export interface TypeperfColumnMapping {
  colIndex: number;
  engineKey: string;
}

export function splitCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === ',' && !inQuotes) {
      result.push(current.trim().replace(/^"|"$/g, ''));
      current = '';
    } else {
      current += char;
    }
  }
  result.push(current.trim().replace(/^"|"$/g, ''));
  return result;
}

export function isTypeperfHeaderLine(line: string): boolean {
  const trimmed = line.trim();
  return (
    trimmed.startsWith('"(PDH-CSV') ||
    trimmed.includes('\\GPU Engine(') ||
    (trimmed.startsWith('"') && trimmed.includes('GPU Engine'))
  );
}

export function parseTypeperfHeader(headerLine: string): TypeperfColumnMapping[] {
  const cols = splitCsvLine(headerLine);
  const mappings: TypeperfColumnMapping[] = [];

  for (let i = 1; i < cols.length; i++) {
    const col = cols[i];
    const engineMatch = col.match(/GPU Engine\(([^)]+)\)/i);
    const instanceName = engineMatch ? engineMatch[1] : col;

    // Pattern: pid_.._luid_X_phys_N_eng_M_engtype_T
    const match = instanceName.match(/luid_([a-z0-9_]+?)_phys_(\d+)_eng_(\d+)/i);
    if (match) {
      const luid = match[1];
      const phys = match[2];
      const eng = match[3];
      const engineKey = `${luid}_phys_${phys}_eng_${eng}`;
      mappings.push({ colIndex: i, engineKey });
    }
  }

  return mappings;
}

export function parseTypeperfRow(
  rowLine: string,
  mappings: TypeperfColumnMapping[]
): number | null {
  const trimmed = rowLine.trim();
  if (!trimmed || mappings.length === 0) return null;
  const cols = splitCsvLine(trimmed);
  if (cols.length < 2) return null;

  const engineSums = new Map<string, number>();
  let hasValidNumber = false;

  for (const m of mappings) {
    if (m.colIndex < cols.length) {
      const val = parseFloat(cols[m.colIndex]);
      if (!isNaN(val) && isFinite(val)) {
        hasValidNumber = true;
        engineSums.set(m.engineKey, (engineSums.get(m.engineKey) || 0) + Math.max(0, val));
      }
    }
  }

  if (!hasValidNumber) return null;

  let maxEng = 0;
  for (const sum of engineSums.values()) {
    if (sum > maxEng) maxEng = sum;
  }

  return Math.min(100, Math.max(0, Math.round(maxEng * 10) / 10));
}
