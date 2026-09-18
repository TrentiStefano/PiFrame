const fs = require('fs');
const path = require('path');
const Ajv2020 = require('ajv/dist/2020');
const addFormats = require('ajv-formats');

const ajv = new Ajv2020({ strict: true, allErrors: true });
addFormats(ajv);

const schemaDir = path.resolve(__dirname, '../schema');
const fixturesDir = path.resolve(__dirname, '../fixtures/pcp');

const schemaFiles = fs.readdirSync(schemaDir).filter(f => f.endsWith('.schema.json'));
const validators = {};

for (const sf of schemaFiles) {
  const schema = JSON.parse(fs.readFileSync(path.join(schemaDir, sf), 'utf8'));
  const kind = sf.replace('.schema.json', '');
  validators[kind] = ajv.compile(schema);
  console.log(`Compiled schema for kind: ${kind}`);
}

const fixtureFiles = fs.readdirSync(fixturesDir).filter(f => f.endsWith('.json'));
let passed = 0;
let failed = 0;

for (const ff of fixtureFiles) {
  const fullPath = path.join(fixturesDir, ff);
  const data = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
  const isInvalidFixture = ff.includes('.invalid.');
  const kind = ff.split('.')[0];

  const validate = validators[kind] || validators.envelope;
  if (!validate) {
    console.error(`No validator found for fixture: ${ff}`);
    failed++;
    continue;
  }

  const valid = validate(data);

  if (isInvalidFixture) {
    if (valid) {
      console.error(`[FAIL] Expected ${ff} to be INVALID, but schema passed!`);
      failed++;
    } else {
      console.log(`[PASS] ${ff} correctly failed validation as expected.`);
      passed++;
    }
  } else {
    if (!valid) {
      console.error(`[FAIL] Expected ${ff} to be VALID, but failed:`, validate.errors);
      failed++;
    } else {
      console.log(`[PASS] ${ff} passed validation.`);
      passed++;
    }
  }
}

console.log(`\nValidation complete: ${passed} passed, ${failed} failed.`);
if (failed > 0) {
  process.exit(1);
}
