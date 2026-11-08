import test from 'node:test';
import * as assert from 'node:assert/strict';
import {
  parseNvidiaSmiLine,
  aggregateNvidiaSmiSamples,
  parseNvidiaSmiOutput
} from '../parsers/nvidiaSmiParser.js';
import {
  splitCsvLine,
  parseTypeperfHeader,
  parseTypeperfRow,
  isTypeperfHeaderLine
} from '../parsers/typeperfParser.js';
import { parseIoregOutput } from '../parsers/ioregParser.js';
import { parseSysfsCard, aggregateSysfsCards } from '../parsers/sysfsParser.js';

test('nvidiaSmiParser: parse single line with valid values', () => {
  const line = '24.5, 2048, 8192';
  const parsed = parseNvidiaSmiLine(line);
  assert.ok(parsed);
  assert.equal(parsed?.utilization, 24.5);
  assert.equal(parsed?.memoryUsedBytes, 2048 * 1024 * 1024);
  assert.equal(parsed?.memoryTotalBytes, 8192 * 1024 * 1024);
});

test('nvidiaSmiParser: parses line with spaces and handles non-numeric / unsupported gracefully', () => {
  const line1 = '   100, 1024, 4096   ';
  const p1 = parseNvidiaSmiLine(line1);
  assert.equal(p1?.utilization, 100);
  assert.equal(p1?.memoryUsedBytes, 1024 * 1024 * 1024);

  const line2 = '[Not Supported], N/A, 8192';
  const p2 = parseNvidiaSmiLine(line2);
  assert.ok(p2);
  assert.equal(p2?.utilization, null);
  assert.equal(p2?.memoryUsedBytes, null);
  assert.equal(p2?.memoryTotalBytes, 8192 * 1024 * 1024);

  const line3 = '';
  assert.equal(parseNvidiaSmiLine(line3), null);
});

test('nvidiaSmiParser: aggregates multiple GPUs taking max utilization and sum memory', () => {
  const output = `
    12.4, 1000, 8000
    45.8, 2000, 8000
    30.1, 1500, 8000
  `;
  const result = parseNvidiaSmiOutput(output);
  assert.equal(result.source, 'nvidia-smi');
  assert.equal(result.percent, 45.8);
  assert.equal(result.memoryUsedBytes, (1000 + 2000 + 1500) * 1024 * 1024);
  assert.equal(result.memoryTotalBytes, (8000 + 8000 + 8000) * 1024 * 1024);
});

test('typeperfParser: splitCsvLine handles quoted and unquoted columns', () => {
  const line = '"(PDH-CSV 4.0) (UTC)(0)","\\\\HOST\\GPU Engine(pid_1_luid_0x0001_phys_0_eng_0)\\Utilization","0.000000"';
  const cols = splitCsvLine(line);
  assert.equal(cols.length, 3);
  assert.equal(cols[0], '(PDH-CSV 4.0) (UTC)(0)');
  assert.ok(cols[1].includes('GPU Engine'));
  assert.equal(cols[2], '0.000000');
});

test('typeperfParser: parses header and aggregates data across pids for same (luid, phys, eng)', () => {
  const header =
    '"(PDH-CSV 4.0) (UTC)(0)",' +
    '"\\\\PC\\GPU Engine(pid_100_luid_0x00000000_0x0000E528_phys_0_eng_0_engtype_3D)\\Utilization Percentage",' +
    '"\\\\PC\\GPU Engine(pid_200_luid_0x00000000_0x0000E528_phys_0_eng_0_engtype_3D)\\Utilization Percentage",' +
    '"\\\\PC\\GPU Engine(pid_300_luid_0x00000000_0x0000E528_phys_0_eng_1_engtype_Copy)\\Utilization Percentage"';

  assert.equal(isTypeperfHeaderLine(header), true);
  const mappings = parseTypeperfHeader(header);
  assert.equal(mappings.length, 3);
  assert.equal(mappings[0].engineKey, '0x00000000_0x0000E528_phys_0_eng_0');
  assert.equal(mappings[1].engineKey, '0x00000000_0x0000E528_phys_0_eng_0');
  assert.equal(mappings[2].engineKey, '0x00000000_0x0000E528_phys_0_eng_1');

  // eng_0 has pid_100 (15.5%) + pid_200 (10.2%) = 25.7%
  // eng_1 has pid_300 (18.1%)
  // Max engine is eng_0 = 25.7%
  const row = '"11/05/2026 12:00:00.000","15.500000","10.200000","18.100000"';
  const util = parseTypeperfRow(row, mappings);
  assert.equal(util, 25.7);
});

