import test from 'node:test';
import * as assert from 'node:assert/strict';
import { SystemMetricsService } from '../SystemMetricsService.js';
import type { GpuMetricsProvider, GpuSample } from '../types.js';

class MockGpuProvider implements GpuMetricsProvider {
  public source = 'nvidia-smi' as const;
  public startCalls = 0;
  public stopCalls = 0;
  public getSampleCalls = 0;
  public sampleToReturn: GpuSample = {
    percent: 30.5,
    memoryUsedBytes: 1000,
    memoryTotalBytes: 4000,
    source: 'nvidia-smi'
  };

  public start(): void {
    this.startCalls++;
  }

  public stop(): void {
    this.stopCalls++;
  }

  public getSample(): GpuSample {
    this.getSampleCalls++;
    return this.sampleToReturn;
  }
}

class MockConnection {
  public id: string;
  public sentMessages: any[] = [];

  constructor(id: string) {
    this.id = id;
  }

  public send(msg: any): void {
    this.sentMessages.push(msg);
  }
}

test('SystemMetricsService: with zero subscribers, no timers, no samplers, no GPU process started', () => {
  let setIntervalCalled = 0;
  let clearIntervalCalled = 0;
  let cpuSampleCalls = 0;
  let memorySampleCalls = 0;
  let diskSampleCalls = 0;

  const gpu = new MockGpuProvider();

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => {
        setIntervalCalled++;
        return 1 as any;
      },
      clearInterval: () => {
        clearIntervalCalled++;
      }
    },
    gpuProvider: gpu,
    sampleCpu: () => {
      cpuSampleCalls++;
      return { percent: 10.0 };
    },
    sampleMemory: () => {
      memorySampleCalls++;
      return { usedBytes: 100, totalBytes: 200, percent: 50.0 };
    },
    sampleDisk: () => {
      diskSampleCalls++;
      return { usedBytes: 500, totalBytes: 1000, percent: 50.0 };
    }
  });

  assert.equal(service.getSubscriberCount(), 0);
  assert.equal(service.isSampling(), false);
  assert.equal(setIntervalCalled, 0);
  assert.equal(cpuSampleCalls, 0);
  assert.equal(memorySampleCalls, 0);
  assert.equal(diskSampleCalls, 0);
  assert.equal(gpu.startCalls, 0);
  assert.equal(gpu.getSampleCalls, 0);
});

test('SystemMetricsService: lifecycle on subscribe, tick, and unsubscribe', async () => {
  let timerFn: (() => void) | undefined;
  let clearedTimer: any;
  const gpu = new MockGpuProvider();

  let cpuCallCount = 0;

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: (fn) => {
        timerFn = fn;
        return 42 as any;
      },
      clearInterval: (t) => {
        clearedTimer = t;
      }
    },
    gpuProvider: gpu,
    sampleCpu: () => {
      cpuCallCount++;
      // First tick null, second tick 25.5
      return cpuCallCount === 1 ? null : { percent: 25.5 };
    },
    sampleMemory: () => ({ usedBytes: 4000, totalBytes: 8000, percent: 50.0 }),
    sampleDisk: () => ({ usedBytes: 10000, totalBytes: 50000, percent: 20.0 })
  });

  const conn1 = new MockConnection('c_sub_1');
  const conn2 = new MockConnection('c_sub_2');
  const nonSubConn = new MockConnection('c_other');

  // 1. Subscribe conn1
  const subResult = await service.subscribe(conn1 as any);
  assert.equal(subResult.intervalMs, 1000);
  assert.equal(service.getSubscriberCount(), 1);
  assert.equal(service.isSampling(), true);
  assert.equal(gpu.startCalls, 1);
  assert.ok(timerFn !== undefined);

  // 2. First tick
  await service.tick();
  assert.equal(conn1.sentMessages.length, 1);
  assert.equal(nonSubConn.sentMessages.length, 0);

  const event1 = conn1.sentMessages[0];
  assert.equal(event1.kind, 'event');
  assert.equal(event1.type, 'system.metrics');
  assert.equal(event1.sessionId, '@daemon');
  assert.equal(event1.seq, 0);
  assert.equal(event1.payload.cpu, null); // first tick null
  assert.equal(event1.payload.memory.percent, 50.0);
  assert.equal(event1.payload.disk.percent, 20.0);
  assert.equal(event1.payload.gpu.percent, 30.5);

  // 3. Subscribe conn2 (second subscriber)
  await service.subscribe(conn2 as any);
  assert.equal(service.getSubscriberCount(), 2);
  assert.equal(gpu.startCalls, 1); // Not restarted

  // 4. Second tick -> both conn1 and conn2 receive event
  await service.tick();
  assert.equal(conn1.sentMessages.length, 2);
  assert.equal(conn2.sentMessages.length, 1);
  assert.equal(nonSubConn.sentMessages.length, 0);

  const event2 = conn2.sentMessages[0];
  assert.equal(event2.payload.cpu.percent, 25.5);

  // 5. Unsubscribe conn1
  service.unsubscribe(conn1.id);
  assert.equal(service.getSubscriberCount(), 1);
  assert.equal(service.isSampling(), true);
  assert.equal(gpu.stopCalls, 0);

  // 6. Unsubscribe conn2 -> zero subscribers
  service.unsubscribe(conn2.id);
  assert.equal(service.getSubscriberCount(), 0);
  assert.equal(service.isSampling(), false);
  assert.equal(gpu.stopCalls, 1);
  assert.equal(clearedTimer, 42);
});

