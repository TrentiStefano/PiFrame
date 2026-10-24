import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/frame_snack_bar.dart';
import '../composer/composer_draft.dart';
import '../workspace/repository_workspace.dart';
import 'browser_controller.dart';
import 'browser_models.dart';

class WebBrowserPane extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onCollapse;
  final List<WorkspacePane>? companionTabs;
  final WorkspacePane? activeCompanionTab;
  final ValueChanged<WorkspacePane>? onSelectCompanionTab;

  const WebBrowserPane({
    super.key,
    required this.sessionId,
    this.onCollapse,
    this.companionTabs,
    this.activeCompanionTab,
    this.onSelectCompanionTab,
  });

  @override
  ConsumerState<WebBrowserPane> createState() => _WebBrowserPaneState();
}

class _WebBrowserPaneState extends ConsumerState<WebBrowserPane> {
  late final TextEditingController _urlController;
  late final TextEditingController _homeSearchController;
  final FocusNode _urlFocusNode = FocusNode();
  String? _lastSyncedUrl;

  @override
  void initState() {
    super.initState();
    final activeTab = ref.read(webBrowserProvider).activeTab;
    _urlController = TextEditingController(
      text: activeTab.isHome ? '' : activeTab.url,
    );
    _homeSearchController = TextEditingController();
    _lastSyncedUrl = activeTab.url;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _homeSearchController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _syncUrl(WebBrowserTab activeTab) {
    if (!_urlFocusNode.hasFocus && _lastSyncedUrl != activeTab.url) {
      _lastSyncedUrl = activeTab.url;
      final newText = activeTab.isHome ? '' : activeTab.url;
      if (_urlController.text != newText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_urlFocusNode.hasFocus) {
            _urlController.text = newText;
          }
        });
      }
    }
  }

  void _submitUrl() {
    final text = _urlController.text.trim();
    if (text.isEmpty) return;
    _urlFocusNode.unfocus();
    ref.read(webBrowserProvider.notifier).navigate(text);
  }

  void _submitHomeSearch() {
    final text = _homeSearchController.text.trim();
    if (text.isEmpty) return;
    _homeSearchController.clear();
    ref.read(webBrowserProvider.notifier).navigate(text);
  }

  Future<void> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: 'Impossibile aprire il browser di sistema: $e',
        );
      }
    }
  }

  void _sendToComposer(WebBrowserTab activeTab) {
    final title = activeTab.title.trim().isNotEmpty
        ? activeTab.title.trim()
        : activeTab.url;
    final snippet = '[$title](${activeTab.url})';

    final draftNotifier = ref.read(
      composerDraftProvider(widget.sessionId).notifier,
    );
    final current = draftNotifier.state.trim();
    if (current.isEmpty) {
      draftNotifier.state = snippet;
    } else {
      draftNotifier.state = '$current\n$snippet';
    }

    FrameSnackBar.show(
      context,
      message: 'Link della pagina aggiunto al prompt del composer.',
      duration: const Duration(seconds: 2),
    );
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    FrameSnackBar.show(
      context,
      message: 'URL copiato negli appunti.',
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final browserState = ref.watch(webBrowserProvider);
    final activeTab = browserState.activeTab;
    _syncUrl(activeTab);

    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(tokens),
          _buildTabBar(tokens, browserState),
          _buildOmniboxBar(tokens, browserState, activeTab),
          _buildBookmarksBar(tokens, browserState),
          if (activeTab.isLoading)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: tokens.surfaceElevated,
              color: tokens.accent,
            ),
          Expanded(
            child: _buildBody(tokens, activeTab),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(FrameTokens tokens) {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Row(
        children: [
          // Segmented Switcher: [ Git Changes ] [ Web Browser ]
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentButton(
                  key: const ValueKey('right-pane-switch-git-chip'),
                  label: 'Git Changes',
                  icon: Icons.source_outlined,
                  isSelected: false,
                  tokens: tokens,
                  onTap: () {
                    ref.read(rightPaneModeProvider.notifier).state =
                        RightPaneMode.git;
                  },
                ),
                _buildSegmentButton(
                  key: const ValueKey('right-pane-switch-browser-chip'),
                  label: 'Web Browser',
                  icon: Icons.language,
                  isSelected: true,
                  tokens: tokens,
                  onTap: () {},
                ),
              ],
            ),
          ),
          const Spacer(),
          // Action Buttons
          IconButton(
            key: const ValueKey('browser-send-to-chat-btn'),
            tooltip: 'Invia al Chat Composer',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => _sendToComposer(
              ref.read(webBrowserProvider).activeTab,
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 15),
          ),
          IconButton(
            key: const ValueKey('browser-copy-url-btn'),
            tooltip: 'Copia URL',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => _copyUrl(
              ref.read(webBrowserProvider).activeTab.url,
            ),
            icon: const Icon(Icons.copy_outlined, size: 15),
          ),
          IconButton(
            key: const ValueKey('browser-open-external-btn'),
            tooltip: 'Apri nel browser di sistema',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () {
              final url = ref.read(webBrowserProvider).activeTab.url;
              if (url != 'about:home') _openExternal(url);
            },
            icon: const Icon(Icons.open_in_new, size: 15),
          ),
          if (widget.onCollapse != null) ...[
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('browser-collapse-btn'),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: 'Collassa pannello Web Browser',
              onPressed: widget.onCollapse,
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool isSelected,
    required FrameTokens tokens,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? tokens.surfaceElevated
              : tokens.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: isSelected
              ? Border.all(color: tokens.borderStrong, width: 0.8)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? tokens.accent : tokens.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? tokens.displayText : tokens.textMuted,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(FrameTokens tokens, WebBrowserState browserState) {
    final notifier = ref.read(webBrowserProvider.notifier);
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: browserState.tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final tab = browserState.tabs[index];
                final isActive = tab.id == browserState.activeTabId;
                return InkWell(
                  key: ValueKey('browser-tab-${tab.id}'),
                  onTap: () => notifier.switchTab(tab.id),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 160, minWidth: 80),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isActive ? tokens.surfaceElevated : tokens.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(tokens.radiusSm),
                      ),
                      border: Border.all(
                        color: isActive ? tokens.accent : tokens.border,
                        width: isActive ? 1.0 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.isLoading)
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: tokens.accent,
                            ),
                          )
                        else
                          Icon(
                            tab.isHome ? Icons.home_outlined : Icons.language,
                            size: 12,
                            color: isActive ? tokens.accent : tokens.textMuted,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tab.title.isEmpty ? 'Nuova scheda' : tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                              color: isActive
                                  ? tokens.textPrimary
                                  : tokens.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          key: ValueKey('browser-close-tab-${tab.id}'),
                          onTap: () => notifier.closeTab(tab.id),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 11,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            key: const ValueKey('browser-new-tab-btn'),
            tooltip: 'Nuova scheda',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => notifier.newTab(),
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildOmniboxBar(
    FrameTokens tokens,
    WebBrowserState browserState,
    WebBrowserTab activeTab,
  ) {
    final notifier = ref.read(webBrowserProvider.notifier);
    final isBookmarked = browserState.isBookmarked(activeTab.url);

    return Container(
      height: 38,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('browser-back-btn'),
            tooltip: 'Indietro',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: activeTab.canGoBack ? () => notifier.goBack() : null,
            icon: const Icon(Icons.arrow_back, size: 16),
          ),
          IconButton(
            key: const ValueKey('browser-forward-btn'),
            tooltip: 'Avanti',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed:
                activeTab.canGoForward ? () => notifier.goForward() : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
          ),
          IconButton(
            key: const ValueKey('browser-reload-btn'),
            tooltip: 'Ricarica',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => notifier.reload(),
            icon: const Icon(Icons.refresh, size: 16),
          ),
          IconButton(
            key: const ValueKey('browser-home-btn'),
            tooltip: 'Home',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: () => notifier.goHome(),
            icon: const Icon(Icons.home_outlined, size: 16),
          ),
          const SizedBox(width: 4),
          // Omnibox Input
          Expanded(
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(
                  color: _urlFocusNode.hasFocus
                      ? tokens.accent
                      : tokens.borderStrong,
                ),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      activeTab.url.startsWith('https://')
                          ? Icons.lock_outline
                          : Icons.search,
                      size: 13,
                      color: activeTab.url.startsWith('https://')
                          ? tokens.accent
                          : tokens.textMuted,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('browser-omnibox-input'),
                      controller: _urlController,
                      focusNode: _urlFocusNode,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.textPrimary,
                        fontFamily: tokens.monoFontFamily,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 7),
                        hintText:
                            'Cerca o inserisci URL (es. pub.dev o flutter riverpod)...',
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _submitUrl(),
                    ),
                  ),
                  if (_urlController.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Pulisci',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      onPressed: () {
                        _urlController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 12),
                    ),
                  IconButton(
                    key: const ValueKey('browser-bookmark-btn'),
                    tooltip: isBookmarked
                        ? 'Rimuovi dai preferiti'
                        : 'Aggiungi ai preferiti',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: activeTab.isHome
                        ? null
                        : () => notifier.toggleBookmark(
                              activeTab.url,
                              activeTab.title,
                            ),
                    icon: Icon(
                      isBookmarked ? Icons.star : Icons.star_border,
                      size: 14,
                      color: isBookmarked ? tokens.warning : tokens.textMuted,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('browser-go-btn'),
                    tooltip: 'Vai',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: _submitUrl,
                    icon: const Icon(Icons.arrow_forward_ios, size: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Search Engine Picker
          PopupMenuButton<SearchEngine>(
            key: const ValueKey('browser-engine-picker'),
            tooltip: 'Motore di ricerca: ${browserState.searchEngine.label}',
            initialValue: browserState.searchEngine,
            padding: EdgeInsets.zero,
            onSelected: (engine) => notifier.setSearchEngine(engine),
            itemBuilder: (context) => [
              for (final engine in SearchEngine.values)
                PopupMenuItem(
                  value: engine,
                  height: 32,
                  child: Row(
                    children: [
                      Icon(engine.icon, size: 14, color: tokens.accent),
                      const SizedBox(width: 8),
                      Text(
                        engine.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Row(
                children: [
                  Icon(
                    browserState.searchEngine.icon,
                    size: 13,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 14, color: tokens.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarksBar(FrameTokens tokens, WebBrowserState browserState) {
    final notifier = ref.read(webBrowserProvider.notifier);
    return Container(
      height: 26,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: browserState.bookmarks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final bm = browserState.bookmarks[index];
          return ActionChip(
            key: ValueKey('browser-bm-$index'),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            backgroundColor: tokens.surfaceElevated,
            side: BorderSide(color: tokens.border, width: 0.5),
            avatar: Icon(
              bm.icon ?? Icons.bookmark_border,
              size: 11,
              color: tokens.accent,
            ),
            label: Text(
              bm.title,
              style: TextStyle(
                fontSize: 10.5,
                color: tokens.textPrimary,
              ),
            ),
            onPressed: () => notifier.navigate(bm.url),
          );
        },
      ),
    );
  }

  Widget _buildBody(FrameTokens tokens, WebBrowserTab activeTab) {
    if (activeTab.isHome) {
      return _buildHomeDashboard(tokens);
    }

    if (activeTab.isLoading && activeTab.content == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              'Caricamento in corso...',
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              activeTab.url,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontFamily: tokens.monoFontFamily,
              ),
            ),
          ],
        ),
      );
    }

    if (activeTab.errorMessage != null) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 36, color: tokens.warning),
              const SizedBox(height: 12),
              const Text(
                'Impossibile caricare la pagina',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                activeTab.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('browser-retry-btn'),
                    onPressed: () =>
                        ref.read(webBrowserProvider.notifier).reload(),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Riprova'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openExternal(activeTab.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Apri esternamente'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final content = activeTab.content;
    if (content == null || content.isEmpty) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.article_outlined, size: 36, color: tokens.textMuted),
              const SizedBox(height: 12),
              const Text(
                'Nessun testo principale rilevato',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Questa pagina potrebbe richiedere JavaScript attivo o un browser completo per visualizzare il contenuto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _openExternal(activeTab.url),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Apri nel browser di sistema'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page Meta Header Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                            ),
                            child: Text(
                              content.domain,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              content.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (content.description != null &&
                          content.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          content.description!,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Apri nel browser di sistema',
                  onPressed: () => _openExternal(content.url),
                  icon: const Icon(Icons.open_in_new, size: 16),
                ),
                IconButton(
                  tooltip: 'Invia al Chat Composer',
                  onPressed: () => _sendToComposer(activeTab),
                  icon: const Icon(Icons.send_outlined, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search Results View (if search)
          if (content.isSearch) ...[
            Text(
              'Risultati (${content.searchResults.length}):',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < content.searchResults.length; i++)
              _buildSearchResultCard(
                tokens,
                content.searchResults[i],
                index: i,
              ),
          ] else ...[
            // Regular Web Reader View
            if (content.headings.isNotEmpty) ...[
              for (final heading in content.headings)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    heading,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
            ],
            if (content.paragraphs.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final p in content.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    p,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
            ] else if (content.rawText.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                content.rawText,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: tokens.textPrimary,
                ),
              ),
            ],
            if (content.codeSnippets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Codice estratti (${content.codeSnippets.length}):',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              for (final code in content.codeSnippets)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.borderStrong),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          code,
                          style: TextStyle(
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 11,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        tooltip: 'Copia codice',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          FrameSnackBar.show(
                            context,
                            message: 'Codice copiato.',
                            duration: const Duration(seconds: 1),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 12),
                      ),
                    ],
                  ),
                ),
            ],
            if (content.links.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Collegamenti nella pagina (${content.links.length}):',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final link in content.links)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      backgroundColor: tokens.surfaceElevated,
                      side: BorderSide(color: tokens.border, width: 0.5),
                      avatar: Icon(Icons.link, size: 11, color: tokens.accent),
                      label: Text(
                        link.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.accent,
                        ),
                      ),
                      onPressed: () =>
                          ref.read(webBrowserProvider.notifier).navigate(link.url),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResultCard(
    FrameTokens tokens,
    WebSearchResult result, {
    required int index,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  result.domain,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            key: ValueKey('browser-search-result-$index'),
            onTap: () =>
                ref.read(webBrowserProvider.notifier).navigate(result.url),
            child: Text(
              result.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: tokens.accent,
              ),
            ),
          ),
          if (result.snippet.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              result.snippet,
              style: TextStyle(fontSize: 11.5, color: tokens.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeDashboard(FrameTokens tokens) {
    final browserState = ref.watch(webBrowserProvider);
    final notifier = ref.read(webBrowserProvider.notifier);

    return SingleChildScrollView(
      key: const ValueKey('browser-home-dashboard'),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.travel_explore, size: 48, color: tokens.accent),
              const SizedBox(height: 12),
              const Text(
                'PiFrame Web Browser',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Naviga e cerca documentazione, librerie o soluzioni per il tuo progetto',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 24),

              // Search input
              TextField(
                key: const ValueKey('browser-home-search-input'),
                controller: _homeSearchController,
                decoration: InputDecoration(
                  hintText: 'Cerca con ${browserState.searchEngine.label}...',
                  prefixIcon: Icon(
                    browserState.searchEngine.icon,
                    size: 16,
                    color: tokens.accent,
                  ),
                  suffixIcon: IconButton(
                    key: const ValueKey('browser-home-search-btn'),
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _submitHomeSearch,
                  ),
                  filled: true,
                  fillColor: tokens.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusMd),
                    borderSide: BorderSide(color: tokens.borderStrong),
                  ),
                ),
                onSubmitted: (_) => _submitHomeSearch(),
              ),

              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Segnalibri veloci',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bm in browserState.bookmarks)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tokens.surfaceElevated,
                        foregroundColor: tokens.textPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          side: BorderSide(color: tokens.border),
                        ),
                      ),
                      onPressed: () => notifier.navigate(bm.url),
                      icon: Icon(
                        bm.icon ?? Icons.bookmark_border,
                        size: 14,
                        color: tokens.accent,
                      ),
                      label: Text(bm.title, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),

              if (browserState.recentSearches.isNotEmpty) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ricerche recenti',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final query in browserState.recentSearches)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: tokens.surfaceElevated,
                        side: BorderSide(color: tokens.border, width: 0.5),
                        avatar: Icon(Icons.history, size: 12, color: tokens.textMuted),
                        label: Text(query, style: const TextStyle(fontSize: 11)),
                        onPressed: () => notifier.navigate(query),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
