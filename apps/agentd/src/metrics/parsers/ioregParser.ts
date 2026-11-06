export function parseIoregOutput(output: string): {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: 'ioreg';
} {
  if (!output || typeof output !== 'string') {
    return { percent: null, memoryUsedBytes: null, memoryTotalBytes: null, source: 'ioreg' };
  }

  const utilRegex = /"Device Utilization %"\s*=\s*(\d+)/g;
  const memRegex = /"In use system memory"\s*=\s*(\d+)/g;

  const utilizations: number[] = [];
  let match: RegExpExecArray | null;
  while ((match = utilRegex.exec(output)) !== null) {
    const val = parseInt(match[1], 10);
    if (!isNaN(val) && val >= 0) {
      utilizations.push(Math.min(100, Math.max(0, val)));
    }
  }

  const memories: number[] = [];
  while ((match = memRegex.exec(output)) !== null) {
    const val = parseInt(match[1], 10);
    if (!isNaN(val) && val >= 0) {
      memories.push(val);
    }
  }

  const percent =
    utilizations.length > 0
      ? Math.round(Math.max(...utilizations) * 10) / 10
      : null;

  const memoryUsedBytes =
    memories.length > 0
      ? memories.reduce((a, b) => a + b, 0)
      : null;

  return {
    percent,
    memoryUsedBytes,
    memoryTotalBytes: null,
    source: 'ioreg'
  };
}
