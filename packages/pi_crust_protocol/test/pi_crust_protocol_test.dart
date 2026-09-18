import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust_protocol/pi_crust_protocol.dart';

void main() {
  group('PcpCodec & Envelopes', () {
    test('encodes and decodes a command message', () {
      final cmd = PcpCommand.create(
        commandId: 'cmd_001',
        sessionId: 's_001',
        type: 'agent.prompt',
        payload: {'message': 'Hello'},
      );

      final encoded = PcpCodec.encodeMessage(cmd);
      final decoded = PcpCodec.decodeMessage(encoded);

      expect(decoded, isA<PcpCommand>());
      final decodedCmd = decoded as PcpCommand;
      expect(decodedCmd.commandId, 'cmd_001');
      expect(decodedCmd.sessionId, 's_001');
      expect(decodedCmd.type, 'agent.prompt');
      expect(decodedCmd.payload['message'], 'Hello');
    });

    test('decodes specific event subclasses correctly', () {
      const textDeltaJson = '''
      {
        "protocol": 1,
        "kind": "event",
        "id": "evt_001",
        "ts": 1726640000000,
        "sessionId": "s_001",
        "seq": 10,
        "type": "text.delta",
        "payload": {
          "contentIndex": 0,
          "delta": "streamed token"
        }
      }
      ''';

      final msg = PcpCodec.decodeMessage(textDeltaJson);
      expect(msg, isA<TextDeltaEvent>());
      final evt = msg as TextDeltaEvent;
      expect(evt.contentIndex, 0);
      expect(evt.delta, 'streamed token');
      expect(evt.seq, 10);
    });

    test('decodes UnknownEvent for forward compatibility without throwing', () {
      const futureEventJson = '''
      {
        "protocol": 1,
        "kind": "event",
        "id": "evt_future_001",
        "ts": 1726640000000,
        "sessionId": "s_001",
        "seq": 11,
        "type": "quantum.teleportation.v2",
        "payload": {
          "coordinates": [1, 2, 3]
        }
      }
      ''';

      final msg = PcpCodec.decodeMessage(futureEventJson);
      expect(msg, isA<UnknownEvent>());
      final evt = msg as UnknownEvent;
      expect(evt.type, 'quantum.teleportation.v2');
      expect(evt.seq, 11);
      expect(evt.payload['coordinates'], [1, 2, 3]);
    });

    test('decodes a full session snapshot', () {
      const snapshotJson = '''
      {
        "protocol": 1,
        "kind": "snapshot",
        "id": "sna_001",
        "ts": 1726640000000,
        "sessionId": "s_001",
        "seq": 50,
        "type": "session.snapshot",
        "payload": {
          "session": {
            "id": "s_001",
            "name": "Auth session",
            "cwd": "C:/Repos/pi-crust"
          },
          "runtime": {
            "status": "working",
            "isStreaming": true,
            "isCompacting": false,
            "autoCompaction": true,
            "queue": {
              "steering": ["Steer text"],
              "followUp": []
            }
          },
          "transcript": {
            "entries": [],
            "leafId": null
          },
          "activeTools": [],
          "pendingUiRequests": [],
          "usage": {},
          "workspace": {}
        }
      }
      ''';

      final msg = PcpCodec.decodeMessage(snapshotJson);
      expect(msg, isA<PcpSnapshot>());
      final sna = msg as PcpSnapshot;
      expect(sna.sessionId, 's_001');
      expect(sna.seq, 50);
      expect(sna.session.name, 'Auth session');
      expect(sna.runtime.status, 'working');
      expect(sna.runtime.steeringQueue, ['Steer text']);
    });
  });
}
