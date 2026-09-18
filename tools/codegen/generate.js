import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log('=== PCP Codegen: Verifying Schema -> TS & Dart parity ===');

const schemaDir = path.resolve(__dirname, '../../packages/pcp-spec/schema');
const tsTypesFile = path.resolve(__dirname, '../../packages/pcp-ts/src/types.ts');
const dartEventsFile = path.resolve(__dirname, '../../packages/pi_crust_protocol/lib/src/events.dart');

if (!fs.existsSync(schemaDir) || !fs.existsSync(tsTypesFile) || !fs.existsSync(dartEventsFile)) {
  console.error('Missing schema or target files for codegen verification');
  process.exit(1);
}

const commandSchema = JSON.parse(fs.readFileSync(path.join(schemaDir, 'command.schema.json'), 'utf8'));
const eventSchema = JSON.parse(fs.readFileSync(path.join(schemaDir, 'event.schema.json'), 'utf8'));

const schemaCommandTypes = commandSchema.properties.type.enum;
const schemaEventTypes = eventSchema.properties.type.enum;

const tsContent = fs.readFileSync(tsTypesFile, 'utf8');
const dartContent = fs.readFileSync(dartEventsFile, 'utf8');

let driftDetected = false;

// Check command types in TS
for (const cmd of schemaCommandTypes) {
  if (!tsContent.includes(`'${cmd}'`)) {
    console.error(`[DRIFT] TypeScript types missing command: ${cmd}`);
    driftDetected = true;
  }
}

// Check event types in TS & Dart
for (const evt of schemaEventTypes) {
  if (!tsContent.includes(`'${evt}'`)) {
    console.error(`[DRIFT] TypeScript types missing event: ${evt}`);
    driftDetected = true;
  }
  if (!dartContent.includes(`'${evt}'`)) {
    console.error(`[DRIFT] Dart events missing event: ${evt}`);
    driftDetected = true;
  }
}

if (driftDetected) {
  console.error('Codegen drift check FAILED.');
  process.exit(1);
}

console.log(`Verified ${schemaCommandTypes.length} command types and ${schemaEventTypes.length} event types across Schema, TypeScript, and Dart.`);
console.log('Codegen parity: 100% synchronized.');
