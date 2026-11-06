import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../transcript/workflows_provider.dart';

class ExtensionUiDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final Map<String, dynamic> request;
  final bool isCard;
  final VoidCallback? onDismissed;

  const ExtensionUiDialog({
    super.key,
    required this.sessionId,
    required this.request,
    this.isCard = false,
    this.onDismissed,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required Map<String, dynamic> request,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: context.tokens.overlay,
      builder: (_) => ExtensionUiDialog(sessionId: sessionId, request: request),
    );
  }

  @override
  ConsumerState<ExtensionUiDialog> createState() => _ExtensionUiDialogState();
}

class _ExtensionUiDialogState extends ConsumerState<ExtensionUiDialog> {
  // Another client holds the lease. Any other claim failure (offline, timeout, stale) must not lock the user out:
  // the daemon still arbitrates the final answer.
  bool _lockedByOther = false;
  bool _isClaimChecked = false;
  late TextEditingController _textController;
  final FocusNode _customAnswerFocusNode = FocusNode();
  bool _isCustomAnswerSelected = false;
  bool _hasEnteredCustomAnswer = false;
  String? _selectedOption;
  final Set<String> _selectedOptions = {};
  Timer? _countdownTimer;
  StreamSubscription? _resolutionSubscription;
  bool _isResponding = false;
  String? _responseError;
  int _secondsRemaining = 0;

  bool get _isMultiSelect =>
      widget.request['multiSelect'] == true ||
      widget.request['isMultiSelect'] == true;

  /// pi-subagents' `/agents` → `Workflows (N)` entry.
  bool _opensWorkflowsMenu(String? option) =>
      widget.request['method'] == 'select' &&
      widget.request['title'] == 'Agents' &&
      (option?.startsWith('Workflows (') ?? false);

  static const _secretPlaceholderPrefix = 'piframe-secret:';
  bool get _isSecretInput =>
      widget.request['method'] == 'input' &&
      (widget.request['placeholder']?.toString() ?? '').startsWith(
        _secretPlaceholderPrefix,
      );

  bool _isFreeTextOption(String option) => RegExp(
    r'^(?:\d+\.\s*)?type something[.!?]*$',
    caseSensitive: false,
  ).hasMatch(option.trim());

  bool _customAnswerNeedsFollowUp(List<String> options) {
    // The RPC questionnaire interprets these select values as option choices.
    if (!options.any(
      (option) =>
          RegExp(r'^\d+\.\s*').hasMatch(option) && _isFreeTextOption(option),
    )) {
      return false;
    }
    final answer = _textController.text;
    final trimmed = answer.trim();
    if (options.contains(answer)) return true;
    if (RegExp(r'^\d+\.?$').hasMatch(trimmed)) {
      final index = int.tryParse(trimmed.replaceFirst(RegExp(r'\.$'), ''));
      if (index != null && index >= 1 && index <= options.length) return true;
    }
    return options.any((option) {
      final prefix = RegExp(r'^\d+\.\s*').firstMatch(option);
      return prefix != null &&
          option.substring(prefix.end).startsWith('$trimmed — ');
    });
  }

  // The package's RPC fallback embeds numbered preview blocks in the title.
  ({String title, Map<String, String> previews}) _splitRpcPreviews(
    String title,
    List<String> options,
  ) {
    final markers =
        RegExp(
          r'^--- (\d+)\. (.+) preview ---\r?$',
          multiLine: true,
        ).allMatches(title).where((match) {
          final index = int.tryParse(match[1]!) ?? 0;
          return index > 0 &&
              index <= options.length &&
              match.start >= 2 &&
              title.substring(match.start - 2, match.start) == '\n\n' &&
              match.end < title.length &&
              title[match.end] == '\n' &&
              options[index - 1].startsWith('$index. ${match[2]} — ');
        }).toList();
    if (markers.isEmpty) {
      return (title: title, previews: {});
    }
    final previews = <String, String>{};
    for (var i = 0; i < markers.length; i++) {
      final match = markers[i];
      final index = int.parse(match[1]!) - 1;
      if (previews.containsKey(options[index])) {
        return (title: title, previews: {});
      }
      var preview = title.substring(
        match.end + 1,
        i + 1 < markers.length ? markers[i + 1].start : title.length,
      );
      if (i + 1 < markers.length && preview.endsWith('\n\n')) {
        preview = preview.substring(0, preview.length - 2);
      }
      previews[options[index]] = preview;
    }
    return (
      title: title.substring(0, markers.first.start - 2),
      previews: previews,
    );
  }

