import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The layers Escape closes, from the first one closed to the last (plan task 6.3).
///
/// Escape closes the topmost open layer. Within one kind, the most recently
/// registered layer closes first. Menus and dialogs are not registered here: they
/// take focus when they open, and Flutter's own dismiss action closes them before
/// the shell sees the key. Phase 3's in-pane diff registers as [diff].
enum EscapeLayer { menu, dialog, drawer, diff, review, settings }

class _EscapeEntry {
  _EscapeEntry(this.layer, this.sequence, this.close);

  final EscapeLayer layer;
  final int sequence;

  /// Closes the layer. Returns false when it could not close, so the next one is tried.
  final bool Function() close;
}

/// Registry of open Escape layers. The app shell asks it to close the topmost layer.
///
/// Usage: register when a layer opens, call the returned function when it closes
/// (usually from `dispose` or from the state change that closes it).
///
/// ```dart
/// _unregisterEscape = ref.read(escapeLayersProvider).register(
///   EscapeLayer.diff,
///   () { _closeDiff(); return true; },
/// );
/// // later
/// _unregisterEscape?.call();
/// ```
class EscapeLayers {
  final List<_EscapeEntry> _entries = <_EscapeEntry>[];
  int _sequence = 0;

  /// Registers an open layer. Returns the function that removes it again.
  void Function() register(EscapeLayer layer, bool Function() close) {
    final entry = _EscapeEntry(layer, _sequence++, close);
    _entries.add(entry);
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      _entries.remove(entry);
    };
  }

  /// True while any layer is open. The composer uses this to leave Escape to the
  /// shell instead of interrupting the agent.
  bool get isOpen => _entries.isNotEmpty;

  /// Closes the topmost layer. Returns false when no layer closed.
  bool closeTopmost() {
    final ordered = List<_EscapeEntry>.of(_entries)
      ..sort((a, b) {
        final byLayer = a.layer.index.compareTo(b.layer.index);
        return byLayer != 0 ? byLayer : b.sequence.compareTo(a.sequence);
      });
    for (final entry in ordered) {
      if (entry.close()) return true;
    }
    return false;
  }
}

/// The app-wide registry of open Escape layers.
final escapeLayersProvider = Provider<EscapeLayers>((ref) => EscapeLayers());
