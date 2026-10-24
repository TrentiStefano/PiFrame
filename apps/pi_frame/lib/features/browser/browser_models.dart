import 'package:flutter/material.dart';

enum RightPaneMode {
  git,
  browser,
}

enum SearchEngine {
  duckDuckGo(
    label: 'DuckDuckGo',
    icon: Icons.search,
    searchUrlTemplate: 'https://html.duckduckgo.com/html/?q={query}',
    homeUrl: 'https://duckduckgo.com',
  ),
  pubDev(
    label: 'pub.dev',
    icon: Icons.inventory_2_outlined,
    searchUrlTemplate: 'https://pub.dev/packages?q={query}',
    homeUrl: 'https://pub.dev',
  ),
  wikipedia(
    label: 'Wikipedia',
    icon: Icons.menu_book_outlined,
    searchUrlTemplate: 'https://en.wikipedia.org/w/index.php?search={query}&fulltext=1',
    homeUrl: 'https://en.wikipedia.org',
  ),
  google(
    label: 'Google',
    icon: Icons.travel_explore,
    searchUrlTemplate: 'https://www.google.com/search?q={query}',
    homeUrl: 'https://www.google.com',
  ),
  github(
    label: 'GitHub',
    icon: Icons.code,
    searchUrlTemplate: 'https://github.com/search?q={query}',
    homeUrl: 'https://github.com',
  ),
  stackOverflow(
    label: 'Stack Overflow',
    icon: Icons.help_outline,
    searchUrlTemplate: 'https://stackoverflow.com/questions/tagged/{query}',
    homeUrl: 'https://stackoverflow.com',
  ),
  mdn(
    label: 'MDN Web Docs',
    icon: Icons.menu_book,
    searchUrlTemplate: 'https://developer.mozilla.org/en-US/search?q={query}',
    homeUrl: 'https://developer.mozilla.org',
  );

  final String label;
  final IconData icon;
  final String searchUrlTemplate;
  final String homeUrl;

  const SearchEngine({
    required this.label,
    required this.icon,
    required this.searchUrlTemplate,
    required this.homeUrl,
  });

  String buildSearchUrl(String query) {
    return searchUrlTemplate.replaceAll('{query}', Uri.encodeComponent(query));
  }
}

class WebLink {
  final String text;
  final String url;

  const WebLink({required this.text, required this.url});

  @override
  String toString() => '$text ($url)';
}

class WebSearchResult {
  final String title;
  final String url;
  final String snippet;
  final String domain;

  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    required this.domain,
  });
}

class WebContent {
  final String url;
  final String title;
  final String? description;
  final String domain;
  final List<String> headings;
  final List<String> paragraphs;
  final List<WebLink> links;
  final List<String> codeSnippets;
  final List<WebSearchResult> searchResults;
  final String rawText;

  const WebContent({
    required this.url,
    required this.title,
    this.description,
    required this.domain,
    this.headings = const [],
    this.paragraphs = const [],
    this.links = const [],
    this.codeSnippets = const [],
    this.searchResults = const [],
    this.rawText = '',
  });

  bool get isSearch => searchResults.isNotEmpty;
  bool get isEmpty =>
      title.isEmpty &&
      headings.isEmpty &&
      paragraphs.isEmpty &&
      searchResults.isEmpty &&
      rawText.trim().isEmpty &&
      links.isEmpty &&
      codeSnippets.isEmpty;
}

class WebBookmark {
  final String title;
  final String url;
  final IconData? icon;

  const WebBookmark({
    required this.title,
    required this.url,
    this.icon,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebBookmark &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}

class WebBrowserTab {
  final String id;
  final String url;
  final String title;
  final bool isLoading;
  final String? errorMessage;
  final List<String> history;
  final int historyIndex;
  final WebContent? content;

  const WebBrowserTab({
    required this.id,
    required this.url,
    required this.title,
    this.isLoading = false,
    this.errorMessage,
    this.history = const [],
    this.historyIndex = 0,
    this.content,
  });

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward => historyIndex < history.length - 1;
  bool get isHome => url == 'about:home';

  WebBrowserTab copyWith({
    String? id,
    String? url,
    String? title,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<String>? history,
    int? historyIndex,
    WebContent? content,
    bool clearContent = false,
  }) {
    return WebBrowserTab(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      content: clearContent ? null : (content ?? this.content),
    );
  }
}

class WebBrowserState {
  final List<WebBrowserTab> tabs;
  final String activeTabId;
  final SearchEngine searchEngine;
  final List<WebBookmark> bookmarks;
  final List<String> recentSearches;

  const WebBrowserState({
    required this.tabs,
    required this.activeTabId,
    this.searchEngine = SearchEngine.duckDuckGo,
    this.bookmarks = const [],
    this.recentSearches = const [],
  });

  WebBrowserTab get activeTab {
    return tabs.firstWhere(
      (t) => t.id == activeTabId,
      orElse: () => tabs.isNotEmpty
          ? tabs.first
          : const WebBrowserTab(id: 't_0', url: 'about:home', title: 'Home'),
    );
  }

  bool isBookmarked(String url) {
    return bookmarks.any((b) => b.url == url);
  }

  WebBrowserState copyWith({
    List<WebBrowserTab>? tabs,
    String? activeTabId,
    SearchEngine? searchEngine,
    List<WebBookmark>? bookmarks,
    List<String>? recentSearches,
  }) {
    return WebBrowserState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
      searchEngine: searchEngine ?? this.searchEngine,
      bookmarks: bookmarks ?? this.bookmarks,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}
