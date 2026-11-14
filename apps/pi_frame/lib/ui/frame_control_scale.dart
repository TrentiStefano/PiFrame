import 'package:flutter/widgets.dart';

/// Largest factor the shared control sizes grow by with the system text scale.
const double frameControlScaleCap = 1.5;

/// Scale factor for icon and target sizes inside shared controls.
///
/// Follows the platform text scale so an icon does not look small next to a
/// label that has grown, but never above [frameControlScaleCap] so a 2.0 text
/// scale does not turn a toolbar into a wall of pixels. Never below 1.0.
double frameControlScale(BuildContext context) {
  final factor = MediaQuery.textScalerOf(context).scale(1);
  return factor.clamp(1.0, frameControlScaleCap).toDouble();
}
