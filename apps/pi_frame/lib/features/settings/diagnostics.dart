import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../app/app_version.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_settings.dart';
import '../../ui/frame_section.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/frame_status_tag.dart';

/// Tests may label synthetic diagnostic fixtures without changing runtime UI.
final diagnosticsFixtureLabelProvider = Provider<String?>((ref) => null);

class DiagnosticsSection extends ConsumerStatefulWidget {
  const DiagnosticsSection({super.key});

  @override
  ConsumerState<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<DiagnosticsSection> {
  bool _isExporting = false;
  String? _exportSuccess;

  Future<void> _exportBundle() async {
    setState(() {
      _isExporting = true;
      _exportSuccess = null;
    });

    try {
      final sessions = await ref.read(sessionListProvider.future);
      final client = ref.read(pcpClientProvider);
      final activeId = ref.read(activeSessionIdProvider);

      Map<String, dynamic> daemonHealth = {};
      if (client != null) {
        try {
          final res = await client.getDaemonConfig();
          daemonHealth = res['data'] as Map<String, dynamic>? ?? res;
        } catch (_) {}
      }

      // Redacted diagnostic bundle (strictly local, secrets scrubbed)
      final bundle = {
        'generatedAt': DateTime.now().toIso8601String(),
        'app': {'name': 'PiFrame', 'version': piFrameVersion, 'protocol': 1},
        'daemon': {
          'status': client?.state.toString() ?? 'unknown',
          'config': {
            'workerIdleTimeoutMs':
                daemonHealth['workerIdleTimeoutMs'] ?? 1800000,
          },
          'token': '[REDACTED]',
        },
        'environment': {
          'activeSessionId': activeId,
          'totalSessionsCount': sessions.length,
          'telemetry': 'DISABLED (no remote telemetry)',
        },
        'sessionsSummary': sessions
            .map(
              (s) => {
                'id': s['id'],
                'name': s['name'],
                'isActive': s['isActive'] ?? false,
                'messageCount': s['messageCount'],
              },
            )
            .toList(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);
      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() {
          _isExporting = false;
          _exportSuccess = strings.diagBundleCopiedRedacted;
        });

        FrameSnackBar.show(
          context,
          message: strings.diagBundleCopiedSnackBar,
        );
      }
    } catch (e) {
      if (mounted) {
        final strings = ref.read(appStringsProvider);
        setState(() {
          _isExporting = false;
          _exportSuccess = strings.diagExportError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final connState =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final sessions = ref.watch(sessionListProvider).value ?? [];
    final fixtureLabel = ref.watch(diagnosticsFixtureLabelProvider);

    final text = FrameText.of(context);

    return ListView(
      padding: const EdgeInsets.all(FrameSpace.x6),
      children: [
        if (fixtureLabel != null) ...[
          Row(
            children: [
              FrameStatusTag(
                key: const ValueKey('diagnostics-fixture-label'),
                label: fixtureLabel,
                tone: FrameStatusTone.warning,
              ),
            ],
          ),
          const SizedBox(height: FrameSpace.x4),
        ],
        // Title & description
        Text(
          strings.diagTitle,
          style: text.title.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: FrameSpace.x2),
        Text(
          strings.diagSubtitle,
          style: text.body.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: FrameSpace.x6),

        // System state card
        FrameSection(
          title: strings.diagRuntimeStateHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetricRow(
                strings.diagDaemonConnection,
                strings.daemonConnectionStateLabel(connState.name),
                tokens,
                // Same daemon vocabulary as the Daemon tab.
                tone: switch (connState) {
                  DaemonConnectionState.connected => FrameStatusTone.success,
                  DaemonConnectionState.disconnected => FrameStatusTone.danger,
                  _ => FrameStatusTone.warning,
                },
              ),
              _buildMetricRow(strings.diagAppVersionLabel, 'v$piFrameVersion', tokens),
              _buildMetricRow(
                strings.diagPcpProtocol,
                'PCP/1 (JSON over WebSocket)',
                tokens,
              ),
              _buildMetricRow(
                strings.diagArchivedSessions,
                '${sessions.length}',
                tokens,
              ),
              _buildMetricRow(
                strings.diagRemoteTelemetry,
                strings.diagTelemetryDisabled,
                tokens,
                tone: FrameStatusTone.success,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Export Diagnostic Bundle
        FrameSection(
          title: strings.diagExportBundleTitle,
          description: strings.diagExportBundleDesc,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                key: const ValueKey('diagnostics-copy-bundle-btn'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, FrameSize.rowForm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FrameSpace.x4,
                  ),
                ),
                icon: _isExporting
                    ? SizedBox(
                        width: FrameSize.icon,
                        height: FrameSize.icon,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accentContrast,
                        ),
                      )
                    : const Icon(Icons.copy, size: FrameSize.icon),
                label: Text(
                  _isExporting
                      ? strings.diagGenerating
                      : strings.diagCopyBundleBtn,
                ),
                onPressed: _isExporting ? null : _exportBundle,
              ),
              if (_exportSuccess != null) ...[
                const SizedBox(height: FrameSpace.x2 + 2),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: FrameSize.icon,
                      color: tokens.agentSettled,
                    ),
                    const SizedBox(width: FrameSpace.x2),
                    Expanded(
                      child: Text(
                        _exportSuccess!,
                        style: text.caption.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    FrameTokens tokens, {
    FrameStatusTone? tone,
  }) {
    final text = FrameText.fromTokens(tokens);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FrameSpace.x1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: text.body.copyWith(color: tokens.textSecondary),
          );
          final valueText = Text(
            value,
            style: text.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          );
          final valueWidget = tone == null
              ? valueText
              : FrameStatusTag(label: value, tone: tone);
          if (constraints.maxWidth < 520) {
            return Padding(
              padding: const EdgeInsets.only(bottom: FrameSpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelWidget,
                  const SizedBox(height: FrameSpace.x1),
                  valueWidget,
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: FrameSpace.x4),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
