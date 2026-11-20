import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_transcript.dart';
import '../../ui/frame_middle_ellipsis.dart';
import '../composer/composer_focus_provider.dart';

/// Empty chat (plan 4.6): shown in place of the transcript while a session has
/// no messages. It names the working folder and branch and gives three
/// keyboard hints. It has no button of its own, so it does not use
/// `FrameEmptyState`, whose contract is one action button.
class EmptyChatView extends ConsumerStatefulWidget {
  final String sessionId;
  final String cwd;

  const EmptyChatView({super.key, required this.sessionId, required this.cwd});

  @override
  ConsumerState<EmptyChatView> createState() => _EmptyChatViewState();
}

class _EmptyChatViewState extends ConsumerState<EmptyChatView> {
  String? _branch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Start the new chat with the cursor in the composer.
      ref.read(composerFocusRequestProvider(widget.sessionId).notifier).state++;
      _loadBranch();
    });
  }

  Future<void> _loadBranch() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final result = await client.refreshWorkspace(widget.sessionId);
      final data = (result['data'] as Map<String, dynamic>?) ?? result;
      final branch = data['branch']?.toString();
      if (mounted && branch != null && branch.isNotEmpty) {
        setState(() => _branch = branch);
      }
    } catch (_) {
      // The branch is optional context; the view works without it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final strings = ref.watch(appStringsProvider);
    final hints = [strings.emptyChatHintCommands, strings.emptyChatHintAttach, strings.emptyChatHintPalette];

    // Scrolls when the pane is shorter than the content (side panel, phone).
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(FrameSpace.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              key: const ValueKey('empty-chat'),
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: Icon(Icons.chat_bubble_outline, size: 32, color: tokens.textMuted)),
                const SizedBox(height: FrameSpace.x3),
                Semantics(
                  header: true,
                  child: Text(
                    strings.emptyChatTitle,
                    textAlign: TextAlign.center,
                    style: text.title.copyWith(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(height: FrameSpace.x2),
                FrameMiddleEllipsis(
                  text: widget.cwd,
                  style: text.mono.copyWith(color: tokens.textMuted),
                ),
                if (_branch != null) ...[
                  const SizedBox(height: FrameSpace.x1),
                  Row(
                    key: const ValueKey('empty-chat-branch'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_split_outlined, size: FrameSize.icon, color: tokens.textMuted),
                      const SizedBox(width: FrameSpace.x1),
                      Flexible(
                        child: Text(
                          _branch!,
                          overflow: TextOverflow.ellipsis,
                          style: text.mono.copyWith(color: tokens.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: FrameSpace.x4),
                for (var i = 0; i < hints.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FrameSpace.x1),
                    child: Text(
                      hints[i],
                      key: ValueKey('empty-chat-hint-$i'),
                      textAlign: TextAlign.center,
                      style: text.body.copyWith(color: tokens.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
