import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';

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

      // Redacted Diagnostic Bundle (D16: strictly local, secrets scrubbed)
      final bundle = {
        'generatedAt': DateTime.now().toIso8601String(),
        'app': {
          'name': 'Pi-Crust',
          'version': '0.1.0',
          'protocol': 1,
        },
        'daemon': {
          'status': client?.state.toString() ?? 'unknown',
          'config': {
            'workerIdleTimeoutMs': daemonHealth['workerIdleTimeoutMs'] ?? 1800000,
          },
          'token': '[REDACTED]',
        },
        'environment': {
          'activeSessionId': activeId,
          'totalSessionsCount': sessions.length,
          'telemetry': 'DISABLED (D16: zero remote telemetry)',
        },
        'sessionsSummary': sessions.map((s) => {
          'id': s['id'],
          'name': s['name'],
          'isActive': s['isActive'] ?? false,
          'messageCount': s['messageCount'] ?? 0,
        }).toList(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);
      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccess = 'Bundle diagnostico copiato negli appunti (tutti i segreti sono stati redatti con [REDACTED])';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bundle diagnostico copiato negli appunti!'),
            backgroundColor: context.tokens.surfaceElevated,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccess = 'Errore durante esportazione: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final connState = ref.watch(connectionStateProvider).value ?? DaemonConnectionState.disconnected;
    final sessions = ref.watch(sessionListProvider).value ?? [];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Title & description
        Text(
          'Diagnostica Locale & Stato di Sistema',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tutti i dati di diagnostica rimangono confinati sulla tua macchina locale. '
          'In conformità con la politica di privacy D16, nessun dato viene mai trasmesso a server esterni.',
          style: TextStyle(color: tokens.textSecondary, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),

        // System state card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STATO ATTUALE DEL RUNTIME',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildMetricRow('Connessione Daemon', connState.name.toUpperCase(), tokens,
                  color: connState == DaemonConnectionState.connected ? tokens.agentSettled : tokens.warning),
              _buildMetricRow('Versione Pi-Crust App', 'v0.1.0', tokens),
              _buildMetricRow('Protocollo PCP', 'PCP/1 (JSON over WebSocket)', tokens),
              _buildMetricRow('Sessioni archiviate', '${sessions.length}', tokens),
              _buildMetricRow('Telemetria Remota', 'DISABILITATA (Zero Analytics)', tokens, color: tokens.agentSettled),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Export Diagnostic Bundle
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bug_report_outlined, color: tokens.accent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Esporta Bundle Diagnostico',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Genera un rapporto diagnostico completo formattato in JSON. '
                'Tutti i token, credenziali e percorsi sensibili vengono automaticamente anonimizzati e redatti prima della copia negli appunti.',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radiusSm)),
                ),
                icon: _isExporting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: tokens.surface),
                      )
                    : const Icon(Icons.copy, size: 16),
                label: Text(
                  _isExporting ? 'Generazione...' : 'Copia Bundle Diagnostico negli Appunti',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _isExporting ? null : _exportBundle,
              ),
              if (_exportSuccess != null) ...[
                const SizedBox(height: 10),
                Text(
                  _exportSuccess!,
                  style: TextStyle(color: tokens.agentSettled, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, CrustTokens tokens, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: color ?? tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
