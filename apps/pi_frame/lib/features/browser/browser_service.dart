import 'dart:convert';
import 'package:http/http.dart' as http;
import 'browser_models.dart';

class WebBrowserService {
  final http.Client _client;

  WebBrowserService({http.Client? client}) : _client = client ?? http.Client();

  static const _tlds = {
    'com',
    'org',
    'net',
    'edu',
    'gov',
    'dev',
    'io',
    'app',
    'ai',
    'it',
    'de',
    'uk',
    'fr',
    'es',
    'eu',
    'me',
    'co',
    'info',
    'biz',
    'xyz',
  };

  bool isUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('about:')) return true;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }
    if (trimmed.startsWith('localhost') || trimmed.startsWith('127.0.0.1')) {
      return true;
    }
    if (!trimmed.contains(' ') && trimmed.contains('.')) {
      final parts = trimmed.split('/')[0].split(':');
      final host = parts[0];
      final segments = host.split('.');
      if (segments.length >= 2) {
        final tld = segments.last.toLowerCase();
        if (_tlds.contains(tld)) return true;
      }
    }
    return false;
  }

  String normalizeUrl(
    String input, {
    SearchEngine defaultEngine = SearchEngine.duckDuckGo,
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed == 'about:home') return 'about:home';
    if (isUrl(trimmed)) {
      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('about:')) {
        return trimmed;
      }
      if (trimmed.startsWith('localhost') || trimmed.startsWith('127.0.0.1')) {
        return 'http://$trimmed';
      }
      return 'https://$trimmed';
    }
    return defaultEngine.buildSearchUrl(trimmed);
  }

  Future<WebContent> load(
    String rawInput, {
    SearchEngine defaultEngine = SearchEngine.duckDuckGo,
  }) async {
    final targetUrl = normalizeUrl(rawInput, defaultEngine: defaultEngine);
    if (targetUrl == 'about:home') {
      return const WebContent(
        url: 'about:home',
        title: 'Home',
        domain: 'about:home',
        paragraphs: ['Benvenuto nel browser integrato di PiFrame.'],
      );
    }

    final isSearchQuery = !isUrl(rawInput.trim()) && !rawInput.startsWith('about:');
    final queryText = isSearchQuery ? rawInput.trim() : null;

    final uri = Uri.parse(targetUrl);
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7',
      'Sec-Ch-Ua': '"Chromium";v="124", "Google Chrome";v="124"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
    };

    final response = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    String html;
    try {
      html = utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      html = response.body;
    }

    final finalUri = response.request?.url ?? uri;
    final finalUrl = finalUri.toString();
    final domain = finalUri.host.isNotEmpty ? finalUri.host : finalUrl;
    final title = _extractTitle(html) ?? (queryText != null ? 'Ricerca: $queryText' : domain);
    final description = _extractMetaDescription(html);
    final headings = _extractHeadings(html);
    final codeSnippets = _extractCodeSnippets(html);
    final links = _extractLinks(html, finalUri);
    final searchResults = _extractSearchResults(html, finalUri, queryText);
    final paragraphs = _extractParagraphs(html);
    final rawText = _extractReadableText(html);

    return WebContent(
      url: finalUrl,
      title: title,
      description: description,
      domain: domain,
      headings: headings,
      paragraphs: paragraphs,
      links: links,
      codeSnippets: codeSnippets,
      searchResults: searchResults,
      rawText: rawText,
    );
  }

  String? _extractTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (match != null) {
      return _cleanText(match.group(1) ?? '');
    }
    return null;
  }

  String? _extractMetaDescription(String html) {
    final match = RegExp(
      r'''<meta\s+[^>]*name=["']description["'][^>]*content=["'](.*?)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html) ??
    RegExp(
      r'''<meta\s+[^>]*content=["'](.*?)["'][^>]*name=["']description["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html) ??
    RegExp(
      r'''<meta\s+[^>]*property=["']og:description["'][^>]*content=["'](.*?)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);

    if (match != null) {
      return _cleanText(match.group(1) ?? '');
    }
    return null;
  }

  List<String> _extractHeadings(String html) {
    final headings = <String>[];
    final regex = RegExp(
      r'<h[1-4][^>]*>(.*?)</h[1-4]>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in regex.allMatches(html)) {
      final text = _cleanText(match.group(1) ?? '');
      if (text.isNotEmpty && !headings.contains(text) && text.length < 150) {
        headings.add(text);
      }
      if (headings.length >= 10) break;
    }
    return headings;
  }

  List<String> _extractCodeSnippets(String html) {
    final codeSnippets = <String>[];
    final regex = RegExp(
      r'<pre[^>]*><code[^>]*>(.*?)</code></pre>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in regex.allMatches(html)) {
      final text = _cleanHtmlEntities(match.group(1) ?? '').trim();
      if (text.isNotEmpty && !codeSnippets.contains(text)) {
        codeSnippets.add(text);
      }
      if (codeSnippets.length >= 8) break;
    }
    return codeSnippets;
  }

  List<WebLink> _extractLinks(String html, Uri baseUri) {
    final links = <WebLink>[];
    final regex = RegExp(
      r'''<a\s+[^>]*href=["']([^"'#]+)["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in regex.allMatches(html)) {
      final href = match.group(1) ?? '';
      final text = _cleanText(match.group(2) ?? '');
      if (text.isEmpty || href.isEmpty || href.startsWith('javascript:')) {
        continue;
      }

      String resolved;
      try {
        final parsed = Uri.parse(href);
        resolved = parsed.isAbsolute ? parsed.toString() : baseUri.resolveUri(parsed).toString();
      } catch (_) {
        continue;
      }

      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        if (!links.any((l) => l.url == resolved)) {
          links.add(WebLink(text: text, url: resolved));
        }
      }
      if (links.length >= 25) break;
    }
    return links;
  }

  List<WebSearchResult> _extractSearchResults(String html, Uri baseUri, String? query) {
    final results = <WebSearchResult>[];

    // 1. DuckDuckGo HTML search results
    final ddgTitleMatches = RegExp(
      r'''<a\s+[^>]*class=["'][^"']*result__a[^"']*["'][^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();

    final ddgSnippetMatches = RegExp(
      r'''<a\s+[^>]*class=["'][^"']*result__snippet[^"']*["'][^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html).toList();

    if (ddgTitleMatches.isNotEmpty) {
      for (int i = 0; i < ddgTitleMatches.length; i++) {
        final titleMatch = ddgTitleMatches[i];
        final rawHref = titleMatch.group(1) ?? '';
        final title = _cleanText(titleMatch.group(2) ?? '');
        final actualUrl = _decodeDuckDuckGoUrl(rawHref);
        String snippet = '';
        if (i < ddgSnippetMatches.length) {
          snippet = _cleanText(ddgSnippetMatches[i].group(2) ?? '');
        }
        if (actualUrl.isNotEmpty && title.isNotEmpty) {
          results.add(
            WebSearchResult(
              title: title,
              url: actualUrl,
              snippet: snippet.isNotEmpty ? snippet : 'Risultato DuckDuckGo per "${query ?? ''}"',
              domain: Uri.tryParse(actualUrl)?.host ?? '',
            ),
          );
        }
        if (results.length >= 15) break;
      }
    } else if (ddgSnippetMatches.isNotEmpty) {
      for (final match in ddgSnippetMatches) {
        final rawHref = match.group(1) ?? '';
        final snippet = _cleanText(match.group(2) ?? '');
        final actualUrl = _decodeDuckDuckGoUrl(rawHref);
        final title = actualUrl.split('/').last.replaceAll('-', ' ');
        results.add(
          WebSearchResult(
            title: title.isEmpty ? actualUrl : title,
            url: actualUrl,
            snippet: snippet,
            domain: Uri.tryParse(actualUrl)?.host ?? '',
          ),
        );
      }
    }

    // 2. Wikipedia search results
    if (results.isEmpty && (baseUri.host.contains('wikipedia.org') || html.contains('mw-search-result'))) {
      final wikiMatches = RegExp(
        r'''<div\s+class=["']mw-search-result-heading["'][^>]*><a\s+href=["']([^"']+)["'][^>]*>(.*?)</a></div>(?:\s*<div\s+class=["']searchresult["'][^>]*>(.*?)</div>)?''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html);

      for (final match in wikiMatches) {
        final relHref = match.group(1) ?? '';
        final title = _cleanText(match.group(2) ?? '');
        final snippet = _cleanText(match.group(3) ?? '');
        final actualUrl = baseUri.resolve(relHref).toString();
        results.add(
          WebSearchResult(
            title: title,
            url: actualUrl,
            snippet: snippet,
            domain: 'en.wikipedia.org',
          ),
        );
        if (results.length >= 15) break;
      }
    }

    // 3. pub.dev package search results
    if (results.isEmpty && baseUri.host.contains('pub.dev')) {
      final pkgMatches = RegExp(
        r'''<a\s+[^>]*href=["'](/packages/([a-zA-Z0-9_]+))["'][^>]*>(.*?)</a>''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html);

      final seenPkgs = <String>{};
      for (final match in pkgMatches) {
        final pkgPath = match.group(1) ?? '';
        final pkgName = match.group(2) ?? '';
        final text = _cleanText(match.group(3) ?? '');
        if (pkgName.isNotEmpty && text == pkgName && seenPkgs.add(pkgName)) {
          results.add(
            WebSearchResult(
              title: pkgName,
              url: 'https://pub.dev$pkgPath',
              snippet: 'Dart / Flutter package su pub.dev',
              domain: 'pub.dev',
            ),
          );
          if (results.length >= 15) break;
        }
      }
    }

    // 4. Generic H3 + Anchor search results
    if (results.isEmpty && query != null) {
      final h3Matches = RegExp(
        r'''<h3[^>]*>\s*<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>\s*</h3>''',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html);

      for (final match in h3Matches) {
        final href = match.group(1) ?? '';
        final title = _cleanText(match.group(2) ?? '');
        final resolved = Uri.tryParse(href)?.isAbsolute == true
            ? href
            : baseUri.resolve(href).toString();
        final linkUri = Uri.tryParse(resolved);
        if (linkUri != null && title.isNotEmpty && !results.any((r) => r.url == resolved)) {
          results.add(
            WebSearchResult(
              title: title,
              url: resolved,
              snippet: 'Risultato da ${linkUri.host}',
              domain: linkUri.host,
            ),
          );
          if (results.length >= 12) break;
        }
      }
    }

    // 5. Generic external link fallback
    if (results.isEmpty && query != null) {
      final links = _extractLinks(html, baseUri);
      for (final link in links) {
        final linkUri = Uri.tryParse(link.url);
        if (linkUri != null && linkUri.host != baseUri.host && link.text.length > 5) {
          results.add(
            WebSearchResult(
              title: link.text,
              url: link.url,
              snippet: 'Risultato correlato per "$query" da ${linkUri.host}',
              domain: linkUri.host,
            ),
          );
          if (results.length >= 10) break;
        }
      }
    }

    return results;
  }

  String _decodeDuckDuckGoUrl(String raw) {
    if (raw.contains('uddg=')) {
      final match = RegExp(r'uddg=([^&]+)').firstMatch(raw);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
    }
    if (raw.startsWith('//')) {
      return 'https:$raw';
    }
    return raw;
  }

  List<String> _extractParagraphs(String html) {
    final paragraphs = <String>[];
    final regex = RegExp(
      r'<p[^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in regex.allMatches(html)) {
      final text = _cleanText(match.group(1) ?? '');
      if (text.length > 20 &&
          !text.startsWith('{') &&
          !text.startsWith('window.') &&
          !text.contains('function(') &&
          !paragraphs.contains(text)) {
        paragraphs.add(text);
      }
      if (paragraphs.length >= 25) break;
    }

    // Fallback: If page has few <p> tags, extract readable blocks from <article>, <section>, <li>, <blockquote>
    if (paragraphs.length < 3) {
      final blockRegex = RegExp(
        r'<(?:article|section|li|blockquote)[^>]*>(.*?)</(?:article|section|li|blockquote)>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final match in blockRegex.allMatches(html)) {
        final text = _cleanText(match.group(1) ?? '');
        if (text.length > 30 &&
            text.length < 600 &&
            !text.startsWith('{') &&
            !text.startsWith('window.') &&
            !text.contains('function(') &&
            !paragraphs.contains(text)) {
          paragraphs.add(text);
        }
        if (paragraphs.length >= 25) break;
      }
    }

    return paragraphs;
  }

  String _extractReadableText(String html) {
    final cleaned = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<svg[^>]*>.*?</svg>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true, caseSensitive: false), '');
    return _cleanText(cleaned);
  }

  String _cleanText(String input) {
    return _cleanHtmlEntities(input)
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanHtmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&middot;', '·');
  }
}
