import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/first_run/app_first_run_store.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/session_labels.dart';
import '../../ui/frame_list_row.dart';
import '../../ui/motion.dart';
import '../../ui/precision.dart';
import '../dialogs/new_session_dialog.dart';
import '../sessions_sidebar/session_actions.dart';
import '../workspace/repository_workspace.dart';
import 'recent_sessions.dart';

/// Most recent sessions listed on the welcome, grouped by repository.
const int _maxRecentSessions = 8;

/// Rise of each entrance item on the first run.
const double _riseOffset = FrameSpace.x3;

/// Welcome surface shown while no session is active: start a new session or
/// resume a recent one.
class WelcomeView extends ConsumerStatefulWidget {
  const WelcomeView({
    super.key,
    required this.narrow,
    required this.connected,
    required this.onOpenSessionsDrawer,
    required this.onOpenCommandPalette,
  });

  /// True when the sessions rail is not shown (narrow window).
  final bool narrow;
  final bool connected;
  final VoidCallback onOpenSessionsDrawer;
  final VoidCallback onOpenCommandPalette;

  @override
  ConsumerState<WelcomeView> createState() => _WelcomeViewState();
}

class _WelcomeViewState extends ConsumerState<WelcomeView>
    with SingleTickerProviderStateMixin {
  bool _creating = false;

  /// Drives the first-run entrance. Starts complete, so later launches show
  /// everything at once. It is rewound only on the first run.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _introChecked = false;
  bool _introReduced = false;

  AppStrings get strings => ref.watch(appStringsProvider);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introChecked) return;
    _introChecked = true;
    // Persisted: the entrance plays once per install, on the first run only.
    if (!ref.read(appFirstRunStoreProvider).consumeIntro()) return;
    _introReduced = FrameMotion.reduced(context);
    _intro
      ..duration = _introReduced
          ? FrameMotion.crossFade
          : FrameMotion.firstRun + FrameMotion.stagger * 2
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Entrance for item [index] (0 title, 1 description, 2 actions): 300 ms
  /// ease-out with a 12 px rise, each item 100 ms after the previous one. Under
  /// reduced motion it is a cross-fade with no movement.
  Widget _reveal(int index, Widget child) {
    if (_intro.isCompleted) return child;
    final total = _intro.duration!.inMicroseconds;
    final reduced = _introReduced;
    final begin = reduced
        ? 0.0
        : (FrameMotion.stagger * index).inMicroseconds / total;
    final end = reduced
        ? 1.0
        : (FrameMotion.stagger * index + FrameMotion.firstRun).inMicroseconds /
              total;
    final curve = Interval(begin, end, curve: FrameMotion.enterCurve);
    return AnimatedBuilder(
      animation: _intro,
      child: child,
      builder: (context, content) {
        final t = curve.transform(_intro.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, reduced ? 0 : (1 - t) * _riseOffset),
            child: content,
          ),
        );
      },
    );
  }

  Future<void> _create() async {
    if (_creating) return;
    // The button stays idle while the dialog is open. It shows progress only
    // after a folder has been chosen.
    final cwd = await showNewSessionDialog(context);
    if (cwd == null || !mounted) return;
    setState(() => _creating = true);
    await createSession(context, ref, cwd: cwd);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _openSession(String id) async {
    if (await switchSessionSafely(context, ref, id)) {
      ref.read(activeSessionIdProvider.notifier).state = id;
    }
  }

  /// Arrow keys and Enter need a hardware keyboard. Phones and tablets have
  /// none, so the shortcut hint is hidden there.
  bool get _hasHardwareKeyboard => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => false,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final wide = constraints.maxWidth >= 960;

        final sessions = resumableSessions(
          ref.watch(sessionListProvider).value ?? const [],
        );
        final recentSessions = sessions.take(_maxRecentSessions).toList();

        final startContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PiFrameMark(size: 48),
            const SizedBox(height: FrameSpace.x8),
            _reveal(
              0,
              Text(
                strings.welcomeTitle,
                style: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: compact ? 40 : 48,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                  color: tokens.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: FrameSpace.x6),
            _reveal(
              1,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  strings.welcomeDescription,
                  style: text.bodyLarge.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: FrameSpace.x6),
            _reveal(
              2,
              Wrap(
                spacing: FrameSpace.x3,
                runSpacing: FrameSpace.x3,
                children: [
                  PressFeedback(
                    child: FilledButton.icon(
                      key: const ValueKey('new-session-button'),
                      onPressed: widget.connected && !_creating
                          ? _create
                          : null,
                      icon: const Icon(Icons.add, size: FrameSize.iconLg),
                      label: Text(
                        _creating
                            ? strings.creatingSession
                            : strings.newSessionAction,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('browse-sessions-button'),
                    onPressed: widget.narrow
                        ? widget.onOpenSessionsDrawer
                        : widget.onOpenCommandPalette,
                    icon: const Icon(Icons.search, size: FrameSize.iconLg),
                    label: Text(strings.browseSessionsAction),
                  ),
                ],
              ),
            ),
            if (_hasHardwareKeyboard) ...[
              const SizedBox(height: FrameSpace.x8),
              Text(
                strings.commandsShortcutHint,
                style: text.caption.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        );

        final recentContent = recentSessions.isEmpty
            ? const SizedBox.shrink()
            : _buildRecentSessionsSection(tokens, text, recentSessions);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.all(compact ? FrameSpace.x6 : 48),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 5, child: startContent),
                        const SizedBox(width: 48),
                        Expanded(flex: 6, child: recentContent),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        startContent,
                        if (recentSessions.isNotEmpty) ...[
                          const SizedBox(height: FrameSpace.x8),
                          recentContent,
                        ],
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentSessionsSection(
    FrameTokens tokens,
    FrameText text,
    List<Map<String, dynamic>> sessions,
  ) {
    final sessionNames = ref.watch(sessionDisplayNamesProvider);

    // Group by repository. Groups keep the order of their most recent session.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final session in sessions) {
      groups.putIfAbsent(sessionFolder(session), () => []).add(session);
    }
    final folderLabels = folderDisplayNames(groups.keys);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: FrameSize.icon, color: tokens.accent),
              const SizedBox(width: FrameSpace.x2),
              Text(
                strings.recentSessionsHeader,
                style: text.title.copyWith(color: tokens.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: FrameSpace.x3),
          // Arrow keys move between the rows, Enter opens one.
          FocusTraversalGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: FrameSpace.x2,
                      bottom: FrameSpace.x1,
                    ),
                    child: Text(
                      group.key.isEmpty
                          ? strings.unknownFolderLabel
                          : folderLabels[group.key] ?? group.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.label.copyWith(color: tokens.textMuted),
                    ),
                  ),
                  for (final session in group.value)
                    FrameListRow(
                      key: ValueKey(
                        'quick-launch-session-${session['id'] ?? ''}',
                      ),
                      name:
                          sessionNames[session['id'] ?? ''] ??
                          (session['name'] ?? session['id'] ?? '').toString(),
                      leading: Icon(
                        Icons.chat_bubble_outline,
                        size: FrameSize.icon,
                        color: tokens.textSecondary,
                      ),
                      onTap: () =>
                          _openSession((session['id'] ?? '').toString()),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