  void _selectOption(String option) {
    if (_isFreeTextOption(option)) {
      if (_isCustomAnswerSelected) return;
      if (!_hasEnteredCustomAnswer) {
        _textController.clear();
        _hasEnteredCustomAnswer = true;
      }
      setState(() {
        _isCustomAnswerSelected = true;
        _selectedOption = null;
        _selectedOptions.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_lockedByOther) _customAnswerFocusNode.requestFocus();
      });
      return;
    }
    _customAnswerFocusNode.unfocus();
    setState(() {
      _isCustomAnswerSelected = false;
      if (_isMultiSelect) {
        if (!_selectedOptions.remove(option)) _selectedOptions.add(option);
      } else {
        _selectedOption = option;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final prefill = widget.request['prefill']?.toString() ?? '';
    _textController = TextEditingController(text: prefill);

    final options =
        (widget.request['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final selectableOptions = options
        .where((option) => !_isFreeTextOption(option))
        .toList();
    if (selectableOptions.isNotEmpty) {
      _selectedOption = selectableOptions.first;
      _selectedOptions.add(selectableOptions.first);
    }

    final timeoutMs = widget.request['timeoutMs'] as int?;
    if (timeoutMs != null && timeoutMs > 0) {
      _secondsRemaining = (timeoutMs / 1000).ceil();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 1) {
          setState(() => _secondsRemaining--);
        } else {
          timer.cancel();
          if (ref.read(pcpClientProvider) == null) {
            _dismiss();
          } else {
            _sendResponse(cancelled: true);
          }
        }
      });
    }

    final client = ref.read(pcpClientProvider);
    _resolutionSubscription = client?.events(widget.sessionId).listen((event) {
      if (event.type == 'ui.resolved' &&
          event.payload['requestId'] == widget.request['requestId']) {
        if (mounted && !_isResponding) {
          _dismiss();
        }
      }
    });
    _attemptClaim();
  }

  void _dismiss() {
    if (!mounted) return;
    if (widget.isCard) {
      widget.onDismissed?.call();
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _attemptClaim() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final requestId = widget.request['requestId']?.toString() ?? '';
    try {
      final res = await client
          .claimUiRequest(widget.sessionId, requestId)
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _lockedByOther = (res['data'] as Map?)?['claimed'] == false;
          _isClaimChecked = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _lockedByOther = error.toString().contains('claimed by another');
          _isClaimChecked = true;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_isSecretInput) _textController.clear();
    _countdownTimer?.cancel();
    _resolutionSubscription?.cancel();
    _textController.dispose();
    _customAnswerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendResponse({
    dynamic value,
    bool? confirmed,
    bool? cancelled,
  }) async {
    if (_isResponding) return;
    if (_lockedByOther) {
      _dismiss();
      return;
    }
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      setState(() => _responseError = 'Daemon non connesso');
      return;
    }
    setState(() {
      _isResponding = true;
      _responseError = null;
    });
    try {
      await client
          .respondUiRequest(
            widget.sessionId,
            widget.request['requestId']?.toString() ?? '',
            value: value,
            confirmed: confirmed,
            cancelled: cancelled,
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        _dismiss();
      }
    } catch (error) {
      if (!mounted) return;
      // The request is already gone daemon-side (answered elsewhere, aborted or restarted): nothing left to answer.
      if (error.toString().contains('Request not found')) {
        _dismiss();
        return;
      }
      setState(() {
        _isResponding = false;
        _responseError = error is TimeoutException
            ? 'Nessuna risposta dal daemon. Riprova.'
            : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final method = widget.request['method']?.toString() ?? 'confirm';
    final rawTitle =
        widget.request['title']?.toString() ?? 'Richiesta di Interazione';
    final message = widget.request['message']?.toString() ?? '';
    final rawPlaceholder = widget.request['placeholder']?.toString() ?? '';
    final placeholder = _isSecretInput
        ? rawPlaceholder.substring(_secretPlaceholderPrefix.length)
        : rawPlaceholder;
    final options =
        (widget.request['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final parsed = method == 'select'
        ? _splitRpcPreviews(rawTitle, options)
        : (title: rawTitle, previews: <String, String>{});
    final title = parsed.title;
    final canSubmit =
        method != 'select' ||
        (_isCustomAnswerSelected
            ? _textController.text.trim().isNotEmpty
            : _isMultiSelect
            ? _selectedOptions.isNotEmpty
            : _selectedOption != null);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.smart_toy_outlined, size: 18, color: tokens.accent),
            const SizedBox(width: 8),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.15).clamp(
                    40.0,
                    100.0,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            if (_secondsRemaining > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                  border: Border.all(color: tokens.border),
                ),
                child: Text(
                  '${_secondsRemaining}s',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Scrollable body: long messages or many options must never push the answer buttons off screen.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.sizeOf(context).height * 0.4).clamp(
              120.0,
              360.0,
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Lock banner if claimed by another client
                if (_isClaimChecked && _lockedByOther) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: tokens.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.borderStrong),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 15,
                          color: tokens.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Un altro client sta rispondendo a questa richiesta.',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Message content
                if (message.isNotEmpty) ...[
                  Text(
                    message,
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Body based on method
                if (method == 'select')
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final optionRows = options.map((opt) {
                        final isFreeTextOption = _isFreeTextOption(opt);
                        final isSelected = isFreeTextOption
                            ? _isCustomAnswerSelected
                            : _isMultiSelect
                            ? _selectedOptions.contains(opt)
                            : _selectedOption == opt;

                        return InkWell(
                          onTap: !_lockedByOther
                              ? () => _selectOption(opt)
                              : null,
                          onFocusChange: (focused) {
                            if (focused &&
                                parsed.previews.isNotEmpty &&
                                !_isMultiSelect &&
                                !_lockedByOther &&
                                !isSelected) {
                              _selectOption(opt);
                            }
                          },
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isMultiSelect
                                      ? (isSelected
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank)
                                      : (isSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked),
                                  size: 18,
                                  color: isSelected
                                      ? tokens.accent
                                      : tokens.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: isFreeTextOption && isSelected
                                      ? TextField(
                                          key: const ValueKey(
                                            'extension-ui-custom-answer',
                                          ),
                                          controller: _textController,
                                          focusNode: _customAnswerFocusNode,
                                          enabled: !_lockedByOther,
                                          onChanged: (_) => setState(() {}),
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 13,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: 'Scrivi la risposta...',
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                            ),
                                          ),
                                        )
                                      : Text(
                                          opt,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList();
                      final preview = _isCustomAnswerSelected
                          ? null
                          : parsed.previews[_selectedOption];
                      if (preview == null) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: optionRows,
                        );
                      }
                      final fence = RegExp(r'^```[^\n]*\n([\s\S]*?)\n```\s*$')
                          .firstMatch(preview);
                      final previewPane = Container(
                        key: const ValueKey('extension-ui-preview'),
                        constraints: BoxConstraints(
                          maxHeight: (MediaQuery.sizeOf(context).height * 0.25)
                              .clamp(80.0, 200.0),
                        ),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: tokens.border),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                        child: SingleChildScrollView(
                          key: ValueKey(_selectedOption),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              fence?.group(1) ?? preview,
                              softWrap: false,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 12,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ),
                        ),
                      );
                      if (constraints.maxWidth >= 580) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: optionRows,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: previewPane),
                          ],
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...optionRows,
                          const SizedBox(height: 8),
                          previewPane,
                        ],
                      );
                    },
                  )
                else if (method == 'input') ...[
                  TextField(
                    controller: _textController,
                    enabled: !_lockedByOther,
                    obscureText: _isSecretInput,
                    autocorrect: !_isSecretInput,
                    enableSuggestions: !_isSecretInput,
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: placeholder,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                  ),
                ] else if (method == 'editor') ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: TextField(
                      controller: _textController,
                      enabled: !_lockedByOther,
                      maxLines: null,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 12.5,
                        fontFamily: tokens.monoFontFamily,
                      ),
                      decoration: InputDecoration(
                        hintText: placeholder.isNotEmpty
                            ? placeholder
                            : 'Inserisci testo...',
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        if (_responseError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _responseError!,
              style: TextStyle(color: tokens.danger, fontSize: 12),
            ),
          ),

        // Actions row
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isResponding
                  ? null
                  : () => _sendResponse(cancelled: true),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(
                'Annulla',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: !_lockedByOther && !_isResponding && canSubmit
                  ? () {
                      if (method == 'confirm') {
                        _sendResponse(confirmed: true);
                      } else if (method == 'select') {
                        if (_isCustomAnswerSelected) {
                          _sendResponse(
                            value: _customAnswerNeedsFollowUp(options)
                                ? options.firstWhere(_isFreeTextOption)
                                : _textController.text,
                          );
                        } else if (_isMultiSelect) {
                          _sendResponse(value: _selectedOptions.toList());
                        } else if (_opensWorkflowsMenu(_selectedOption)) {
                          // RPC cannot render pi-subagents' custom workflow dialog, so its
                          // menu would reopen forever; cancel it and show PiFrame's panel.
                          ref
                              .read(agentActivityPanelOpenProvider(widget.sessionId).notifier)
                              .state = true;
                          _sendResponse(cancelled: true);
                        } else {
                          _sendResponse(value: _selectedOption);
                        }
                      } else {
                        _sendResponse(value: _textController.text);
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.accentContrast,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              child: Text(
                method == 'confirm' ? 'Conferma' : 'Invia',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    final focusContent = method == 'select' && parsed.previews.isNotEmpty
        ? Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (_lockedByOther ||
                  _isMultiSelect ||
                  _customAnswerFocusNode.hasFocus ||
                  event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
                  ? 1
                  : event.logicalKey == LogicalKeyboardKey.arrowUp
                  ? -1
                  : 0;
              if (direction == 0 || options.isEmpty) {
                return KeyEventResult.ignored;
              }
              final current = _isCustomAnswerSelected
                  ? options.indexWhere(_isFreeTextOption)
                  : options.indexOf(_selectedOption ?? '');
              final index = (current + direction).clamp(0, options.length - 1);
              if (index != current) _selectOption(options[index]);
              return KeyEventResult.handled;
            },
            child: content,
          )
        : content;

    if (widget.isCard) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 820),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(
            color: tokens.accent.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.overlay.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: focusContent,
      );
    }

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: focusContent,
      ),
    );
  }
}