test('SystemMetricsService: connection close hook stops sampling on last subscriber', async () => {
  let cleared = false;
  const gpu = new MockGpuProvider();

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => 10 as any,
      clearInterval: () => {
        cleared = true;
      }
    },
    gpuProvider: gpu,
    sampleCpu: () => ({ percent: 5.0 }),
    sampleMemory: () => null,
    sampleDisk: () => null
  });

  const conn = new MockConnection('c_will_close');
  await service.subscribe(conn as any);
  assert.equal(service.getSubscriberCount(), 1);
  assert.equal(service.isSampling(), true);

  // Simulating connection drop
  service.handleConnectionClose(conn.id);
  assert.equal(service.getSubscriberCount(), 0);
  assert.equal(service.isSampling(), false);
  assert.equal(cleared, true);
  assert.equal(gpu.stopCalls, 1);
});

test('SystemMetricsService: idempotency on repeated subscribe / unsubscribe', async () => {
  const gpu = new MockGpuProvider();
  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => 99 as any,
      clearInterval: () => {}
    },
    gpuProvider: gpu
  });

  const conn = new MockConnection('c_repeat');
  await service.subscribe(conn as any);
  await service.subscribe(conn as any);
  assert.equal(service.getSubscriberCount(), 1);
  assert.equal(gpu.startCalls, 1);

  service.unsubscribe(conn.id);
  service.unsubscribe(conn.id); // idempotent
  assert.equal(service.getSubscriberCount(), 0);
  assert.equal(gpu.stopCalls, 1);
});

test('SystemMetricsService: deferred getProvider resolving after unsubscribe does not start provider or timer', async () => {
  let timerStarted = false;
  const mockGpu = new MockGpuProvider();

  let resolveProvider!: (p: GpuMetricsProvider) => void;
  const deferredProviderPromise = new Promise<GpuMetricsProvider>((resolve) => {
    resolveProvider = resolve;
  });

  const fakeGpuFactory = {
    getProvider: async () => deferredProviderPromise
  } as any;

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => {
        timerStarted = true;
        return 123 as any;
      },
      clearInterval: () => {}
    },
    gpuFactory: fakeGpuFactory
  });

  const conn = new MockConnection('c_race');
  const subPromise = service.subscribe(conn as any);

  // While getProvider is awaiting in-flight, unsubscribe the connection
  service.unsubscribe(conn.id);
  assert.equal(service.getSubscriberCount(), 0);

  // Now resolve getProvider
  resolveProvider(mockGpu);
  await subPromise;

  assert.equal(mockGpu.startCalls, 0, 'GPU provider must not be started with 0 subscribers');
  assert.equal(timerStarted, false, 'Sampling timer must not be started with 0 subscribers');
  assert.equal(service.isSampling(), false);
});

test('SystemMetricsService: service.stop() during startup is honored', async () => {
  let timerStarted = false;
  const mockGpu = new MockGpuProvider();

  let resolveProvider!: (p: GpuMetricsProvider) => void;
  const deferredProviderPromise = new Promise<GpuMetricsProvider>((resolve) => {
    resolveProvider = resolve;
  });

  const fakeGpuFactory = {
    getProvider: async () => deferredProviderPromise
  } as any;

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => {
        timerStarted = true;
        return 123 as any;
      },
      clearInterval: () => {}
    },
    gpuFactory: fakeGpuFactory
  });

  const conn = new MockConnection('c_stop');
  const subPromise = service.subscribe(conn as any);

  // stop() called during startup
  service.stop();
  assert.equal(service.getSubscriberCount(), 0);

  resolveProvider(mockGpu);
  await subPromise;

  assert.equal(mockGpu.startCalls, 0, 'GPU provider must not be started after stop()');
  assert.equal(timerStarted, false, 'Sampling timer must not be started after stop()');
  assert.equal(service.isSampling(), false);
});

test('SystemMetricsService: concurrent subscribes share single start promise and do not overlap', async () => {
  let timerStartCount = 0;
  const mockGpu = new MockGpuProvider();

  let resolveProvider!: (p: GpuMetricsProvider) => void;
  const deferredProviderPromise = new Promise<GpuMetricsProvider>((resolve) => {
    resolveProvider = resolve;
  });

  let getProviderCallCount = 0;
  const fakeGpuFactory = {
    getProvider: async () => {
      getProviderCallCount++;
      return deferredProviderPromise;
    }
  } as any;

  const service = new SystemMetricsService({
    timerProvider: {
      setInterval: () => {
        timerStartCount++;
        return 123 as any;
      },
      clearInterval: () => {}
    },
    gpuFactory: fakeGpuFactory
  });

  const conn1 = new MockConnection('c_conc_1');
  const conn2 = new MockConnection('c_conc_2');

  const p1 = service.subscribe(conn1 as any);
  const p2 = service.subscribe(conn2 as any);

  assert.equal(service.getSubscriberCount(), 2);
  assert.equal(getProviderCallCount, 1);

  resolveProvider(mockGpu);
  await Promise.all([p1, p2]);

  assert.equal(mockGpu.startCalls, 1, 'Provider start must only be called once');
  assert.equal(timerStartCount, 1, 'Timer must only be created once');
  assert.equal(service.isSampling(), true);

  service.unsubscribe(conn1.id);
  assert.equal(service.isSampling(), true);
  assert.equal(mockGpu.stopCalls, 0);

  service.unsubscribe(conn2.id);
  assert.equal(service.isSampling(), false);
  assert.equal(mockGpu.stopCalls, 1);
});


