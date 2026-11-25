import 'package:web/web.dart' as web;

Future<String?> getWebDeviceToken() async {
  try {
    final sessionTok = web.window.sessionStorage.getItem('pcp_device_token');
    if (sessionTok != null && sessionTok.isNotEmpty) return sessionTok;
    final localTok = web.window.localStorage.getItem('pcp_device_token');
    if (localTok != null && localTok.isNotEmpty) return localTok;
  } catch (_) {}
  return null;
}
