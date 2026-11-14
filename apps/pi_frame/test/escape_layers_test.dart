import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/ui/escape_layers.dart';

/// A layer that is open until it is closed, as the shell and panes use the registry:
/// closing it unregisters it.
class _Layer {
  _Layer(this.name, EscapeLayers registry, EscapeLayer kind, this.log) {
    _unregister = registry.register(kind, () {
      if (!_open) return false;
      _open = false;
      log.add(name);
      _unregister();
      return true;
    });
  }

  final String name;
  final List<String> log;
  late final void Function() _unregister;
  bool _open = true;
}

void main() {
  test('closes the topmost layer first, one per Escape', () {
    final log = <String>[];
    final layers = EscapeLayers();
    _Layer('settings', layers, EscapeLayer.settings, log);
    _Layer('review', layers, EscapeLayer.review, log);
    _Layer('drawer', layers, EscapeLayer.drawer, log);

    expect(layers.closeTopmost(), isTrue);
    expect(layers.closeTopmost(), isTrue);
    expect(layers.closeTopmost(), isTrue);
    expect(layers.closeTopmost(), isFalse);
    expect(log, ['drawer', 'review', 'settings']);
    expect(layers.isOpen, isFalse);
  });

  test('within one kind the most recently registered layer closes first', () {
    final log = <String>[];
    final layers = EscapeLayers();
    _Layer('start drawer', layers, EscapeLayer.drawer, log);
    _Layer('end drawer', layers, EscapeLayer.drawer, log);

    layers.closeTopmost();
    expect(log, ['end drawer']);
  });

  test('a layer that cannot close is skipped; unregister removes it', () {
    final log = <String>[];
    final layers = EscapeLayers();
    final settings = _Layer('settings', layers, EscapeLayer.settings, log);
    final declines = layers.register(EscapeLayer.drawer, () => false);

    expect(layers.closeTopmost(), isTrue);
    expect(log, ['settings']);
    expect(settings._open, isFalse);

    declines();
    declines();
    expect(layers.isOpen, isFalse);
    expect(layers.closeTopmost(), isFalse);
  });
}
