import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while a pane divider is being dragged. Layout-following widgets (the composer)
/// use it to skip size tweens so they track the divider instead of trailing it.
final paneDraggingProvider = StateProvider<bool>((ref) => false);
