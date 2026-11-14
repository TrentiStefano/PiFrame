import 'package:flutter/material.dart';

import '../../../data/language/language_settings.dart';
import '../../../data/language/strings_workspace.dart';

/// Asks for the commit message of the staged files. Returns the trimmed
/// message, or null when the dialog was cancelled.
Future<String?> showGitCommitDialog({
  required BuildContext context,
  required AppStrings strings,
  required TextEditingController controller,
  required List<String> staged,
  required Map<String, dynamic>? status,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(strings.commitStagedFilesTitle),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: (MediaQuery.sizeOf(ctx).height * 0.6).clamp(200.0, 420.0),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.commitDialogDetails(
                  root: status?['rootPath']?.toString() ?? '—',
                  branch: status?['branch']?.toString() ?? '—',
                  count: staged.length,
                  filesPreview: staged.take(5).join(', '),
                  remaining: staged.length > 5 ? staged.length - 5 : 0,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: strings.commitMessageLabel,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(strings.commitAction),
        ),
      ],
    ),
  );
}
