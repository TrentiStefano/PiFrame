import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/transcript/transcript_view.dart';
import '../features/composer/composer.dart';
import '../features/context_panel/context_panel.dart';
import '../features/command_palette/command_palette.dart';
import '../features/settings/settings_view.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final connStateAsync = ref.watch(connectionStateProvider);
    final activeSessionId = ref.watch(activeSessionIdProvider);
    final isSettingsOpen = ref.watch(showSettingsProvider);

    final connState = connStateAsync.value ?? DaemonConnectionState.disconnected;
    final isDisconnected = connState != DaemonConnectionState.connected;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyK &&
              (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
            CommandPalette.show(
              context,
              onOpenSettings: () {
                ref.read(showSettingsProvider.notifier).state = true;
              },
            );
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: tokens.background,
        drawer: const Drawer(width: 290, child: SessionsSidebar()),
        appBar: MediaQuery.sizeOf(context).width < 900 ? AppBar(
          backgroundColor: tokens.surface,
          foregroundColor: tokens.textPrimary,
          title: const Text('Pi-Crust'),
          toolbarHeight: 40,
        ) : null,
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
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(daemonEndpointProvider),
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                ),

              // View routing: Settings View or Main 3-Column Layout
              Expanded(
                child: isSettingsOpen
                    ? SettingsView(
                        onClose: () {
                          ref.read(showSettingsProvider.notifier).state = false;
                        },
                      )
                    : LayoutBuilder(
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
                                            const SizedBox(height: 16),
                                            OutlinedButton.icon(
                                              icon: const Icon(Icons.search, size: 16),
                                              label: const Text('Command Palette (Ctrl+K)'),
                                              onPressed: () {
                                                CommandPalette.show(
                                                  context,
                                                  onOpenSettings: () {
                                                    ref.read(showSettingsProvider.notifier).state = true;
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          Expanded(
                                            child: TranscriptView(key: ValueKey('transcript_$activeSessionId'), sessionId: activeSessionId),
                                          ),
                                          Composer(key: ValueKey('composer_$activeSessionId'), sessionId: activeSessionId),
                                        ],
                                      ),
                              ),

                              // Column 3: Context Panel
                              if (showContextPanel && activeSessionId != null)
                                ContextPanel(key: ValueKey('context_$activeSessionId'), sessionId: activeSessionId),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
