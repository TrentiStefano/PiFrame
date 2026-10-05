import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';

Future<void> createSession(BuildContext context, WidgetRef ref) async {
  final client = ref.read(pcpClientProvider);
  if (client == null) return;
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await client.sendCommand(
      PcpCommand(
        protocol: 1,
        id: 'cmd_$now',
        ts: now,
        commandId: PcpClient.newCommandId('crt'),
        type: 'session.create',
        payload: {},
      ),
    );
    if (!context.mounted) return;
    final data = result['data'] as Map<String, dynamic>?;
    final session = data?['session'] as Map<String, dynamic>?;
    final id = session?['id'] as String?;
    if (id != null) {
      ref.read(activeSessionIdProvider.notifier).state = id;
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
