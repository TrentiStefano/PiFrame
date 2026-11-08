import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// iOS-style concentric corners for the browser on rounded-corner iPhones.
///
/// Native iOS apps follow the display curve: an element inset by `m` from the screen edge uses a
/// corner radius of `displayRadius - m`. A web page cannot read the device's corner radius, so it is
/// estimated from the logical width of the phone (390pt = iPhone 12/13/14 -> ~47pt, 393/430pt =
/// iPhone 14 Pro/15/16 -> ~55pt, 375pt = X/11/mini -> ~40pt).
///
/// Returns null when the curve does not matter: not the browser, not phone sized, the browser already
/// reports a safe area, or the viewport is not tall (Safari toolbars/keyboard cover the bottom).
double? phoneDisplayCornerRadius(BuildContext context) {
  if (!kIsWeb) return null;
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 600) return null;
  if (MediaQuery.paddingOf(context).bottom > 0) return null;
  if (size.height / size.width <= 1.9) return null;
  if (size.width <= 380) return 40;
  if (size.width < 392) return 47;
  return 55;
}

/// Radius for an element whose corner is [inset] logical pixels from the screen corner.
double concentricRadius(double displayRadius, double inset, {double min = 0}) {
  final r = displayRadius - inset;
  return r < min ? min : r;
}
