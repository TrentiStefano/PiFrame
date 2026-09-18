const fs = require('fs');
const path = require('path');

const adrDir = path.resolve(__dirname, '../../docs/adr');
if (!fs.existsSync(adrDir)) {
  console.error('docs/adr directory does not exist');
  process.exit(1);
}

const files = fs.readdirSync(adrDir).filter(f => f.endsWith('.md'));
console.log(`Found ${files.length} ADRs in docs/adr`);

if (files.length !== 17) {
  console.error(`Expected exactly 17 ADRs, found ${files.length}`);
  process.exit(1);
}

const validStatuses = ['Accepted', 'Proposed', 'Superseded'];

for (const file of files) {
  const content = fs.readFileSync(path.join(adrDir, file), 'utf8');
  const statusMatch = content.match(/- \*\*Status:\*\*\s*(\w+)/);
  if (!statusMatch) {
    console.error(`ADR ${file} is missing - **Status:** field`);
    process.exit(1);
  }
  const status = statusMatch[1];
  if (!validStatuses.includes(status)) {
    console.error(`ADR ${file} has invalid status: ${status}`);
    process.exit(1);
  }
  if (status !== 'Accepted') {
    console.error(`ADR ${file} status should be Accepted, found ${status}`);
    process.exit(1);
  }
}

console.log('All 17 ADRs validated successfully with status: Accepted.');
