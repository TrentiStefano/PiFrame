export interface RawNvidiaSample {
  utilization: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
}

export function parseNvidiaSmiLine(line: string): RawNvidiaSample | null {
  const trimmed = line.trim();
  if (!trimmed) return null;
  const parts = trimmed.split(',').map((p) => p.trim());
  if (parts.length < 3) return null;

  const utilNum = parseFloat(parts[0]);
  const utilization =
    !isNaN(utilNum) && isFinite(utilNum)
      ? Math.min(100, Math.max(0, Math.round(utilNum * 10) / 10))
      : null;

  const usedMb = parseFloat(parts[1]);
  const memoryUsedBytes =
    !isNaN(usedMb) && isFinite(usedMb) && usedMb >= 0
      ? Math.round(usedMb * 1024 * 1024)
      : null;

  const totalMb = parseFloat(parts[2]);
  const memoryTotalBytes =
    !isNaN(totalMb) && isFinite(totalMb) && totalMb >= 0
      ? Math.round(totalMb * 1024 * 1024)
      : null;

  return { utilization, memoryUsedBytes, memoryTotalBytes };
}

export function aggregateNvidiaSmiSamples(samples: RawNvidiaSample[]): {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: 'nvidia-smi';
} {
  if (samples.length === 0) {
    return {
      percent: null,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: 'nvidia-smi'
    };
  }

  const validPercents = samples
    .map((s) => s.utilization)
    .filter((p): p is number => p !== null);
  const maxPercent =
    validPercents.length > 0 ? Math.max(...validPercents) : null;

  const validUsed = samples
    .map((s) => s.memoryUsedBytes)
    .filter((b): b is number => b !== null);
  const sumUsed =
    validUsed.length > 0 ? validUsed.reduce((a, b) => a + b, 0) : null;

  const validTotal = samples
    .map((s) => s.memoryTotalBytes)
    .filter((b): b is number => b !== null);
  const sumTotal =
    validTotal.length > 0 ? validTotal.reduce((a, b) => a + b, 0) : null;

  return {
    percent: maxPercent !== null ? Math.round(maxPercent * 10) / 10 : null,
    memoryUsedBytes: sumUsed,
    memoryTotalBytes: sumTotal,
    source: 'nvidia-smi'
  };
}

export function parseNvidiaSmiOutput(output: string): {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: 'nvidia-smi';
} {
  const lines = output.split(/\r?\n/);
  const samples: RawNvidiaSample[] = [];
  for (const line of lines) {
    const parsed = parseNvidiaSmiLine(line);
    if (parsed) samples.push(parsed);
  }
  return aggregateNvidiaSmiSamples(samples);
}
