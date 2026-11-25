import test from 'node:test';
import * as assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import type { ExecFileOptions } from 'node:child_process';
import { WindowsTypeperfGpuProvider } from '../gpu/WindowsTypeperfGpuProvider.js';
import { NvidiaGpuProvider } from '../gpu/NvidiaGpuProvider.js';
import { MacIoregGpuProvider } from '../gpu/MacIoregGpuProvider.js';
import { asChild, execFileDouble, spawnDouble } from './fakes.js';

class FakeChildProcess extends EventEmitter {
  public stdout: EventEmitter & { setEncoding: (encoding: string) => void } = Object.assign(new EventEmitter(), {
    setEncoding: () => {}
  });
  public killed = false;
  public killCallCount = 0;

  constructor(private readonly onKill?: (child: FakeChildProcess) => void) {
    super();
  }

  public kill(): boolean {
    this.killed = true;
    this.killCallCount++;
    if (this.onKill) {
      this.onKill(this);
    }
    return true;
  }
}

test('WindowsTypeperfGpuProvider: child emitting exit(1) after stop/kill does not respawn', async () => {
  let spawnCount = 0;
  const spawnedChildren: FakeChildProcess[] = [];

  const fakeSpawn = () => {
    spawnCount++;
    const fakeChild = new FakeChildProcess((child) => {
      // Real typeperf exits with code 1 after kill()
      queueMicrotask(() => {
        child.emit('exit', 1);
      });
    });
    spawnedChildren.push(fakeChild);
    return asChild(fakeChild);
  };

  const provider = new WindowsTypeperfGpuProvider(spawnDouble(fakeSpawn));
  provider.start();
  assert.equal(spawnCount, 1);

  provider.stop();
  assert.equal(spawnedChildren[0]!.killCallCount, 1);

  // Wait for microtasks / events to settle
  await new Promise<void>((resolve) => setTimeout(resolve, 50));

  assert.equal(spawnCount, 1, 'typeperf must not be respawned after stop()');
});

test('NvidiaGpuProvider: stdout data and exit after stop() are ignored and do not update samples', () => {
  let spawnCount = 0;
  let activeChild: FakeChildProcess | undefined;

  const fakeSpawn = () => {
    spawnCount++;
    activeChild = new FakeChildProcess();
    return asChild(activeChild);
  };

  const provider = new NvidiaGpuProvider(spawnDouble(fakeSpawn));
  provider.start();
  assert.equal(spawnCount, 1);

  provider.stop();
  assert.equal(activeChild!.killCallCount, 1);

  // Late stdout data and exit after stop()
  activeChild!.stdout.emit('data', '75, 4000, 8000\n');
  activeChild!.emit('exit', 0);

  const sample = provider.getSample();
  assert.equal(sample.percent, null);
  assert.equal(sample.memoryUsedBytes, null);
  assert.equal(sample.memoryTotalBytes, null);
});

test('MacIoregGpuProvider: in-flight execFile resolving after stop() does not update sample and uses windowsHide', async () => {
  let execCount = 0;
  let execCallback: ((error: Error | null, stdout: string, stderr: string) => void) | undefined;
  let passedOptions: ExecFileOptions | undefined;

  const fakeExecFile = (
    _file: string,
    _args: readonly string[],
    options: ExecFileOptions,
    cb: (error: Error | null, stdout: string, stderr: string) => void
  ) => {
    execCount++;
    passedOptions = options;
    execCallback = cb;
    return new FakeChildProcess();
  };

  const provider = new MacIoregGpuProvider(execFileDouble(fakeExecFile));
  provider.start();

  const samplePromise = provider.getSample();
  assert.equal(execCount, 1);
  assert.equal(passedOptions?.windowsHide, true, 'windowsHide must be true in execFile options');

  // stop() while execFile is in flight
  provider.stop();

  // Late ioreg output resolving after stop()
  const sampleOutput = `
+-o IOAccelerator  <class IOAccelerator, id 0x10000021b, registered, matched, active, busy 0 (0 ms), retain 40>
| {
|   "PerformanceStatistics" = {"Device Utilization %"=42}
| }
`;
  execCallback!(null, sampleOutput, '');

  const sampleFromPromise = await samplePromise;
  assert.equal(sampleFromPromise.percent, null);

  const latestSample = await provider.getSample();
  assert.equal(latestSample.percent, null);
});
