import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import '../../data/daemon/daemon_providers.dart';

class SessionsSidebar extends ConsumerWidget {
  const SessionsSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sessioni',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add, color: tokens.accent, size: 20),
                  tooltip: 'Nuova Sessione',
                  onPressed: () async {
                    final client = ref.read(pcpClientProvider);
                    if (client == null) return;
                    final cmd = PcpCommand(
                      protocol: 1,
                      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
                      ts: DateTime.now().millisecondsSinceEpoch,
                      commandId: 'crt_${DateTime.now().millisecondsSinceEpoch}',
                      type: 'session.create',
                      payload: {},
                    );
                    final res = await client.sendCommand(cmd);
                    final data = res['data'] as Map<String, dynamic>?;
                    final session = data?['session'] as Map<String, dynamic>?;
                    final sid = session?['id'] as String?;
                    if (sid != null) {
                      ref.read(activeSessionIdProvider.notifier).state = sid;
                      ref.invalidate(sessionListProvider);
                    }
                  },
                ),
              ],
            ),
          ),

          // Session list
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) {
                if (sessions.isEmpty) {
                  return Center(
                    child: Text(
                      'Nessuna sessione trovata',
                      style: TextStyle(color: tokens.textMuted, fontSize: 13),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final id = s['id'] as String? ?? 's';
                    final name = s['name'] as String? ?? id;
                    final isSelected = id == activeId;

                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: tokens.surfaceElevated,
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? tokens.accent : tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        s['cwd'] as String? ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textMuted, fontSize: 11),
                      ),
                      onTap: () {
                        ref.read(activeSessionIdProvider.notifier).state = id;
                      },
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
              ),
              error: (err, _) => Center(
                child: Text('Errore: $err', style: TextStyle(color: tokens.danger, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
