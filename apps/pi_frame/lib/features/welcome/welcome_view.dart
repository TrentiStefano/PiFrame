import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/session_labels.dart';
import '../../ui/precision.dart';
import '../sessions_sidebar/session_actions.dart';
import '../workspace/repository_workspace.dart';

/// Welcome surface shown while no session is active: start a session or resume
/// a recent one. Moved out of `AppShell` without behaviour change.
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

class _WelcomeViewState extends ConsumerState<WelcomeView> {
  bool _creating = false;

  AppStrings get strings => ref.watch(appStringsProvider);

  VoidCallback get onOpenSessionsDrawer => widget.onOpenSessionsDrawer;
  VoidCallback get onOpenCommandPalette => widget.onOpenCommandPalette;

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) =>
      _welcome(context.tokens, widget.narrow, widget.connected);

  bool _isSubsession(Map<String, dynamic> session) {
    if (session['isSubsession'] == true) return true;
    final parentSession = (session['parentSession'] ?? '').toString().trim();
    if (parentSession.isNotEmpty) return true;
    final name = (session['name'] ?? '').toString().toLowerCase();
    final id = (session['id'] ?? '').toString().toLowerCase();
    return name.contains('worker#') ||
        id.contains('worker#') ||
        name.contains('#') ||
        id.contains('#') ||
        name.startsWith('subagent') ||
        id.startsWith('subagent');
  }

  String _sessionFolder(Map<String, dynamic> session) {
    return sessionFolder(session);
  }

  int _sessionTimestamp(Map<String, dynamic> s) {
    final raw = s['updatedAt'] ?? s['mtime'] ?? s['createdAt'] ?? s['ts'];
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsedNum = int.tryParse(raw);
      if (parsedNum != null) return parsedNum;
      final parsedDate = DateTime.tryParse(raw);
      if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
    }
    return 0;
  }

  Widget _buildRecentSessionsSection(
    FrameTokens tokens,
    List<Map<String, dynamic>> sessions,
    bool compact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 16, color: tokens.accent),
            const SizedBox(width: 8),
            Text(
              strings.recentSessionsHeader,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                'Quick Launch',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              for (final session in sessions)
                _buildQuickLaunchSessionCard(tokens, session),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLaunchSessionCard(
    FrameTokens tokens,
    Map<String, dynamic> session,
  ) {
    final id = (session['id'] ?? '').toString();
    final name = ref.watch(sessionDisplayNamesProvider)[id] ??
        (session['name'] ?? id).toString();
    final folder = _sessionFolder(session);
    final folderDisplay = folder.isNotEmpty ? folder : strings.noFolderDisplay;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('quick-launch-session-$id'),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: () async {
            if (await switchSessionSafely(context, ref, id)) {
              ref.read(activeSessionIdProvider.notifier).state = id;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        folderDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(FrameTokens tokens, bool narrow, bool connected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final wide = constraints.maxWidth >= 960;

          final sessionsList = (ref.watch(sessionListProvider).value ?? const [])
              .where((s) => !_isSubsession(s))
              .toList();

          sessionsList.sort((a, b) {
            final tsB = _sessionTimestamp(b);
            final tsA = _sessionTimestamp(a);
            if (tsB != 0 || tsA != 0) return tsB.compareTo(tsA);
            return 0;
          });

          final recentSessions = sessionsList.take(5).toList();

          final startContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiFrameMark(size: compact ? 48 : 64),
              const SizedBox(height: 32),
              Text(
                strings.newSessionHeroTitle,
                style: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: compact ? 56 : 84,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Text(
                  strings.welcomeDescription,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  PressFeedback(
                    child: FilledButton.icon(
                      key: const ValueKey('new-session-button'),
                      onPressed: connected && !_creating ? _create : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        _creating ? strings.creatingSession : strings.newSessionAction,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: narrow
                        ? onOpenSessionsDrawer
                        : onOpenCommandPalette,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(
                      narrow ? strings.browseSessionsAction : strings.searchCommandsAction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                strings.commandsShortcutHint,
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ],
          );

          final recentContent = recentSessions.isEmpty
              ? const SizedBox.shrink()
              : _buildRecentSessionsSection(tokens, recentSessions, compact);

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(compact ? 24 : 48),
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
                            const SizedBox(height: 40),
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
