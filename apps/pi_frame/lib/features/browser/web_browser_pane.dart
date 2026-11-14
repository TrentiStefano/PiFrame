import '../../domain/errors/user_facing_error.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_win_floating/webview.dart';

import '../../data/language/language_settings.dart';
import '../../data/language/strings_workspace.dart';
import '../../ui/frame_activity_indicator.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../composer/composer_draft.dart';
import '../workspace/repository_workspace.dart';
import 'browser_controller.dart';
import 'browser_models.dart';
import '../../ui/precision.dart';

/// Companion width below which header and toolbar actions move into
/// overflow menus so the single toolbar row always fits (audit P1-4).
const double kCompactCompanionWidth = 360;

/// Actions that move into the overflow menus on narrow companions.
enum _BrowserMenuAction {
  devTools,
  sendToChat,
  copyUrl,
  openExternal,
  home,
  bookmark,
}

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
  AppStrings _getStrings() {
    try {
      return ref.watch(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  AppStrings _getReadStrings() {
    try {
      return ref.read(appStringsProvider);
    } catch (_) {
      return const AppStrings(AppLanguage.it);
    }
  }

  late final TextEditingController _urlController;
  late final TextEditingController _homeSearchController;
  final FocusNode _urlFocusNode = FocusNode();
  String? _lastSyncedUrl;
  WinWebViewController? _winController;

  bool get _isNativeWebViewSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  void initState() {
    super.initState();
    final activeTab = ref.read(webBrowserProvider).activeTab;
    _urlController = TextEditingController(
      text: activeTab.isHome ? '' : activeTab.url,
    );
    _homeSearchController = TextEditingController();
    _lastSyncedUrl = activeTab.url;

    if (_isNativeWebViewSupported) {
      _initWinWebView();
    }
  }

  void _initWinWebView() {
    final controller = WinWebViewController();
    _winController = controller;
    controller.setNavigationDelegate(
      WinNavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          ref
              .read(webBrowserProvider.notifier)
              .updateCurrentTab(url: url, isLoading: true);
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          final title = await controller.getTitle();
          ref
              .read(webBrowserProvider.notifier)
              .updateCurrentTab(url: url, title: title, isLoading: false);
        },
        onUrlChange: (change) {
          if (!mounted) return;
          final url = change.url;
          if (url != null && url.isNotEmpty) {
            ref.read(webBrowserProvider.notifier).updateCurrentTab(url: url);
          }
        },
        onPageTitleChanged: (title) {
          if (!mounted) return;
          final activeTab = ref.read(webBrowserProvider).activeTab;
          ref
              .read(webBrowserProvider.notifier)
              .updateCurrentTab(url: activeTab.url, title: title);
        },
        onWebResourceError: (error) {
          if (!mounted) return;
          ref
              .read(webBrowserProvider.notifier)
              .updateCurrentTab(
                url: ref.read(webBrowserProvider).activeTab.url,
                isLoading: false,
                errorMessage: error.description,
              );
        },
      ),
    );
    final activeTab = ref.read(webBrowserProvider).activeTab;
    if (!activeTab.isHome && activeTab.url.isNotEmpty) {
      final uri = Uri.tryParse(activeTab.url);
      if (uri != null) {
        controller.loadRequest(uri);
      }
    } else {
      controller.setVisibility(false);
    }
  }

  @override
  void activate() {
    super.activate();
    final activeTab = ref.read(webBrowserProvider).activeTab;
    if (!activeTab.isHome && _isNativeWebViewSupported) {
      _winController?.setVisibility(true);
    }
  }

  @override
  void deactivate() {
    _winController?.setVisibility(false);
    super.deactivate();
  }

  @override
  void dispose() {
    _winController?.dispose();
    _winController = null;
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

  Future<void> _navigateTo(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    _urlFocusNode.unfocus();

    final normalized = await ref
        .read(webBrowserProvider.notifier)
        .navigate(text);
    if (_isNativeWebViewSupported && _winController != null) {
      if (normalized == 'about:home') {
        await _winController!.setVisibility(false);
      } else {
        await _winController!.setVisibility(true);
        final uri = Uri.tryParse(normalized);
        if (uri != null) {
          await _winController!.loadRequest(uri);
        }
      }
    }
  }

  void _submitUrl() {
    final text = _urlController.text.trim();
    if (text.isEmpty) return;
    _navigateTo(text);
  }

  void _submitHomeSearch() {
    final text = _homeSearchController.text.trim();
    if (text.isEmpty) return;
    _homeSearchController.clear();
    _navigateTo(text);
  }

  Future<void> _switchTab(String tabId) async {
    ref.read(webBrowserProvider.notifier).switchTab(tabId);
    final targetTab = ref
        .read(webBrowserProvider)
        .tabs
        .firstWhere((t) => t.id == tabId);
    if (_isNativeWebViewSupported && _winController != null) {
      if (targetTab.isHome) {
        await _winController!.setVisibility(false);
      } else {
        await _winController!.setVisibility(true);
        final currentUrl = await _winController!.currentUrl();
        if (currentUrl != targetTab.url) {
          final uri = Uri.tryParse(targetTab.url);
          if (uri != null) {
            await _winController!.loadRequest(uri);
          }
        }
      }
    }
  }

  Future<void> _newTab() async {
    ref.read(webBrowserProvider.notifier).newTab();
    if (_isNativeWebViewSupported && _winController != null) {
      await _winController!.setVisibility(false);
    }
  }

  Future<void> _closeTab(String tabId) async {
    ref.read(webBrowserProvider.notifier).closeTab(tabId);
    final activeTab = ref.read(webBrowserProvider).activeTab;
    if (_isNativeWebViewSupported && _winController != null) {
      if (activeTab.isHome) {
        await _winController!.setVisibility(false);
      } else {
        await _winController!.setVisibility(true);
        final currentUrl = await _winController!.currentUrl();
        if (currentUrl != activeTab.url) {
          final uri = Uri.tryParse(activeTab.url);
          if (uri != null) {
            await _winController!.loadRequest(uri);
          }
        }
      }
    }
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
        final strings = _getReadStrings();
        FrameSnackBar.show(
          context,
          message: strings.cannotOpenSystemBrowser(e),
          isError: true,
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

    final strings = _getReadStrings();
    FrameSnackBar.show(
      context,
      message: strings.pageLinkAddedToComposer,
      duration: const Duration(seconds: 2),
    );
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    final strings = _getReadStrings();
    FrameSnackBar.show(
      context,
      message: strings.urlCopiedToClipboard,
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
          _buildHeader(tokens, browserState),
          _buildOmniboxBar(tokens, browserState, activeTab),
          if (activeTab.isLoading) _loadingBar(tokens),
          Expanded(child: _buildBody(tokens, activeTab)),
        ],
      ),
    );
  }

  /// The companion title bar: the Git/Browser switch and actions on the first row,
  /// the browser tab strip below it (plan task 10.2). Tabs no longer take a row of
  /// their own, so the page starts one bar higher.
  Widget _buildHeader(FrameTokens tokens, WebBrowserState browserState) {
    final strings = _getStrings();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kCompactCompanionWidth;
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.borderStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      // Segmented Switcher: [ Git Changes ] [ Web Browser ]
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: _buildSegmentButton(
                                  key: const ValueKey(
                                    'right-pane-switch-git-chip',
                                  ),
                                  label: _getStrings().browserGitChangesLabel,
                                  icon: Icons.source_outlined,
                                  isSelected: false,
                                  tokens: tokens,
                                  onTap: () {
                                    _winController?.setVisibility(false);
                                    ref
                                        .read(rightPaneModeProvider.notifier)
                                        .state = RightPaneMode
                                        .git;
                                  },
                                ),
                              ),
                              Flexible(
                                child: _buildSegmentButton(
                                  key: const ValueKey(
                                    'right-pane-switch-browser-chip',
                                  ),
                                  label: _getStrings().browserWebBrowserLabel,
                                  icon: Icons.language_outlined,
                                  isSelected: true,
                                  tokens: tokens,
                                  onTap: () {},
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Action buttons: inline when wide, in one overflow menu when narrow.
                      if (compact)
                        PopupMenuButton<_BrowserMenuAction>(
                          key: const ValueKey('browser-companion-overflow-btn'),
                          tooltip: strings.browserMoreActionsTooltip,
                          padding: EdgeInsets.zero,
                          onSelected: _onBrowserMenuAction,
                          itemBuilder: (context) => [
                            if (_isNativeWebViewSupported)
                              _browserMenuItem(
                                key: const ValueKey('browser-menu-devtools'),
                                value: _BrowserMenuAction.devTools,
                                icon: Icons.developer_mode_outlined,
                                label: strings.openChromiumDevToolsTooltip,
                                tokens: tokens,
                              ),
                            _browserMenuItem(
                              key: const ValueKey('browser-menu-send-to-chat'),
                              value: _BrowserMenuAction.sendToChat,
                              icon: Icons.chat_bubble_outlined,
                              label: strings.sendToChatComposerTooltip,
                              tokens: tokens,
                            ),
                            _browserMenuItem(
                              key: const ValueKey('browser-menu-copy-url'),
                              value: _BrowserMenuAction.copyUrl,
                              icon: Icons.copy_outlined,
                              label: strings.copyUrlTooltip,
                              tokens: tokens,
                            ),
                            _browserMenuItem(
                              key: const ValueKey('browser-menu-open-external'),
                              value: _BrowserMenuAction.openExternal,
                              icon: Icons.open_in_new_outlined,
                              label: strings.openInSystemBrowserTooltip,
                              tokens: tokens,
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.more_horiz_outlined,
                              size: FrameSize.icon,
                              color: tokens.textMuted,
                            ),
                          ),
                        )
                      else ...[
                        if (_isNativeWebViewSupported)
                          IconButton(
                            key: const ValueKey('browser-devtools-btn'),
                            tooltip: strings.openChromiumDevToolsTooltip,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                            onPressed: _openDevTools,
                            icon: const Icon(
                              Icons.developer_mode_outlined,
                              size: FrameSize.icon,
                            ),
                          ),
                        IconButton(
                          key: const ValueKey('browser-send-to-chat-btn'),
                          tooltip: strings.sendToChatComposerTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: _sendActiveTabToComposer,
                          icon: const Icon(
                            Icons.chat_bubble_outlined,
                            size: FrameSize.icon,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('browser-copy-url-btn'),
                          tooltip: strings.copyUrlTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: _copyActiveUrl,
                          icon: const Icon(
                            Icons.copy_outlined,
                            size: FrameSize.icon,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('browser-open-external-btn'),
                          tooltip: strings.openInSystemBrowserTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: _openActiveExternal,
                          icon: const Icon(
                            Icons.open_in_new_outlined,
                            size: FrameSize.icon,
                          ),
                        ),
                      ],
                      if (widget.onCollapse != null) ...[
                        const SizedBox(width: FrameSpace.x1),
                        IconButton(
                          key: const ValueKey('browser-collapse-btn'),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: strings.collapseBrowserPanelTooltip,
                          onPressed: () {
                            _winController?.setVisibility(false);
                            widget.onCollapse?.call();
                          },
                          icon: const Icon(
                            Icons.chevron_right_outlined,
                            size: FrameSize.icon,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildTabBar(tokens, browserState),
            ],
          ),
        );
      },
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
        duration: FrameMotion.small,
        padding: const EdgeInsets.symmetric(
          horizontal: FrameSpace.x2,
          vertical: 3,
        ),
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FrameText.of(context).caption.copyWith(
                  color: isSelected ? tokens.displayText : tokens.textMuted,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(FrameTokens tokens, WebBrowserState browserState) {
    final strings = _getStrings();
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 6),
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
                  onTap: () => _switchTab(tab.id),
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 160,
                      minWidth: 80,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FrameSpace.x2,
                    ),
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
                          FrameActivityIndicator(
                            size: 10,
                            strokeWidth: 1.5,
                            color: tokens.accent,
                          )
                        else
                          Icon(
                            tab.isHome
                                ? Icons.home_outlined
                                : Icons.language_outlined,
                            size: 12,
                            color: isActive ? tokens.accent : tokens.textMuted,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tab.title.isEmpty
                                ? strings.newBrowserTab
                                : tab.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FrameText.of(context).caption.copyWith(
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? tokens.textPrimary
                                  : tokens.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: FrameSpace.x1),
                        InkWell(
                          key: ValueKey('browser-close-tab-${tab.id}'),
                          onTap: () => _closeTab(tab.id),
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_outlined,
                              size: FrameSize.icon,
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
            tooltip: strings.newBrowserTab,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: _newTab,
            icon: const Icon(Icons.add_outlined, size: FrameSize.icon),
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
    final strings = _getStrings();
    final notifier = ref.read(webBrowserProvider.notifier);
    final isBookmarked = browserState.isBookmarked(activeTab.url);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kCompactCompanionWidth;
        return Container(
          height: 38,
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('browser-back-btn'),
                tooltip: strings.browserBackTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: activeTab.canGoBack
                    ? () async {
                        if (_isNativeWebViewSupported &&
                            _winController != null &&
                            await _winController!.canGoBack()) {
                          await _winController!.goBack();
                        }
                        ref.read(webBrowserProvider.notifier).goBack();
                      }
                    : null,
                icon: const Icon(
                  Icons.arrow_back_outlined,
                  size: FrameSize.icon,
                ),
              ),
              IconButton(
                key: const ValueKey('browser-forward-btn'),
                tooltip: strings.browserForwardTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: activeTab.canGoForward
                    ? () async {
                        if (_isNativeWebViewSupported &&
                            _winController != null &&
                            await _winController!.canGoForward()) {
                          await _winController!.goForward();
                        }
                        ref.read(webBrowserProvider.notifier).goForward();
                      }
                    : null,
                icon: const Icon(
                  Icons.arrow_forward_outlined,
                  size: FrameSize.icon,
                ),
              ),
              IconButton(
                key: const ValueKey('browser-reload-btn'),
                tooltip: strings.browserReloadTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () async {
                  if (_isNativeWebViewSupported &&
                      _winController != null &&
                      !activeTab.isHome) {
                    await _winController!.reload();
                  }
                  ref.read(webBrowserProvider.notifier).reload();
                },
                icon: const Icon(Icons.refresh_outlined, size: FrameSize.icon),
              ),
              if (!compact)
                IconButton(
                  key: const ValueKey('browser-home-btn'),
                  tooltip: strings.browserHomeTooltip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: _goHome,
                  icon: const Icon(Icons.home_outlined, size: FrameSize.icon),
                ),
              const SizedBox(width: FrameSpace.x1),
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
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 4 : 6,
                        ),
                        child: Icon(
                          activeTab.url.startsWith('https://')
                              ? Icons.lock_outlined
                              : Icons.search_outlined,
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
                          style: FrameText.of(context).caption.copyWith(
                            color: tokens.textPrimary,
                            fontFamily: tokens.monoFontFamily,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 7,
                            ),
                            hintText: strings.browserOmniboxHint,
                            hintStyle: FrameText.of(context).caption
                                .copyWith(color: tokens.textMuted),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _submitUrl(),
                        ),
                      ),
                      if (_urlController.text.isNotEmpty)
                        IconButton(
                          tooltip: strings.browserClearTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          onPressed: () {
                            _urlController.clear();
                            setState(() {});
                          },
                          icon: const Icon(
                            Icons.close_outlined,
                            size: FrameSize.icon,
                          ),
                        ),
                      if (!compact)
                        IconButton(
                          key: const ValueKey('browser-bookmark-btn'),
                          tooltip: isBookmarked
                              ? strings.removeBookmarkTooltip
                              : strings.addBookmarkTooltip,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                          onPressed: activeTab.isHome
                              ? null
                              : () => notifier.toggleBookmark(
                                  activeTab.url,
                                  activeTab.title,
                                ),
                          icon: Icon(
                            isBookmarked ? Icons.star_outlined : Icons.star_border,
                            size: 14,
                            color: isBookmarked
                                ? tokens.warning
                                : tokens.textMuted,
                          ),
                        ),
                      IconButton(
                        key: const ValueKey('browser-go-btn'),
                        tooltip: strings.browserGoTooltip,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: _submitUrl,
                        icon: const Icon(
                          Icons.arrow_forward_ios_outlined,
                          size: FrameSize.icon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: FrameSpace.x1),
              // Search Engine Picker
              PopupMenuButton<SearchEngine>(
                key: const ValueKey('browser-engine-picker'),
                tooltip: strings.browserSearchEngineTooltip(
                  browserState.searchEngine.label,
                ),
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
                          Icon(
                            engine.icon,
                            size: FrameSize.icon,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: FrameSpace.x2),
                          Text(
                            engine.label,
                            style: FrameText.of(context).label,
                          ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FrameSpace.x1,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.borderStrong),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        browserState.searchEngine.icon,
                        size: 13,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: FrameSpace.x1),
                      Icon(
                        Icons.arrow_drop_down_outlined,
                        size: FrameSize.icon,
                        color: tokens.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              // Narrow companions move home and bookmark into this menu.
              if (compact) ...[
                const SizedBox(width: FrameSpace.x1),
                PopupMenuButton<_BrowserMenuAction>(
                  key: const ValueKey('browser-toolbar-overflow-btn'),
                  tooltip: strings.browserMoreActionsTooltip,
                  padding: EdgeInsets.zero,
                  onSelected: _onBrowserMenuAction,
                  itemBuilder: (context) => [
                    _browserMenuItem(
                      key: const ValueKey('browser-menu-home'),
                      value: _BrowserMenuAction.home,
                      icon: Icons.home_outlined,
                      label: strings.browserHomeTooltip,
                      tokens: tokens,
                    ),
                    _browserMenuItem(
                      key: const ValueKey('browser-menu-bookmark'),
                      value: _BrowserMenuAction.bookmark,
                      icon: isBookmarked ? Icons.star_outlined : Icons.star_border,
                      label: isBookmarked
                          ? strings.removeBookmarkTooltip
                          : strings.addBookmarkTooltip,
                      tokens: tokens,
                      enabled: !activeTab.isHome,
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.more_horiz_outlined,
                      size: FrameSize.icon,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- Shared actions (used by inline buttons and overflow menus) ---

  void _openDevTools() => _winController?.openDevTools();

  void _sendActiveTabToComposer() =>
      _sendToComposer(ref.read(webBrowserProvider).activeTab);

  void _copyActiveUrl() => _copyUrl(ref.read(webBrowserProvider).activeTab.url);

  void _openActiveExternal() {
    final url = ref.read(webBrowserProvider).activeTab.url;
    if (url != 'about:home') _openExternal(url);
  }

  Future<void> _goHome() async {
    if (_isNativeWebViewSupported && _winController != null) {
      await _winController!.setVisibility(false);
    }
    ref.read(webBrowserProvider.notifier).goHome();
  }

  void _toggleActiveBookmark() {
    final tab = ref.read(webBrowserProvider).activeTab;
    if (tab.isHome) return;
    ref.read(webBrowserProvider.notifier).toggleBookmark(tab.url, tab.title);
  }

  void _onBrowserMenuAction(_BrowserMenuAction action) {
    switch (action) {
      case _BrowserMenuAction.devTools:
        _openDevTools();
      case _BrowserMenuAction.sendToChat:
        _sendActiveTabToComposer();
      case _BrowserMenuAction.copyUrl:
        _copyActiveUrl();
      case _BrowserMenuAction.openExternal:
        _openActiveExternal();
      case _BrowserMenuAction.home:
        _goHome();
      case _BrowserMenuAction.bookmark:
        _toggleActiveBookmark();
    }
  }

  PopupMenuItem<_BrowserMenuAction> _browserMenuItem({
    required Key key,
    required _BrowserMenuAction value,
    required IconData icon,
    required String label,
    required FrameTokens tokens,
    bool enabled = true,
  }) {
    return PopupMenuItem<_BrowserMenuAction>(
      key: key,
      value: value,
      enabled: enabled,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: FrameSize.icon, color: tokens.accent),
          const SizedBox(width: FrameSpace.x2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FrameText.of(context).label,
            ),
          ),
        ],
      ),
    );
  }

  /// Thin page-load bar. Under reduced motion it is a static accent strip, so
  /// nothing loops on screen.
  Widget _loadingBar(FrameTokens tokens) {
    if (FrameMotion.reduced(context)) {
      return SizedBox(height: 2, child: ColoredBox(color: tokens.accent));
    }
    return LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: tokens.surfaceElevated,
      color: tokens.accent,
    );
  }

  Widget _buildBody(FrameTokens tokens, WebBrowserTab activeTab) {
    if (activeTab.isHome) {
      if (_isNativeWebViewSupported && _winController != null) {
        _winController!.setVisibility(false);
      }
      return _buildHomeDashboard(tokens);
    }

    if (_isNativeWebViewSupported && _winController != null) {
      _winController!.setVisibility(true);
      return Stack(
        children: [
          Positioned.fill(child: WinWebViewWidget(controller: _winController!)),
          if (activeTab.isLoading)
            Positioned(top: 0, left: 0, right: 0, child: _loadingBar(tokens)),
        ],
      );
    }

    return _buildFallbackReaderView(tokens, activeTab);
  }

  Widget _buildFallbackReaderView(FrameTokens tokens, WebBrowserTab activeTab) {
    final strings = _getStrings();

    if (activeTab.isLoading && activeTab.content == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FrameActivityIndicator(
              size: FrameSize.iconLg,
              color: tokens.accent,
              strokeWidth: 2,
            ),
            const SizedBox(height: FrameSpace.x3),
            Text(
              strings.browserLoadingInProgress,
              style: FrameText.of(context).label
                  .copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: FrameSpace.x1),
            Text(
              activeTab.url,
              style: FrameText.of(context).caption.copyWith(
                color: tokens.textMuted,
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
              Icon(Icons.wifi_off_outlined, size: 36, color: tokens.warning),
              const SizedBox(height: FrameSpace.x3),
              Text(
                strings.unableToLoadPageTitle,
                style: FrameText.of(context).bodyLarge
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: FrameSpace.x2),
              Text(
                describeError(activeTab.errorMessage!, strings).summary,
                textAlign: TextAlign.center,
                style: FrameText.of(context).caption
                    .copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: FrameSpace.x4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  PressFeedback(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('browser-retry-btn'),
                      onPressed: () =>
                          ref.read(webBrowserProvider.notifier).reload(),
                      icon: const Icon(
                        Icons.refresh_outlined,
                        size: FrameSize.icon,
                      ),
                      label: Text(strings.retryBtn),
                    ),
                  ),
                  PressFeedback(
                    child: OutlinedButton.icon(
                      onPressed: () => _openExternal(activeTab.url),
                      icon: const Icon(
                        Icons.open_in_new_outlined,
                        size: FrameSize.icon,
                      ),
                      label: Text(strings.openExternallyBtn),
                    ),
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
              const SizedBox(height: FrameSpace.x3),
              Text(
                strings.noMainTextDetectedTitle,
                style: FrameText.of(context).bodyLarge
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: FrameSpace.x2),
              Text(
                strings.noMainTextDetectedMessage,
                textAlign: TextAlign.center,
                style: FrameText.of(context).caption
                    .copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: FrameSpace.x4),
              PressFeedback(
                child: OutlinedButton.icon(
                  onPressed: () => _openExternal(activeTab.url),
                  icon: const Icon(
                    Icons.open_in_new_outlined,
                    size: FrameSize.icon,
                  ),
                  label: Text(strings.openInSystemBrowserBtn),
                ),
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
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                            ),
                            child: Text(
                              content.domain,
                              style: FrameText.of(context).caption.copyWith(
                                color: tokens.accent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: FrameSpace.x2),
                          Expanded(
                            child: Text(
                              content.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FrameText.of(context).caption.copyWith(
                                color: tokens.textMuted,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content.title,
                        style: FrameText.of(context).title
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (content.description != null &&
                          content.description!.isNotEmpty) ...[
                        const SizedBox(height: FrameSpace.x1),
                        Text(
                          content.description!,
                          style: FrameText.of(context).caption
                              .copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.openInSystemBrowserTooltip,
                  onPressed: () => _openExternal(content.url),
                  icon: const Icon(
                    Icons.open_in_new_outlined,
                    size: FrameSize.icon,
                  ),
                ),
                IconButton(
                  tooltip: strings.sendToChatComposerTooltip,
                  onPressed: () => _sendToComposer(activeTab),
                  icon: const Icon(Icons.send_outlined, size: FrameSize.icon),
                ),
              ],
            ),
          ),
          const SizedBox(height: FrameSpace.x4),

          // Search Results View (if search)
          if (content.isSearch) ...[
            Text(
              strings.browserSearchResultsCount(content.searchResults.length),
              style: FrameText.of(context).label.copyWith(
                color: tokens.textMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: FrameSpace.x2),
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
                  padding: const EdgeInsets.only(
                    top: FrameSpace.x3,
                    bottom: FrameSpace.x1,
                  ),
                  child: Text(
                    heading,
                    style: FrameText.of(context).bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
            ],
            if (content.paragraphs.isNotEmpty) ...[
              const SizedBox(height: FrameSpace.x2),
              for (final p in content.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: FrameSpace.x2),
                  child: Text(
                    p,
                    style: FrameText.of(context).label
                        .copyWith(height: 1.5, color: tokens.textPrimary),
                  ),
                ),
            ] else if (content.rawText.isNotEmpty) ...[
              const SizedBox(height: FrameSpace.x2),
              SelectableText(
                content.rawText,
                style: FrameText.of(context).label
                    .copyWith(height: 1.5, color: tokens.textPrimary),
              ),
            ],
            if (content.codeSnippets.isNotEmpty) ...[
              const SizedBox(height: FrameSpace.x3),
              Text(
                strings.browserExtractedCodeCount(content.codeSnippets.length),
                style: FrameText.of(context).label.copyWith(
                  color: tokens.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              for (final code in content.codeSnippets)
                Container(
                  margin: const EdgeInsets.only(bottom: FrameSpace.x2),
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
                          style: FrameText.of(context).caption.copyWith(
                            fontFamily: tokens.monoFontFamily,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        tooltip: strings.copyCodeTooltip,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          FrameSnackBar.show(
                            context,
                            message: strings.codeCopiedMessage,
                            duration: const Duration(seconds: 1),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_outlined,
                          size: FrameSize.icon,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (content.links.isNotEmpty) ...[
              const SizedBox(height: FrameSpace.x4),
              Text(
                strings.browserPageLinksCount(content.links.length),
                style: FrameText.of(context).label.copyWith(
                  color: tokens.textMuted,
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
                      avatar: Icon(
                        Icons.link_outlined,
                        size: FrameSize.icon,
                        color: tokens.accent,
                      ),
                      label: Text(
                        link.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FrameText.of(context).caption
                            .copyWith(color: tokens.accent),
                      ),
                      onPressed: () => _navigateTo(link.url),
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
      margin: const EdgeInsets.only(bottom: FrameSpace.x2),
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
                  style: FrameText.of(context).caption.copyWith(
                    color: tokens.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: FrameSpace.x2),
              Expanded(
                child: Text(
                  result.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FrameText.of(context).caption.copyWith(
                    color: tokens.textMuted,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FrameSpace.x1),
          InkWell(
            key: ValueKey('browser-search-result-$index'),
            onTap: () => _navigateTo(result.url),
            child: Text(
              result.title,
              style: FrameText.of(context).body
                  .copyWith(fontWeight: FontWeight.bold, color: tokens.accent),
            ),
          ),
          if (result.snippet.isNotEmpty) ...[
            const SizedBox(height: FrameSpace.x1),
            Text(
              result.snippet,
              style: FrameText.of(context).caption
                  .copyWith(color: tokens.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHomeDashboard(FrameTokens tokens) {
    final strings = _getStrings();
    final browserState = ref.watch(webBrowserProvider);

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
              Icon(
                Icons.travel_explore_outlined,
                size: 48,
                color: tokens.accent,
              ),
              const SizedBox(height: FrameSpace.x3),
              Text(
                'PiFrame Web Browser',
                style: FrameText.of(context).heading
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                strings.browserHomeSubtitle,
                textAlign: TextAlign.center,
                style: FrameText.of(context).label
                    .copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: FrameSpace.x6),

              // Search input
              TextField(
                key: const ValueKey('browser-home-search-input'),
                controller: _homeSearchController,
                decoration: InputDecoration(
                  hintText: strings.browserHomeSearchHint(
                    browserState.searchEngine.label,
                  ),
                  prefixIcon: Icon(
                    browserState.searchEngine.icon,
                    size: FrameSize.icon,
                    color: tokens.accent,
                  ),
                  suffixIcon: IconButton(
                    key: const ValueKey('browser-home-search-btn'),
                    icon: const Icon(Icons.arrow_forward_outlined),
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

              const SizedBox(height: FrameSpace.x6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  strings.quickBookmarksHeader,
                  style: FrameText.of(context).label.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: FrameSpace.x2),
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
                      onPressed: () => _navigateTo(bm.url),
                      icon: Icon(
                        bm.icon ?? Icons.bookmark_border_outlined,
                        size: 14,
                        color: tokens.accent,
                      ),
                      label: Text(
                        bm.title,
                        style: FrameText.of(context).caption,
                      ),
                    ),
                ],
              ),

              if (browserState.recentSearches.isNotEmpty) ...[
                const SizedBox(height: FrameSpace.x6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    strings.recentSearchesHeader,
                    style: FrameText.of(context).label.copyWith(
                      fontWeight: FontWeight.bold,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: FrameSpace.x2),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final query in browserState.recentSearches)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: tokens.surfaceElevated,
                        side: BorderSide(color: tokens.border, width: 0.5),
                        avatar: Icon(
                          Icons.history_outlined,
                          size: FrameSize.icon,
                          color: tokens.textMuted,
                        ),
                        label: Text(
                          query,
                          style: FrameText.of(context).caption,
                        ),
                        onPressed: () => _navigateTo(query),
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
