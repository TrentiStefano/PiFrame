// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<String?> getWebDeviceToken() async {
  try {
    final sessionTok = html.window.sessionStorage['pcp_device_token'];
    if (sessionTok != null && sessionTok.isNotEmpty) return sessionTok;
    final localTok = html.window.localStorage['pcp_device_token'];
    if (localTok != null && localTok.isNotEmpty) return localTok;
  } catch (_) {}
  return null;
}
