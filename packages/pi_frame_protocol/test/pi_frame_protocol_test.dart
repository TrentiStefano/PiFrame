import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';

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
            "cwd": "C:/Repos/pi-frame"
          },
          "runtime": {
            "status": "working",
            "isStreaming": true,
            "runStartedAt": 1726639990000,
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
      expect(sna.runtime.runStartedAt, 1726639990000);
      expect(sna.runtime.steeringQueue, ['Steer text']);
      expect(RuntimeMeta.fromJson({}).runStartedAt, isNull);
    });

    test('decodes SystemMetricsEvent correctly', () {
      const metricsJson = '''
      {
        "protocol": 1,
        "kind": "event",
        "id": "evt_metrics_001",
        "ts": 1726640000000,
        "sessionId": "@daemon",
        "seq": 0,
        "type": "system.metrics",
        "payload": {
          "sampledAt": 1726640000000,
          "cpu": { "percent": 34.5 },
          "memory": { "usedBytes": 8000, "totalBytes": 16000, "percent": 50.0 },
          "disk": { "usedBytes": 10000, "totalBytes": 50000, "percent": 20.0 },
          "gpu": {
            "percent": 15.0,
            "memoryUsedBytes": 1024,
            "memoryTotalBytes": 8192,
            "source": "nvidia-smi"
          }
        }
      }
      ''';

      final msg = PcpCodec.decodeMessage(metricsJson);
      expect(msg, isA<SystemMetricsEvent>());
      final evt = msg as SystemMetricsEvent;
      expect(evt.sessionId, '@daemon');
      expect(evt.seq, 0);
      expect(evt.sampledAt, 1726640000000);
      expect(evt.cpu?['percent'], 34.5);
      expect(evt.memory?['percent'], 50.0);
      expect(evt.disk?['percent'], 20.0);
      expect(evt.gpu?['percent'], 15.0);
      expect(evt.gpu?['source'], 'nvidia-smi');
    });

    test('decodes RemoteStatusChangedEvent correctly', () {
      const remoteStatusJson = '''
      {
        "protocol": 1,
        "kind": "event",
        "id": "evt_remote_001",
        "ts": 1726640000000,
        "sessionId": "@daemon",
        "seq": 0,
        "type": "remote.statusChanged",
        "payload": {
          "enabled": true,
          "state": "running"
        }
      }
      ''';

      final msg = PcpCodec.decodeMessage(remoteStatusJson);
      expect(msg, isA<RemoteStatusChangedEvent>());
      final evt = msg as RemoteStatusChangedEvent;
      expect(evt.status['enabled'], true);
      expect(evt.status['state'], 'running');
    });

    test('creates systemMetricsSubscribe and systemMetricsUnsubscribe commands', () {
      final sub = PcpCommand.systemMetricsSubscribe(commandId: 'cmd_sub_01');
      expect(sub.commandId, 'cmd_sub_01');
      expect(sub.sessionId, '@daemon');
      expect(sub.type, 'system.metrics.subscribe');
      expect(sub.payload, isEmpty);

      final unsub = PcpCommand.systemMetricsUnsubscribe(commandId: 'cmd_unsub_01');
      expect(unsub.commandId, 'cmd_unsub_01');
      expect(unsub.sessionId, '@daemon');
      expect(unsub.type, 'system.metrics.unsubscribe');
      expect(unsub.payload, isEmpty);
    });
  });
}
