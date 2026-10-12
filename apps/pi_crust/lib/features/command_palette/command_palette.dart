import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../composer/composer_draft.dart';
import '../sessions_sidebar/session_actions.dart';

class PaletteAction {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() onExecute;

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

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onOpenSettings,
  }) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierColor: context.tokens.overlay,
      builder: (_) => CommandPalette(onOpenSettings: onOpenSettings),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _searchController = TextEditingController();
  int _selectedIndex = 0;
  bool _executing = false;
  final _scrollController = ScrollController();

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(
      () => _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1),
    );
    if (_scrollController.hasClients) {
      final offset = (_selectedIndex * 72.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(offset);
    }
  }

  Future<void> _execute(PaletteAction action) async {
    if (_executing) return;
    setState(() => _executing = true);
    try {
      await action.onExecute();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Azione non riuscita: $error')));
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
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
          if (pcpClient == null) return;
          await createSession(context, ref, name: 'Nuova Sessione');
          if (!mounted || !context.mounted) return;
          ref.invalidate(sessionListProvider);
        },
      ),
      if (activeSessionId != null &&
          !ref.watch(sessionStateFamily(activeSessionId)).readOnly) ...[
        PaletteAction(
          id: 'compact',
          title: 'Compatta contesto',
          subtitle: 'Esegui manual compaction per ridurre i token',
          icon: Icons.compress,
          onExecute: () async {
            await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .compact();
          },
        ),
        PaletteAction(
          id: 'clear_queue',
          title: 'Svuota coda',
          subtitle: 'Rimuovi tutti i messaggi steer e follow-up in attesa',
          icon: Icons.clear_all,
          onExecute: () async {
            await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .clearQueue();
          },
        ),
        PaletteAction(
          id: 'interrupt',
          title: 'Interrompi agente (Esc)',
          subtitle: 'Ferma il modello e ripristina la coda nel composer',
          icon: Icons.stop_circle_outlined,
          onExecute: () async {
            final result = await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .interrupt();
            if (!mounted) return;
            final data = result?['data'] as Map<String, dynamic>? ?? result;
            final queue = data?['queue'];
            if (queue is Map) {
              final restored =
                  [
                        ...?queue['steering'] as List?,
                        ...?queue['followUp'] as List?,
                      ]
                      .whereType<String>()
                      .where((text) => text.trim().isNotEmpty)
                      .join('\n');
              if (restored.isNotEmpty) {
                final draft = ref.read(
                  composerDraftProvider(activeSessionId).notifier,
                );
                draft.state = draft.state.trim().isEmpty
                    ? restored
                    : '${draft.state}\n$restored';
              }
            }
          },
        ),
      ],
      PaletteAction(
        id: 'settings',
        title: 'Apri Impostazioni',
        subtitle: 'Configura percorso Pi, timeout worker e aspetto',
        icon: Icons.settings,
        onExecute: () async {
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
      return a.title.toLowerCase().contains(query) ||
          a.subtitle.toLowerCase().contains(query);
    }).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (filtered.isNotEmpty) _execute(filtered[_selectedIndex]);
        },
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 420),
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                children: [
                  // Search Input Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: tokens.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Cerca un\'azione o comando...',
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (_) =>
                                setState(() => _selectedIndex = 0),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
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
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final action = filtered[index];
                              final isSelected = index == _selectedIndex;

                              return InkWell(
                                onTap: _executing
                                    ? null
                                    : () => _execute(action),
                                hoverColor: tokens.surface,
                                child: Container(
                                  color: isSelected
                                      ? tokens.accent.withValues(alpha: 0.1)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        action.icon,
                                        size: 18,
                                        color: isSelected
                                            ? tokens.accent
                                            : tokens.textSecondary,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              action.title,
                                              style: TextStyle(
                                                color: tokens.textPrimary,
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
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
      ),
    );
  }
}
