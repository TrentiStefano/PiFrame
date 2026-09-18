import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import '../../data/daemon/daemon_providers.dart';

class PaletteAction {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onExecute;

  const PaletteAction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExecute,
  });
}

class CommandPalette extends ConsumerStatefulWidget {
  final VoidCallback? onOpenSettings;

  const CommandPalette({super.key, this.onOpenSettings});

  static Future<void> show(BuildContext context, {VoidCallback? onOpenSettings}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => CommandPalette(onOpenSettings: onOpenSettings),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _searchController = TextEditingController();
  int _selectedIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PaletteAction> _buildActions(BuildContext context) {
    final activeSessionId = ref.read(activeSessionIdProvider);
    final pcpClient = ref.read(pcpClientProvider);

    return [
      PaletteAction(
        id: 'new_session',
        title: 'Crea nuova sessione',
        subtitle: 'Avvia una nuova sessione Pi',
        icon: Icons.add_circle_outline,
        onExecute: () async {
          if (pcpClient != null) {
            final cmd = PcpCommand(
              protocol: 1,
              id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
              ts: DateTime.now().millisecondsSinceEpoch,
              sessionId: '@daemon',
              commandId: 'cs_${DateTime.now().millisecondsSinceEpoch}',
              type: 'session.create',
              payload: {'name': 'Nuova Sessione'},
            );
            final res = await pcpClient.sendCommand(cmd);
            final data = res['data'] as Map<String, dynamic>?;
            final session = (data?['session'] ?? res['session']) as Map<String, dynamic>?;
            if (session != null && session['id'] != null) {
              ref.read(activeSessionIdProvider.notifier).state = session['id'] as String;
              ref.invalidate(sessionListProvider);
            }
          }
        },
      ),
      if (activeSessionId != null) ...[
        PaletteAction(
          id: 'compact',
          title: 'Compatta contesto',
          subtitle: 'Esegui manual compaction per ridurre i token',
          icon: Icons.compress,
          onExecute: () {
            ref.read(sessionStateFamily(activeSessionId).notifier).compact();
          },
        ),
        PaletteAction(
          id: 'clear_queue',
          title: 'Svuota coda',
          subtitle: 'Rimuovi tutti i messaggi steer e follow-up in attesa',
          icon: Icons.clear_all,
          onExecute: () {
            ref.read(sessionStateFamily(activeSessionId).notifier).clearQueue();
          },
        ),
        PaletteAction(
          id: 'interrupt',
          title: 'Interrompi agente (Esc)',
          subtitle: 'Ferma il modello e ripristina la coda nel composer',
          icon: Icons.stop_circle_outlined,
          onExecute: () {
            ref.read(sessionStateFamily(activeSessionId).notifier).interrupt();
          },
        ),
      ],
      PaletteAction(
        id: 'settings',
        title: 'Apri Impostazioni',
        subtitle: 'Configura percorso Pi, timeout worker e aspetto',
        icon: Icons.settings,
        onExecute: () {
          widget.onOpenSettings?.call();
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final allActions = _buildActions(context);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = allActions.where((a) {
      return a.title.toLowerCase().contains(query) || a.subtitle.toLowerCase().contains(query);
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 420),
        child: Material(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          elevation: 16,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Column(
              children: [
                // Search Input Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 20, color: tokens.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: TextStyle(color: tokens.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Cerca un\'azione o comando...',
                            hintStyle: TextStyle(color: tokens.textMuted, fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() => _selectedIndex = 0),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Text(
                          'ESC',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.border),

                // Results list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Nessuna azione trovata',
                            style: TextStyle(color: tokens.textMuted, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final action = filtered[index];
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: () {
                                Navigator.of(context).pop();
                                action.onExecute();
                              },
                              hoverColor: tokens.surface,
                              child: Container(
                                color: isSelected ? tokens.accent.withValues(alpha: 0.1) : null,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(action.icon, size: 18, color: isSelected ? tokens.accent : tokens.textSecondary),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            action.title,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                          Text(
                                            action.subtitle,
                                            style: TextStyle(
                                              color: tokens.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
