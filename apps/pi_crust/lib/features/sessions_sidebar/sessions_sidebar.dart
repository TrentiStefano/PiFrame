import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import 'session_actions.dart';
import '../../data/daemon/daemon_providers.dart';
import '../command_palette/command_palette.dart';
import '../session_tree/session_tree_dialog.dart';
import '../workspace/repository_workspace.dart';

bool _isWorkerSession(Map<String, dynamic> session) {
  final name = (session['name'] ?? '').toString().toLowerCase();
  final id = (session['id'] ?? '').toString().toLowerCase();
  return name.contains('worker#') || id.contains('worker#');
}

String _sessionFolder(Map<String, dynamic> session) {
  final gitRoot = (session['gitRoot'] ?? '').toString().trim();
  return gitRoot.isNotEmpty ? gitRoot : (session['cwd'] ?? '').toString();
}

String _folderName(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return segments.isEmpty ? 'Sessioni' : segments.last;
}

class SessionsSidebar extends ConsumerStatefulWidget {
  final VoidCallback? onSessionSelected;

  const SessionsSidebar({super.key, this.onSessionSelected});

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'active', 'repo'
  bool _creating = false;
  final Set<String> _collapsedFolders = {};

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
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
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
    if (!await resolveDirtyRepository(
      context,
      ref,
      ref.read(activeSessionIdProvider),
    )) {
      return;
    }

    try {
      final res = await client.cloneSession(sessionId);
      if (!mounted || !context.mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        if (!await switchSessionSafely(context, ref, newSid)) return;
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
    final activeSessionCwd = activeId != null
        ? ref.watch(sessionStateFamily(activeId)).cwd
        : '';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(right: BorderSide(color: tokens.borderStrong, width: 1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sessioni',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 30,
                      height: 1.0,
                      fontFamily: tokens.headingFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: tokens.textMuted, size: 18),
                  tooltip: 'Aggiorna sessioni',
                  onPressed: () {
                    ref.invalidate(sessionListProvider);
                    final active = ref.read(activeSessionIdProvider);
                    if (active != null) {
                      ref.read(pcpClientProvider)?.attach(active);
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add, color: tokens.accent, size: 20),
                  tooltip: 'Nuova Sessione',
                  onPressed: _creating || ref.watch(pcpClientProvider) == null
                      ? null
                      : () async {
                          setState(() => _creating = true);
                          await createSession(context, ref);
                          if (mounted) {
                            setState(() => _creating = false);
                            widget.onSessionSelected?.call();
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
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Cerca sessioni...',
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: tokens.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: tokens.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
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
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'Tutte', tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('active', 'Gestite', tokens),
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
                  if (_isWorkerSession(s)) return false;
                  final id = (s['id'] as String? ?? '').toLowerCase();
                  final name = (s['name'] as String? ?? '').toLowerCase();
                  final cwd = (s['cwd'] as String? ?? '').toLowerCase();
                  final preview = (s['lastMessagePreview'] as String? ?? '')
                      .toLowerCase();
                  final isActive = s['isActive'] == true;

                  // Text search
                  if (_searchQuery.isNotEmpty) {
                    final match =
                        id.contains(_searchQuery) ||
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
                    var activeGroup = activeSessionCwd;
                    for (final candidate in allSessions) {
                      if (candidate['id'] == activeId) {
                        activeGroup = _sessionFolder(candidate);
                        break;
                      }
                    }
                    if (_sessionFolder(s) != activeGroup) return false;
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

                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final session in filtered) {
                  grouped
                      .putIfAbsent(_sessionFolder(session), () => [])
                      .add(session);
                }
                final rows =
                    <({String? folder, Map<String, dynamic>? session})>[];
                for (final group in grouped.entries) {
                  rows.add((folder: group.key, session: null));
                  if (!_collapsedFolders.contains(group.key)) {
                    rows.addAll(
                      group.value.map(
                        (session) => (folder: null, session: session),
                      ),
                    );
                  }
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row.session == null) {
                      final folder = row.folder ?? '';
                      final collapsed = _collapsedFolders.contains(folder);
                      return Material(
                        color: tokens.chassis,
                        child: ListTile(
                          key: ValueKey('session-folder:$folder'),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Icon(
                            collapsed
                                ? Icons.folder_outlined
                                : Icons.folder_open_outlined,
                            size: 17,
                            color: tokens.accent,
                          ),
                          title: Text(
                            _folderName(folder),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            folder.isEmpty ? 'Cartella non nota' : folder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          trailing: Icon(
                            collapsed ? Icons.chevron_right : Icons.expand_more,
                            size: 18,
                            color: tokens.textMuted,
                          ),
                          onTap: () => setState(() {
                            if (collapsed) {
                              _collapsedFolders.remove(folder);
                            } else {
                              _collapsedFolders.add(folder);
                            }
                          }),
                        ),
                      );
                    }
                    final s = row.session!;
                    final id = s['id'] as String? ?? 's';
                    final name = s['name'] as String? ?? id;
                    final cwd = s['cwd'] as String? ?? '';
                    final preview = s['lastMessagePreview'] as String?;
                    final isSelected = id == activeId;
                    final isActive = s['isActive'] == true;

                    return Padding(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 2,
                        bottom: 1,
                      ),
                      child: Material(
                        color: isSelected
                            ? tokens.displaySurface
                            : tokens.chassis,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          side: BorderSide(
                            color: isSelected
                                ? tokens.focusRing
                                : tokens.border,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          selected: isSelected,
                          selectedColor: tokens.displayText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                          ),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          minVerticalPadding: 2,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 0,
                          ),
                          leading: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? tokens.displayText
                                  : (isActive
                                        ? tokens.agentSettled
                                        : tokens.textMuted.withValues(
                                            alpha: 0.5,
                                          )),
                              border: Border.all(color: tokens.borderStrong),
                            ),
                          ),
                          title: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? tokens.displayText
                                  : tokens.textPrimary,
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            preview != null && preview.isNotEmpty
                                ? preview
                                : cwd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? tokens.displayText.withValues(alpha: 0.8)
                                  : tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Azioni sessione',
                            icon: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: isSelected
                                  ? tokens.displayText
                                  : tokens.textMuted,
                            ),
                            color: tokens.surfaceElevated,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
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
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Rinomina',
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'tree',
                                height: 32,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.account_tree_outlined,
                                      size: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Albero rami',
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'clone',
                                height: 32,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.copy_outlined,
                                      size: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Duplica',
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            if (await switchSessionSafely(context, ref, id)) {
                              widget.onSessionSelected?.call();
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: tokens.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Errore: $err',
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text(
                      'Impostazioni',
                      style: TextStyle(fontSize: 12),
                    ),
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
    return Semantics(
      selected: isSelected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? tokens.displayText : tokens.textPrimary,
          backgroundColor: isSelected
              ? tokens.surfaceElevated
              : tokens.background,
          side: BorderSide(
            color: isSelected ? tokens.focusRing : tokens.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: TextStyle(
            fontSize: 11,
            fontFamily: tokens.uiFontFamily,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onPressed: () => setState(() => _filterMode = mode),
        child: Text(label),
      ),
    );
  }
}