test('typeperfParser: clamps max engine to 100% and rounds to 1 decimal', () => {
  const header =
    '"(PDH-CSV 4.0)",' +
    '"\\\\PC\\GPU Engine(pid_100_luid_0x1_phys_0_eng_0)\\Utilization",' +
    '"\\\\PC\\GPU Engine(pid_200_luid_0x1_phys_0_eng_0)\\Utilization"';
  const mappings = parseTypeperfHeader(header);
  const row = '"11/05/2026 12:00:00.000","80.3456","45.1234"'; // sum > 100
  const util = parseTypeperfRow(row, mappings);
  assert.equal(util, 100.0);
});

test('ioregParser: parses macOS IOAccelerator device utilization and system memory', () => {
  const ioregOutput = `
    +-o AGXAccelerator  <class AGXAccelerator, id 0x1000003b5, registered, matched, active, busy 0 (0 ms), retain 114>
      {
        "IOClass" = "AGXAccelerator"
        "PerformanceStatistics" = {"Device Utilization %"=38,"In use system memory"=2147483648,"sample interval"=1000000}
      }
  `;
  const result = parseIoregOutput(ioregOutput);
  assert.equal(result.source, 'ioreg');
  assert.equal(result.percent, 38.0);
  assert.equal(result.memoryUsedBytes, 2147483648);
  assert.equal(result.memoryTotalBytes, null);
});

test('ioregParser: aggregates multiple IOAccelerators by max utilization and sum memory', () => {
  const multiIoregOutput = `
    +-o IntegratedGPU
      {"Device Utilization %" = 10, "In use system memory" = 1073741824}
    +-o DiscreteGPU
      {"Device Utilization %" = 55, "In use system memory" = 3221225472}
  `;
  const result = parseIoregOutput(multiIoregOutput);
  assert.equal(result.percent, 55.0);
  assert.equal(result.memoryUsedBytes, 1073741824 + 3221225472);
});

test('ioregParser: returns nulls for empty or unrelated output', () => {
  const result = parseIoregOutput('No IOAccelerator found');
  assert.equal(result.percent, null);
  assert.equal(result.memoryUsedBytes, null);
  assert.equal(result.source, 'ioreg');
});

test('sysfsParser: parse individual card files and aggregate multiple cards', () => {
  const card1 = parseSysfsCard('42\n', '1073741824\n', '8589934592\n');
  assert.equal(card1.percent, 42.0);
  assert.equal(card1.memoryUsedBytes, 1073741824);
  assert.equal(card1.memoryTotalBytes, 8589934592);

  const card2 = parseSysfsCard('78\n', '2147483648\n', '8589934592\n');
  assert.equal(card2.percent, 78.0);

  const agg = aggregateSysfsCards([card1, card2]);
  assert.equal(agg.source, 'sysfs');
  assert.equal(agg.percent, 78.0); // max of 42 and 78
  assert.equal(agg.memoryUsedBytes, 1073741824 + 2147483648);
  assert.equal(agg.memoryTotalBytes, 8589934592 + 8589934592);
});

test('sysfsParser: handles empty or invalid card list', () => {
  const agg = aggregateSysfsCards([]);
  assert.equal(agg.percent, null);
  assert.equal(agg.memoryUsedBytes, null);
  assert.equal(agg.memoryTotalBytes, null);
  assert.equal(agg.source, 'sysfs');
});
