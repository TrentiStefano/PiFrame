import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';
import '../../data/daemon/daemon_providers.dart';
import '../command_palette/command_palette.dart';
import '../session_tree/session_tree_dialog.dart';

class SessionsSidebar extends ConsumerStatefulWidget {
  const SessionsSidebar({super.key});

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'active', 'repo'

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showRenameDialog(String sessionId, String currentName) async {
    final tokens = context.tokens;
    final textController = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.border, width: 1),
        ),
        title: Text(
          'Rinomina Sessione',
          style: TextStyle(color: tokens.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: tokens.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Nome sessione...',
            hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: tokens.accent),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.surface,
            ),
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final client = ref.read(pcpClientProvider);
      if (client != null) {
        try {
          await client.renameSession(sessionId, newName);
          ref.invalidate(sessionListProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sessione rinominata in "$newName"'),
                backgroundColor: tokens.surfaceElevated,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Errore rinomina: $e'),
                backgroundColor: tokens.danger,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _cloneSession(String sessionId) async {
    final tokens = context.tokens;
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    try {
      final res = await client.cloneSession(sessionId);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        ref.read(activeSessionIdProvider.notifier).state = newSid;
        ref.invalidate(sessionListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sessione duplicata: $newSid'),
              backgroundColor: tokens.surfaceElevated,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore duplicazione: $e'),
            backgroundColor: tokens.danger,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final activeSessionCwd = activeId != null ? ref.watch(sessionStateFamily(activeId)).cwd : '';

    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.border, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

          // Search Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cerca sessioni...',
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                prefixIcon: Icon(Icons.search, size: 16, color: tokens.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 14, color: tokens.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: tokens.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.accent),
                ),
              ),
            ),
          ),

          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border, width: 1)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'Tutte', tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('active', 'Attive', tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('repo', 'Questo repo', tokens),
                ],
              ),
            ),
          ),

          // Session list
          Expanded(
            child: sessionsAsync.when(
              data: (allSessions) {
                // Apply search and filter
                final filtered = allSessions.where((s) {
                  final id = (s['id'] as String? ?? '').toLowerCase();
                  final name = (s['name'] as String? ?? '').toLowerCase();
                  final cwd = (s['cwd'] as String? ?? '').toLowerCase();
                  final preview = (s['lastMessagePreview'] as String? ?? '').toLowerCase();
                  final isActive = s['isActive'] == true || s['id'] == activeId;

                  // Text search
                  if (_searchQuery.isNotEmpty) {
                    final match = id.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        cwd.contains(_searchQuery) ||
                        preview.contains(_searchQuery);
                    if (!match) return false;
                  }

                  // Mode filter
                  if (_filterMode == 'active' && !isActive) {
                    return false;
                  }
                  if (_filterMode == 'repo' && activeSessionCwd.isNotEmpty) {
                    if ((s['cwd'] as String? ?? '') != activeSessionCwd) {
                      return false;
                    }
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchQuery.isNotEmpty || _filterMode != 'all'
                            ? 'Nessuna sessione corrisponde ai filtri'
                            : 'Nessuna sessione trovata',
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final s = filtered[index];
                    final id = s['id'] as String? ?? 's';
                    final name = s['name'] as String? ?? id;
                    final cwd = s['cwd'] as String? ?? '';
                    final preview = s['lastMessagePreview'] as String?;
                    final isSelected = id == activeId;
                    final isActive = s['isActive'] == true || isSelected;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: isSelected ? tokens.accent : tokens.surface,
                            width: 3,
                          ),
                          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5), width: 0.5),
                        ),
                      ),
                      child: Material(
                        color: isSelected ? tokens.surfaceElevated : tokens.surface,
                        child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? tokens.accent
                                : (isActive ? tokens.agentSettled : tokens.textMuted.withValues(alpha: 0.5)),
                          ),
                        ),
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
                          preview != null && preview.isNotEmpty ? preview : cwd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tokens.textMuted, fontSize: 11),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 15, color: tokens.textMuted),
                          color: tokens.surfaceElevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            side: BorderSide(color: tokens.border),
                          ),
                          onSelected: (action) {
                            if (action == 'rename') {
                              _showRenameDialog(id, name);
                            } else if (action == 'tree') {
                              SessionTreeDialog.show(context, sessionId: id);
                            } else if (action == 'clone') {
                              _cloneSession(id);
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'rename',
                              height: 32,
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 14, color: tokens.textSecondary),
                                  const SizedBox(width: 8),
                                  Text('Rinomina', style: TextStyle(color: tokens.textPrimary, fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'tree',
                              height: 32,
                              child: Row(
                                children: [
                                  Icon(Icons.account_tree_outlined, size: 14, color: tokens.textSecondary),
                                  const SizedBox(width: 8),
                                  Text('Albero rami', style: TextStyle(color: tokens.textPrimary, fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'clone',
                              height: 32,
                              child: Row(
                                children: [
                                  Icon(Icons.copy_outlined, size: 14, color: tokens.textSecondary),
                                  const SizedBox(width: 8),
                                  Text('Duplica', style: TextStyle(color: tokens.textPrimary, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          ref.read(activeSessionIdProvider.notifier).state = id;
                        },
                      ),
                    ),
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

          // Bottom utility bar: Command Palette & Settings
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Impostazioni', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      ref.read(showSettingsProvider.notifier).state = true;
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search, size: 16, color: tokens.textMuted),
                  tooltip: 'Command Palette (Ctrl+K)',
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
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String mode, String label, CrustTokens tokens) {
    final isSelected = _filterMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      onTap: () {
        setState(() {
          _filterMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accent.withValues(alpha: 0.15) : tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? tokens.accent : tokens.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
