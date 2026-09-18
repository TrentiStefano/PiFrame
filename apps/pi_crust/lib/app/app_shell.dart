import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/transcript/transcript_view.dart';
import '../features/composer/composer.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final connStateAsync = ref.watch(connectionStateProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);

    final connState = connStateAsync.value ?? DaemonConnectionState.disconnected;
    final isDisconnected = connState != DaemonConnectionState.connected;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top reconnection banner if disconnected
            if (isDisconnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: connState == DaemonConnectionState.reconnecting
                    ? tokens.warning.withValues(alpha: 0.2)
                    : tokens.danger.withValues(alpha: 0.2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: connState == DaemonConnectionState.reconnecting
                            ? tokens.warning
                            : tokens.danger,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      connState == DaemonConnectionState.reconnecting
                          ? 'Riconnessione al daemon in corso...'
                          : 'Daemon disconnesso o non raggiungibile',
                      style: TextStyle(
                        color: connState == DaemonConnectionState.reconnecting
                            ? tokens.warning
                            : tokens.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            // Main 3-column layout
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final showSidebar = width >= 900;
                  final showContextPanel = width > 1300;

                  return Row(
                    children: [
                      // Column 1: Sessions Sidebar
                      if (showSidebar) const SessionsSidebar(),

                      // Column 2: Conversation & Composer
                      Expanded(
                        child: activeSessionId == null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.terminal, size: 48, color: tokens.textMuted),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Seleziona o crea una sessione per iniziare',
                                      style: TextStyle(color: tokens.textSecondary, fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  Expanded(
                                    child: TranscriptView(sessionId: activeSessionId),
                                  ),
                                  Composer(sessionId: activeSessionId),
                                ],
                              ),
                      ),

                      // Column 3: Context Panel
                      if (showContextPanel)
                        Container(
                          width: 280,
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            border: Border(left: BorderSide(color: tokens.border, width: 1)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Contesto Sessione',
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'File modificati, diff e strumenti attivi appariranno qui.',
                                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
