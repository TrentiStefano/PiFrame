import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';

class ExtensionUiDialog extends ConsumerStatefulWidget {
  final String sessionId;
  final Map<String, dynamic> request;

  const ExtensionUiDialog({
    super.key,
    required this.sessionId,
    required this.request,
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
  bool _isClaimedByMe = false;
  bool _isClaimChecked = false;
  late TextEditingController _textController;
  String? _selectedOption;
  Timer? _countdownTimer;
  StreamSubscription? _resolutionSubscription;
  bool _isResponding = false;
  String? _responseError;
  int _secondsRemaining = 0;

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
    if (options.isNotEmpty) {
      _selectedOption = options.first;
    }

    final timeoutMs = widget.request['timeoutMs'] as int?;
    if (timeoutMs != null && timeoutMs > 0) {
      _secondsRemaining = (timeoutMs / 1000).ceil();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 1) {
          setState(() => _secondsRemaining--);
        } else {
          timer.cancel();
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }

    final client = ref.read(pcpClientProvider);
    _resolutionSubscription = client?.events(widget.sessionId).listen((event) {
      if (event.type == 'ui.resolved' &&
          event.payload['requestId'] == widget.request['requestId']) {
        if (mounted && !_isResponding) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });
    _attemptClaim();
  }

  Future<void> _attemptClaim() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    final requestId = widget.request['requestId']?.toString() ?? '';
    try {
      final res = await client.claimUiRequest(widget.sessionId, requestId);
      if (mounted) {
        setState(() {
          _isClaimedByMe = (res['data'] as Map?)?['claimed'] == true;
          _isClaimChecked = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isClaimedByMe = false;
          _isClaimChecked = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _resolutionSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendResponse({
    dynamic value,
    bool? confirmed,
    bool? cancelled,
  }) async {
    if (_isResponding) return;
    if (!_isClaimedByMe) {
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    setState(() => _isResponding = true);
    try {
      await client.respondUiRequest(
        widget.sessionId,
        widget.request['requestId']?.toString() ?? '',
        value: value,
        confirmed: confirmed,
        cancelled: cancelled,
      );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isResponding = false;
          _responseError = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final method = widget.request['method']?.toString() ?? 'confirm';
    final title =
        widget.request['title']?.toString() ?? 'Richiesta di Interazione';
    final message = widget.request['message']?.toString() ?? '';
    final placeholder = widget.request['placeholder']?.toString() ?? '';
    final options =
        (widget.request['options'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 20, color: tokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_secondsRemaining > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
            const SizedBox(height: 12),

            // Lock banner if claimed by another client
            if (_isClaimChecked && !_isClaimedByMe) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: tokens.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.borderStrong),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
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
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Body based on method
            if (method == 'select') ...[
              ...options.map((opt) {
                final isSelected = _selectedOption == opt;
                return InkWell(
                  onTap: _isClaimedByMe
                      ? () => setState(() => _selectedOption = opt)
                      : null,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: isSelected
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
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
              }),
            ] else if (method == 'input') ...[
              TextField(
                controller: _textController,
                enabled: _isClaimedByMe,
                style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                decoration: InputDecoration(hintText: placeholder),
              ),
            ] else if (method == 'editor') ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: TextField(
                  controller: _textController,
                  enabled: _isClaimedByMe,
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
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            if (_responseError != null)
              Text(_responseError!, style: TextStyle(color: tokens.danger)),

            // Actions row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isResponding
                      ? null
                      : () => _sendResponse(cancelled: true),
                  child: Text(
                    'Annulla',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isClaimedByMe && !_isResponding
                      ? () {
                          if (method == 'confirm') {
                            _sendResponse(confirmed: true);
                          } else if (method == 'select') {
                            _sendResponse(value: _selectedOption);
                          } else {
                            _sendResponse(value: _textController.text);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.accentContrast,
                  ),
                  child: Text(method == 'confirm' ? 'Conferma' : 'Invia'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
