import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the composer of a session to take keyboard focus.
///
/// Bump the value (`ref.read(composerFocusRequestProvider(id).notifier).state++`) to request focus.
/// The transcript's empty state uses it so a new chat starts with the cursor in the field.
final composerFocusRequestProvider = StateProvider.family<int, String>(
  (ref, sessionId) => 0,
);
