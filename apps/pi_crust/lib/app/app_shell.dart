import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';

import 'desktop_chrome.dart';
import '../ui/precision.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../data/theme/theme_providers.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/sessions_sidebar/session_actions.dart';
import '../features/transcript/transcript_view.dart';
import '../features/composer/composer.dart';
import '../features/context_panel/context_panel.dart';
import '../features/command_palette/command_palette.dart';
import '../features/settings/settings_view.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _inspector = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _inspectorOpen = false;
  bool _inspectorVisited = false;
  bool _creating = false;

  void _palette() => CommandPalette.show(
    context,
    onOpenSettings: () => ref.read(showSettingsProvider.notifier).state = true,
  );
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) setState(() => _creating = false);
  }

  void _toggleInspector() {
    setState(() {
      _inspectorVisited = true;
      _inspectorOpen = !_inspectorOpen;
    });
    _inspector.duration = context.tokens.panelDuration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _inspector.value = _inspectorOpen ? 1 : 0;
    } else if (_inspectorOpen) {
      _inspector.forward();
    } else {
      _inspector.reverse();
    }
  }

  @override
  void dispose() {
    _inspector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final activeId = ref.watch(activeSessionIdProvider);
    final settings = ref.watch(showSettingsProvider);
    final connection =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final connected = connection == DaemonConnectionState.connected;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 900;
    final dockInspector = width >= 1280;
    final nativeChrome = ref.watch(desktopChromeProvider);
    final reduced = MediaQuery.disableAnimationsOf(context);
    Widget workArea() => activeId == null
        ? _welcome(tokens, narrow, connected)
        : Column(
            children: [
              Expanded(
                child: TranscriptView(
                  key: ValueKey('transcript_$activeId'),
                  sessionId: activeId,
                ),
              ),
              Composer(
                key: ValueKey('composer_$activeId'),
                sessionId: activeId,
              ),
            ],
          );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          _palette();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: tokens.background,
        drawer: Drawer(
          width: 280,
          child: SessionsSidebar(
            onSessionSelected: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
        ),
        endDrawer: activeId == null
            ? null
            : Drawer(
                width: width < 420 ? width - 24 : 320,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Area di lavoro',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Chiudi workspace',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _scaffoldKey.currentState?.closeEndDrawer(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ContextPanel(
                          key: ValueKey('drawer-context_$activeId'),
                          sessionId: activeId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 76,
                decoration: BoxDecoration(
                  color: tokens.chassis,
                  border: Border(
                    bottom: BorderSide(color: tokens.borderStrong),
                  ),
                ),
                child: Row(
                  children: [
                    if (narrow)
                      IconButton(
                        tooltip: 'Apri sessioni',
                        icon: const Icon(Icons.menu),
                        onPressed: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                    Expanded(
                      child: DesktopDragRegion(
                        child: Padding(
                          padding: EdgeInsets.only(left: narrow ? 4 : 24),
                          child: Row(
                            children: [
                              const CrustMark(size: 28),
                              const SizedBox(width: 12),
                              BrandWordmark(size: width < 520 ? 30 : 38),
                              if (width > 920) ...[
                                const SizedBox(width: 32),
                                Icon(
                                  connected ? Icons.link : Icons.link_off,
                                  size: 16,
                                  color: tokens.textPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  connected ? 'Pi locale' : 'Non connesso',
                                  style: TextStyle(
                                    color: tokens.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (width > 680)
                      PressFeedback(
                        child: TextButton.icon(
                          onPressed: _palette,
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Comandi'),
                        ),
                      ),
                    IconButton(
                      tooltip: Theme.of(context).brightness == Brightness.light
                          ? 'Tema scuro'
                          : 'Tema chiaro',
                      icon: Icon(
                        Theme.of(context).brightness == Brightness.light
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 18,
                      ),
                      onPressed: () => ref
                          .read(activeThemeSpecProvider.notifier)
                          .setTheme(
                            Theme.of(context).brightness == Brightness.light
                                ? 'crust-dark'
                                : 'crust-light',
                          ),
                    ),
                    IconButton(
                      tooltip: 'Impostazioni',
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      onPressed: () =>
                          ref.read(showSettingsProvider.notifier).state =
                              !settings,
                    ),
                    if (activeId != null && !settings)
                      IconButton(
                        tooltip: 'Workspace e modello',
                        isSelected: dockInspector && _inspectorOpen,
                        icon: const Icon(Icons.tune, size: 19),
                        onPressed: () => dockInspector
                            ? _toggleInspector()
                            : _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    if (nativeChrome) ...[
                      Container(
                        width: 1,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: tokens.borderStrong,
                      ),
                      const DesktopCaptionButtons(),
                    ] else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
              if (!connected)
                Container(
                  color: tokens.signalWarning,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.link_off,
                        size: 17,
                        color: tokens.displaySurface,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          connection == DaemonConnectionState.reconnecting
                              ? 'Riconnessione al daemon in corso...'
                              : 'Daemon non raggiungibile. Le sessioni restano gestite da Pi.',
                          style: TextStyle(
                            color: tokens.displaySurface,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.displaySurface,
                        ),
                        onPressed: () => ref.invalidate(daemonEndpointProvider),
                        child: const Text('Riprova'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: settings
                    ? SettingsView(
                        onClose: () =>
                            ref.read(showSettingsProvider.notifier).state =
                                false,
                      )
                    : Row(
                        children: [
                          if (!narrow) const SessionsSidebar(),
                          Expanded(
                            child: Stack(
                              children: [
                                // Reserve space once per toggle, not on every animation frame.
                                Positioned.fill(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right:
                                          dockInspector &&
                                              _inspectorOpen &&
                                              activeId != null
                                          ? 320
                                          : 0,
                                    ),
                                    child: RepaintBoundary(child: workArea()),
                                  ),
                                ),
                                if (dockInspector &&
                                    activeId != null &&
                                    _inspectorVisited)
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    width: 320,
                                    child: IgnorePointer(
                                      ignoring: !_inspectorOpen,
                                      child: ExcludeFocus(
                                        excluding: !_inspectorOpen,
                                        child: ExcludeSemantics(
                                          excluding: !_inspectorOpen,
                                          child: AnimatedBuilder(
                                            animation: _inspector,
                                            child: ContextPanel(
                                              key: ValueKey(
                                                'context_$activeId',
                                              ),
                                              sessionId: activeId,
                                            ),
                                            builder: (context, child) =>
                                                Transform.translate(
                                                  key: const ValueKey(
                                                    'inspector-translation',
                                                  ),
                                                  offset: Offset(
                                                    reduced
                                                        ? (_inspectorOpen
                                                              ? 0
                                                              : 320)
                                                        : 320 *
                                                              (1 -
                                                                  tokens
                                                                      .panelCurve
                                                                      .transform(
                                                                        _inspector
                                                                            .value,
                                                                      )),
                                                    0,
                                                  ),
                                                  child: child,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome(CrustTokens tokens, bool narrow, bool connected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(compact ? 28 : 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CrustMark(size: compact ? 48 : 64),
                    const SizedBox(height: 32),
                    Text(
                      'Nuova\nsessione.',
                      style: TextStyle(
                        fontFamily: tokens.headingFontFamily,
                        fontSize: compact ? 68 : 96,
                        height: 0.95,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.0,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Text(
                        'Scegli una conversazione o inizia a lavorare con Pi. Il lavoro continua anche quando chiudi la finestra.',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        PressFeedback(
                          child: FilledButton.icon(
                            onPressed: connected && !_creating ? _create : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                              _creating ? 'Creazione...' : 'Nuova sessione',
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: narrow
                              ? () => _scaffoldKey.currentState?.openDrawer()
                              : _palette,
                          icon: const Icon(Icons.search, size: 18),
                          label: Text(
                            narrow ? 'Esplora sessioni' : 'Cerca nei comandi',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Ctrl / Cmd + K · Comandi',
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
