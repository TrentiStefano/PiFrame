import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'desktop_notification_service.dart';

final appFocusProvider = StateProvider<bool>((ref) => true);

final notificationsEnabledProvider = StateProvider<bool>((ref) => true);

final desktopNotificationServiceProvider =
    Provider<DesktopNotificationService>((ref) => DesktopNotificationService.instance);
