import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../workspace/repository_workspace.dart';

Future<String?> _chooseSessionDirectory(
  BuildContext context,
  String initialDirectory,
) => showDialog<String>(
  context: context,
  builder: (_) => _SessionDirectoryDialog(initialDirectory: initialDirectory),
);

class _SessionDirectoryDialog extends StatefulWidget {
  const _SessionDirectoryDialog({required this.initialDirectory});
  final String initialDirectory;

  @override
  State<_SessionDirectoryDialog> createState() =>
      _SessionDirectoryDialogState();
}

class _SessionDirectoryDialogState extends State<_SessionDirectoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDirectory,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final directory = await getDirectoryPath();
      if (mounted && directory != null) {
        setState(() => _controller.text = directory);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cartella non disponibile: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuova sessione'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('new-session-cwd'),
          controller: _controller,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Cartella di lavoro',
            hintText: 'C:\\Projects\\my-project',
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 8),
          const Text(
            'Nel browser inserisci il percorso locale raggiungibile dal daemon.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
    actions: [
      if (!kIsWeb)
        TextButton.icon(
          onPressed: _pickDirectory,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Scegli cartella'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Crea'),
      ),
    ],
  );
}

Future<void> createSession(
  BuildContext context,
  WidgetRef ref, {
  String? name,
  String? cwd,
}) async {
  final client = ref.read(pcpClientProvider);
  if (client == null) return;
  if (!await resolveDirtyRepository(
    context,
    ref,
    ref.read(activeSessionIdProvider),
  )) {
    return;
  }
  if (!context.mounted) return;

  var workingDirectory = cwd;
  if (workingDirectory == null) {
    final activeId = ref.read(activeSessionIdProvider);
    final initialDirectory = activeId == null
        ? ''
        : ref.read(sessionStateFamily(activeId)).cwd;
    workingDirectory = await _chooseSessionDirectory(context, initialDirectory);
  }
  if (!context.mounted) return;
  if (workingDirectory == null || workingDirectory.trim().isEmpty) return;

  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await client.sendCommand(
      PcpCommand(
        protocol: 1,
        id: 'cmd_$now',
        ts: now,
        commandId: PcpClient.newCommandId('crt'),
        type: 'session.create',
        payload: {'name': ?name, 'cwd': workingDirectory.trim()},
      ),
    );
    if (!context.mounted) return;
    final data = result['data'] as Map<String, dynamic>?;
    final session = data?['session'] as Map<String, dynamic>?;
    final id = session?['id'] as String?;
    if (id != null) {
      if (!await switchSessionSafely(context, ref, id)) return;
      ref.invalidate(sessionListProvider);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Creazione non riuscita: $error')));
    }
  }
}
