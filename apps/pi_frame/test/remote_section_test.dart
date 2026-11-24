import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/platform/link_service.dart';
import 'package:pi_frame/features/settings/remote_section.dart';

import 'support/fake_platform_services.dart';

class _MockRemoteClient extends PcpClient {
  _MockRemoteClient({this.initialData}) : super(port: 1, token: 'test');
  final Map<String, dynamic>? initialData;
  Object? statusError;
  final _eventsController = StreamController<PcpEvent>.broadcast();

  void emitEvent(PcpEvent event) {
    _eventsController.add(event);
  }

  @override
  Stream<PcpEvent> events(String sessionId) => _eventsController.stream;

  @override
  Future<Map<String, dynamic>> getRemoteStatus() async {
    if (statusError != null) throw statusError!;
    return {
      'data':
          initialData ??
          {
            'enabled': false,
            'state': 'stopped',
            'tunnelProvider': 'cloudflared',
            'devices': [],
            'options': {'defaultMode': 'view'},
          },
    };
  }
}

void main() {
  testWidgets('RemoteSection renders disabled state and options', (tester) async {
    final client = _MockRemoteClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: Scaffold(body: RemoteSection())),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Secure Remote Connection'), findsOneWidget);
    expect(find.text('DISABLED'), findsOneWidget);
    expect(find.text('Enable Remote Access'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    // The provider card sits below the fold now that sections are taller.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Tunnel Provider Configuration'), findsOneWidget);
  });

  testWidgets('a failed status load shows a callout with raw text behind Dettagli', (tester) async {
    final client = _MockRemoteClient()..statusError = StateError('remote-boom-7');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: Scaffold(body: RemoteSection())),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('remote-error')), findsOneWidget);
    expect(find.text('Remote action failed'), findsOneWidget);
    expect(find.textContaining('remote-boom-7'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remote-error-details-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('remote-boom-7'), findsOneWidget);
  });

  testWidgets('RemoteSection renders active tunnel with QR code and device modes', (tester) async {
    final client = _MockRemoteClient(
      initialData: {
        'enabled': true,
        'state': 'running',
        'url': 'https://test-phone-tunnel.trycloudflare.com',
        'tunnelProvider': 'cloudflared',
        'localPort': 54321,
        'pairingPending': {
          'secret': 'pair_tok_mock123',
          'url': 'https://test-phone-tunnel.trycloudflare.com/#pair=pair_tok_mock123',
          'expiresAt': DateTime.now().millisecondsSinceEpoch + 600000,
        },
        'options': {'defaultMode': 'view'},
        'devices': [
          {
            'deviceId': 'dev_test_phone',
            'name': 'Apple iOS Device',
            'mode': 'view',
            'remoteIp': '198.51.100.42',
            'lastUsedAt': DateTime.now().millisecondsSinceEpoch,
            'expiresAt': DateTime.now().millisecondsSinceEpoch + 86400000,
          },
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: Scaffold(body: RemoteSection())),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Pair Your Smartphone'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    // Scroll down to reveal options and paired devices section
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('Default Mode for New Devices'), findsOneWidget);
    expect(find.text('Apple iOS Device'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
  });

  Map<String, dynamic> missingTailscaleData({required bool enabled}) => {
    'enabled': enabled,
    'state': 'stopped',
    'tunnelProvider': 'tailscale',
    'devices': [],
    'options': {'defaultMode': 'view'},
    'tailscale': {'installed': false, 'running': false},
  };

  Future<void> pumpRemoteWith(WidgetTester tester, Map<String, dynamic> data) async {
    final client = _MockRemoteClient(initialData: data);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: Scaffold(body: RemoteSection())),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('missing Tailscale callout is info while remote access is off', (tester) async {
    await pumpRemoteWith(tester, missingTailscaleData(enabled: false));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    // The missing-binary notice is a FrameCallout: its info tone uses the info icon.
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('remote-tailscale-missing')),
        matching: find.byIcon(Icons.info_outlined),
      ),
    );
    expect(icon.color, FrameTokens.dark.info);
    expect(icon.color, isNot(FrameTokens.dark.warning));
    expect(icon.color, isNot(FrameTokens.dark.danger));
  });

  testWidgets('missing Tailscale callout is warning once remote access is on', (tester) async {
    await pumpRemoteWith(tester, missingTailscaleData(enabled: true));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('remote-tailscale-missing')),
        matching: find.byIcon(Icons.warning_amber_outlined),
      ),
    );
    expect(icon.color, FrameTokens.dark.warning);
    expect(icon.color, isNot(FrameTokens.dark.danger));
  });

  testWidgets('open-in-browser button asks the link service to open the tunnel URL', (tester) async {
    const url = 'https://test-phone-tunnel.trycloudflare.com';
    final links = FakeLinkService();
    final client = _MockRemoteClient(
      initialData: {
        'enabled': true,
        'state': 'running',
        'url': url,
        'tunnelProvider': 'cloudflared',
        'localPort': 54321,
        'options': {'defaultMode': 'view'},
        'devices': [],
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pcpClientProvider.overrideWithValue(client), linkServiceProvider.overrideWithValue(links)],
        child: const MaterialApp(home: Scaffold(body: RemoteSection())),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.open_in_browser_outlined));
    await tester.pump();

    expect(links.opened, [Uri.parse(url)]);
  });
}
