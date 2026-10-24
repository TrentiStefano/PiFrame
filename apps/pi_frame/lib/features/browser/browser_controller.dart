import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'browser_models.dart';
import 'browser_service.dart';

final rightPaneModeProvider = StateProvider<RightPaneMode>((ref) => RightPaneMode.git);

final browserClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final browserServiceProvider = Provider<WebBrowserService>((ref) {
  return WebBrowserService(client: ref.watch(browserClientProvider));
});

final webBrowserProvider =
    StateNotifierProvider<WebBrowserNotifier, WebBrowserState>((ref) {
  return WebBrowserNotifier(ref);
});

class WebBrowserNotifier extends StateNotifier<WebBrowserState> {
  final Ref _ref;
  int _tabCounter = 1;

  static const List<WebBookmark> defaultBookmarks = [
    WebBookmark(
      title: 'pub.dev',
      url: 'https://pub.dev',
      icon: Icons.inventory_2_outlined,
    ),
    WebBookmark(
      title: 'Flutter Docs',
      url: 'https://docs.flutter.dev',
      icon: Icons.flutter_dash,
    ),
    WebBookmark(
      title: 'GitHub',
      url: 'https://github.com',
      icon: Icons.code,
    ),
    WebBookmark(
      title: 'Stack Overflow',
      url: 'https://stackoverflow.com',
      icon: Icons.help_outline,
    ),
    WebBookmark(
      title: 'MDN Web Docs',
      url: 'https://developer.mozilla.org',
      icon: Icons.menu_book,
    ),
  ];

  WebBrowserNotifier(this._ref)
      : super(
          const WebBrowserState(
            tabs: [
              WebBrowserTab(
                id: 'tab_1',
                url: 'about:home',
                title: 'Home',
                history: ['about:home'],
                historyIndex: 0,
              ),
            ],
            activeTabId: 'tab_1',
            bookmarks: defaultBookmarks,
          ),
        );

  WebBrowserService get _service => _ref.read(browserServiceProvider);

  Future<void> navigate(String input, {String? tabId}) async {
    final targetTabId = tabId ?? state.activeTabId;
    final tabIndex = state.tabs.indexWhere((t) => t.id == targetTabId);
    if (tabIndex == -1) return;

    final currentTab = state.tabs[tabIndex];
    final normalized = _service.normalizeUrl(
      input,
      defaultEngine: state.searchEngine,
    );

    final newHistory = List<String>.from(
      currentTab.history.take(currentTab.historyIndex + 1),
    )..add(normalized);

    final loadingTab = currentTab.copyWith(
      url: normalized,
      title: input.trim().isEmpty ? 'Caricamento...' : input.trim(),
      isLoading: true,
      clearError: true,
      history: newHistory,
      historyIndex: newHistory.length - 1,
    );

    _updateTab(loadingTab);

    // Record in recent searches if not a direct URL
    if (!_service.isUrl(input.trim()) && input.trim().isNotEmpty) {
      final recents = List<String>.from(state.recentSearches)
        ..remove(input.trim())
        ..insert(0, input.trim());
      state = state.copyWith(recentSearches: recents.take(10).toList());
    }

    try {
      final content = await _service.load(
        normalized,
        defaultEngine: state.searchEngine,
      );
      final loadedTab = loadingTab.copyWith(
        url: content.url,
        title: content.title.isNotEmpty ? content.title : normalized,
        isLoading: false,
        content: content,
      );
      _updateTab(loadedTab);
    } catch (e) {
      final errorTab = loadingTab.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      _updateTab(errorTab);
    }
  }

  Future<void> goBack({String? tabId}) async {
    final targetTabId = tabId ?? state.activeTabId;
    final tab = state.tabs.firstWhere((t) => t.id == targetTabId);
    if (!tab.canGoBack) return;

    final newIndex = tab.historyIndex - 1;
    final prevUrl = tab.history[newIndex];
    await _loadExistingHistory(tab, newIndex, prevUrl);
  }

  Future<void> goForward({String? tabId}) async {
    final targetTabId = tabId ?? state.activeTabId;
    final tab = state.tabs.firstWhere((t) => t.id == targetTabId);
    if (!tab.canGoForward) return;

    final newIndex = tab.historyIndex + 1;
    final nextUrl = tab.history[newIndex];
    await _loadExistingHistory(tab, newIndex, nextUrl);
  }

  Future<void> reload({String? tabId}) async {
    final targetTabId = tabId ?? state.activeTabId;
    final tab = state.tabs.firstWhere((t) => t.id == targetTabId);
    await navigate(tab.url, tabId: targetTabId);
  }

  Future<void> goHome({String? tabId}) async {
    await navigate('about:home', tabId: tabId);
  }

  Future<void> _loadExistingHistory(
    WebBrowserTab tab,
    int index,
    String url,
  ) async {
    final loadingTab = tab.copyWith(
      url: url,
      historyIndex: index,
      isLoading: true,
      clearError: true,
    );
    _updateTab(loadingTab);

    try {
      final content = await _service.load(
        url,
        defaultEngine: state.searchEngine,
      );
      final loadedTab = loadingTab.copyWith(
        title: content.title.isNotEmpty ? content.title : url,
        isLoading: false,
        content: content,
      );
      _updateTab(loadedTab);
    } catch (e) {
      final errorTab = loadingTab.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      _updateTab(errorTab);
    }
  }

  void newTab({String initialUrl = 'about:home', String initialTitle = 'Home'}) {
    _tabCounter++;
    final newId = 'tab_$_tabCounter';
    final tab = WebBrowserTab(
      id: newId,
      url: initialUrl,
      title: initialTitle,
      history: [initialUrl],
      historyIndex: 0,
    );
    state = state.copyWith(
      tabs: [...state.tabs, tab],
      activeTabId: newId,
    );
    if (initialUrl != 'about:home') {
      navigate(initialUrl, tabId: newId);
    }
  }

  void closeTab(String tabId) {
    if (state.tabs.length <= 1) {
      // Don't close last tab, just reset to home
      final resetTab = state.tabs.first.copyWith(
        url: 'about:home',
        title: 'Home',
        clearContent: true,
        clearError: true,
        history: ['about:home'],
        historyIndex: 0,
      );
      state = state.copyWith(tabs: [resetTab], activeTabId: resetTab.id);
      return;
    }

    final newTabs = state.tabs.where((t) => t.id != tabId).toList();
    var newActiveId = state.activeTabId;
    if (newActiveId == tabId) {
      newActiveId = newTabs.last.id;
    }
    state = state.copyWith(
      tabs: newTabs,
      activeTabId: newActiveId,
    );
  }

  void switchTab(String tabId) {
    if (state.tabs.any((t) => t.id == tabId)) {
      state = state.copyWith(activeTabId: tabId);
    }
  }

  void toggleBookmark(String url, String title) {
    final bookmarks = List<WebBookmark>.from(state.bookmarks);
    final exists = bookmarks.any((b) => b.url == url);
    if (exists) {
      bookmarks.removeWhere((b) => b.url == url);
    } else {
      bookmarks.add(WebBookmark(title: title, url: url));
    }
    state = state.copyWith(bookmarks: bookmarks);
  }

  void setSearchEngine(SearchEngine engine) {
    state = state.copyWith(searchEngine: engine);
  }

  void _updateTab(WebBrowserTab tab) {
    final updated = [
      for (final t in state.tabs)
        if (t.id == tab.id) tab else t,
    ];
    state = state.copyWith(tabs: updated);
  }
}
