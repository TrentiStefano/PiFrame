export interface RawSysfsCard {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
}

export function parseSysfsCard(
  busyPercentStr?: string | null,
  vramUsedStr?: string | null,
  vramTotalStr?: string | null
): RawSysfsCard {
  let percent: number | null = null;
  if (busyPercentStr !== undefined && busyPercentStr !== null) {
    const val = parseFloat(busyPercentStr.trim());
    if (!isNaN(val) && isFinite(val) && val >= 0) {
      percent = Math.min(100, Math.max(0, Math.round(val * 10) / 10));
    }
  }

  let memoryUsedBytes: number | null = null;
  if (vramUsedStr !== undefined && vramUsedStr !== null) {
    const val = parseFloat(vramUsedStr.trim());
    if (!isNaN(val) && isFinite(val) && val >= 0) {
      memoryUsedBytes = Math.round(val);
    }
  }

  let memoryTotalBytes: number | null = null;
  if (vramTotalStr !== undefined && vramTotalStr !== null) {
    const val = parseFloat(vramTotalStr.trim());
    if (!isNaN(val) && isFinite(val) && val >= 0) {
      memoryTotalBytes = Math.round(val);
    }
  }

  return { percent, memoryUsedBytes, memoryTotalBytes };
}

export function aggregateSysfsCards(cards: RawSysfsCard[]): {
  percent: number | null;
  memoryUsedBytes: number | null;
  memoryTotalBytes: number | null;
  source: 'sysfs';
} {
  if (cards.length === 0) {
    return {
      percent: null,
      memoryUsedBytes: null,
      memoryTotalBytes: null,
      source: 'sysfs'
    };
  }

  const validPercents = cards
    .map((c) => c.percent)
    .filter((p): p is number => p !== null);
  const maxPercent =
    validPercents.length > 0 ? Math.max(...validPercents) : null;

  const validUsed = cards
    .map((c) => c.memoryUsedBytes)
    .filter((u): u is number => u !== null);
  const sumUsed =
    validUsed.length > 0 ? validUsed.reduce((a, b) => a + b, 0) : null;

  const validTotal = cards
    .map((c) => c.memoryTotalBytes)
    .filter((t): t is number => t !== null);
  const sumTotal =
    validTotal.length > 0 ? validTotal.reduce((a, b) => a + b, 0) : null;

  return {
    percent: maxPercent !== null ? Math.round(maxPercent * 10) / 10 : null,
    memoryUsedBytes: sumUsed,
    memoryTotalBytes: sumTotal,
    source: 'sysfs'
  };
}
