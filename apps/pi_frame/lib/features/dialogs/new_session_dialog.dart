import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/language/strings_shell.dart';
import '../../domain/session/session_labels.dart';
import '../../ui/frame_dialog.dart';
import '../../ui/frame_icon_action.dart';
import '../../ui/frame_list_row.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/motion.dart';
import '../welcome/recent_sessions.dart';
import 'folder_probe.dart';

/// Delay between the last keystroke and the folder check that updates the notice.
const Duration _validationDelay = FrameMotion.debounce;

/// Asks for the working folder of a new session. Returns the trimmed path, or
/// null when cancelled. Enter creates when the folder is valid; Escape cancels.
Future<String?> showNewSessionDialog(BuildContext context, {String initialDirectory = ''}) =>
    showFrameDialogBuilder<String>(
      context: context,
      builder: (_) => _NewSessionDialog(initialDirectory: initialDirectory),
    );

class _NewSessionDialog extends ConsumerStatefulWidget {
  const _NewSessionDialog({required this.initialDirectory});

  final String initialDirectory;

  @override
  ConsumerState<_NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends ConsumerState<_NewSessionDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialDirectory);
  late FolderProbe _probe = probeFolder(widget.initialDirectory);
  // The text that [_probe] describes. Create stays disabled until they match.
  late String _probedText = widget.initialDirectory.trim();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _path => _controller.text.trim();

  bool get _canCreate => _probe.isValid && _probedText == _path;

  void _runProbe(String text) {
    final probe = probeFolder(text);
    setState(() {
      _probe = probe;
      _probedText = text.trim();
    });
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(_validationDelay, () {
      if (mounted) _runProbe(_controller.text);
    });
  }

  void _selectFolder(String folder) {
    _debounce?.cancel();
    _controller.text = folder;
    _runProbe(folder);
  }

  void _submit() {
    _debounce?.cancel();
    final probe = probeFolder(_path);
    setState(() {
      _probe = probe;
      _probedText = _path;
    });
    if (probe.isValid) Navigator.of(context).pop(_path);
  }

  Future<void> _pickDirectory() async {
    try {
      final directory = await getDirectoryPath();
      if (!mounted || directory == null) return;
      _debounce?.cancel();
      _controller.text = directory;
      _runProbe(directory);
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: ref.read(appStringsProvider).directoryNotAvailable(error));
      }
    }
  }

  String? _helperText(AppStrings strings) => switch (_probe.status) {
    FolderStatus.folder => strings.folderFoundNotice,
    FolderStatus.gitRepo =>
      _probe.branch == null ? strings.gitRepoDetectedPlainNotice : strings.gitRepoDetectedNotice(_probe.branch!),
    FolderStatus.unverified => strings.browserPathNotice,
    FolderStatus.empty || FolderStatus.notFound => null,
  };

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final tokens = context.tokens;
    final text = FrameText.of(context);
    final showNotFound = _probe.status == FolderStatus.notFound && _probedText == _path;
    final folders = recentSessionFolders(ref.watch(sessionListProvider).value ?? const []);
    final folderNames = folderDisplayNames(folders);

    return FrameDialog<String>(
      title: strings.newSessionDialogTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('new-session-cwd'),
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: strings.workingDirectoryLabel,
                    hintText: strings.folderPathPlaceholder,
                    errorText: showNotFound ? strings.folderNotFoundNotice : null,
                    helperText: _helperText(strings),
                  ),
                ),
              ),
              if (!kIsWeb) ...[
                const SizedBox(width: FrameSpace.x2),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FrameIconAction(
                    key: const ValueKey('new-session-pick-folder'),
                    icon: Icons.folder_open_outlined,
                    tooltip: strings.chooseFolderAction,
                    onPressed: _pickDirectory,
                  ),
                ),
              ],
            ],
          ),
          if (folders.isNotEmpty) ...[
            const SizedBox(height: FrameSpace.x4),
            Semantics(
              header: true,
              child: Text(strings.recentFoldersHeader, style: text.label.copyWith(color: tokens.textMuted)),
            ),
            const SizedBox(height: FrameSpace.x1),
            for (final folder in folders)
              FrameListRow(
                key: ValueKey('new-session-recent-$folder'),
                name: folderNames[folder] ?? folder,
                secondary: folder,
                leading: Icon(Icons.folder_outlined, size: FrameSize.icon, color: tokens.textSecondary),
                selected: folder == _path,
                onTap: () => _selectFolder(folder),
              ),
          ],
        ],
      ),
      actions: [
        FrameDialogAction<String>(label: strings.cancel, role: FrameDialogActionRole.cancel),
        FrameDialogAction<String>(
          key: const ValueKey('new-session-create'),
          label: strings.createAction,
          role: FrameDialogActionRole.primary,
          value: _path,
          enabled: _canCreate,
        ),
      ],
    );
  }
}
