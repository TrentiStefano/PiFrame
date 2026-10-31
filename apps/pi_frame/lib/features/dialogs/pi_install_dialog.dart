import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/pi_install/pi_install_service.dart';

class PiInstallDialog extends ConsumerStatefulWidget {
  final PiInstallService? customService;

  const PiInstallDialog({
    super.key,
    this.customService,
  });

  static Future<bool?> show(
    BuildContext context, {
    PiInstallService? customService,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: context.tokens.overlay,
      builder: (_) => PiInstallDialog(customService: customService),
    );
  }

  @override
  ConsumerState<PiInstallDialog> createState() => _PiInstallDialogState();
}

class _PiInstallDialogState extends ConsumerState<PiInstallDialog> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _logSubscription;

  bool _isInstalling = false;
  bool _isDone = false;
  bool _isSuccess = false;
  String _logOutput = '';

  @override
  void dispose() {
    _logSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _startInstall() async {
    final PiInstallService service =
        widget.customService ?? ref.read(piInstallServiceProvider);
    setState(() {
      _isInstalling = true;
      _isDone = false;
      _isSuccess = false;
      _logOutput = '';
    });

    try {
      _logSubscription = service.installPiAgent().listen(
        (chunk) {
          if (!mounted) return;
          setState(() {
            _logOutput += chunk;
            if (chunk.contains('[SUCCESSO]')) {
              _isSuccess = true;
            }
          });
          _scrollToBottom();
        },
        onError: (err) {
          if (!mounted) return;
          setState(() {
            _logOutput += '\n[ERRORE] $err\n';
            _isSuccess = false;
          });
          _scrollToBottom();
        },
        onDone: () async {
          if (!mounted) return;
          final installed = await service.isPiInstalled();
          if (!mounted) return;
          setState(() {
            _isInstalling = false;
            _isDone = true;
            _isSuccess = _isSuccess || installed;
          });
          if (_isSuccess) {
            await service.markFirstRunCompleted();
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _isDone = true;
        _isSuccess = false;
        _logOutput += '\n[ECCEZIONE] $e\n';
      });
    }
  }

  Future<void> _dismiss(bool completed) async {
    final PiInstallService service =
        widget.customService ?? ref.read(piInstallServiceProvider);
    await service.markFirstRunCompleted();
    if (mounted) {
      Navigator.of(context).pop(completed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 620,
          maxHeight: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                    ),
                    child: Icon(Icons.terminal, color: tokens.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Installazione Pi Coding Agent',
                          style: TextStyle(
                            fontFamily: tokens.headingFontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: tokens.textPrimary,
                          ),
                        ),
                        Text(
                          'Configurazione automatica iniziale',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Content based on state
              Expanded(
                child: _isInstalling || _isDone
                    ? _buildConsoleView(tokens)
                    : _buildPromptView(tokens),
              ),

              const SizedBox(height: 18),

              // Actions
              _buildActions(tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptView(FrameTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: tokens.info, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pi Coding Agent non rilevato',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'PiFrame utilizza pi-coding-agent (@earendil-works/pi-coding-agent) per alimentare le sessioni e gli strumenti dell\'agente. Non è stato rilevato alcun comando "pi" nel sistema.',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Vuoi procedere con l\'installazione automatica ufficiale adesso?',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          kIsWeb || !Platform.isWindows
              ? 'Comando: curl -fsSL https://pi.dev/install.sh | sh\n(installazione ufficiale con configurazione automatica dei prerequisiti)'
              : 'Comando: irm https://pi.dev/install.ps1 | iex\n(installazione ufficiale con configurazione automatica dei prerequisiti)',
          style: TextStyle(
            fontFamily: tokens.monoFontFamily,
            fontSize: 11,
            color: tokens.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildConsoleView(FrameTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isInstalling) ...[
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Installazione di pi-coding-agent in corso...',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ] else if (_isDone) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (_isSuccess ? tokens.success : tokens.danger)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: (_isSuccess ? tokens.success : tokens.danger)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isSuccess ? Icons.check_circle : Icons.error_outline,
                  color: _isSuccess ? tokens.success : tokens.danger,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isSuccess
                        ? 'Installazione completata con successo!'
                        : 'Installazione non riuscita. Verifica i log sottostanti.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isSuccess ? tokens.success : tokens.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.border),
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SelectableText(
                _logOutput.isEmpty ? 'In attesa di output...\n' : _logOutput,
                style: TextStyle(
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 11,
                  color: tokens.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions(FrameTokens tokens) {
    if (_isInstalling) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Attendere il completamento...',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
        ],
      );
    }

    if (_isDone) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!_isSuccess) ...[
            OutlinedButton(
              key: const ValueKey('pi-install-retry-btn'),
              onPressed: _startInstall,
              child: const Text('Riprova'),
            ),
            const SizedBox(width: 10),
          ],
          FilledButton(
            key: const ValueKey('pi-install-done-btn'),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.accentContrast,
            ),
            onPressed: () => _dismiss(_isSuccess),
            child: Text(_isSuccess ? 'Inizia' : 'Chiudi'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: const ValueKey('pi-install-later-btn'),
          onPressed: () => _dismiss(false),
          child: Text(
            'Più tardi',
            style: TextStyle(color: tokens.textMuted),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          key: const ValueKey('pi-install-now-btn'),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.accent,
            foregroundColor: tokens.accentContrast,
          ),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Installa adesso'),
          onPressed: _startInstall,
        ),
      ],
    );
  }
}
