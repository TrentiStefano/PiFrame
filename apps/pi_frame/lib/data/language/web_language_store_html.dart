// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _key = 'piframe.language';

/// The web client (local browser or phone over remote access) has no access to
/// ~/.piframe, so the language choice lives in the browser's localStorage.
String? readWebLanguage() {
  try {
    final value = html.window.localStorage[_key];
    return (value == null || value.isEmpty) ? null : value;
  } catch (_) {
    return null;
  }
}

void writeWebLanguage(String code) {
  try {
    html.window.localStorage[_key] = code;
  } catch (_) {}
}

/// The browser's preferred language (`navigator.language`, such as `it-IT`), or null when it gives none.
String? readBrowserLanguage() {
  try {
    final value = html.window.navigator.language;
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}
