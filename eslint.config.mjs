// The type-aware ESLint configuration for the TypeScript packages. Run by the diagnostics ratchet
// (tools/scripts/lint-typescript.mjs); the baseline holds today's counts per package and rule. Only the five rules
// below are enabled: they are the ones that find real bugs in async and type-narrowing code, so the rest of the
// recommended sets stay out of scope.
import * as fs from 'node:fs';
import tseslint from 'typescript-eslint';

// The TypeScript package folders, the same list the TypeScript analysis step runs tsc over.
const TYPESCRIPT_PACKAGES = JSON.parse(
  fs.readFileSync(new URL('./tools/scripts/typescript-projects.json', import.meta.url), 'utf8')
);

// node:test's test and describe run their callbacks and return promises the runner awaits, so a bare call is safe.
const NODE_TEST_SAFE_CALLS = [
  { from: 'package', name: ['test', 'describe'], package: 'node:test' }
];

export default tseslint.config({
  files: TYPESCRIPT_PACKAGES.map((dir) => `${dir}/src/**/*.ts`),
  languageOptions: {
    parser: tseslint.parser,
    parserOptions: {
      projectService: true,
      tsconfigRootDir: import.meta.dirname
    }
  },
  plugins: {
    '@typescript-eslint': tseslint.plugin
  },
  rules: {
    '@typescript-eslint/no-floating-promises': ['error', { allowForKnownSafeCalls: NODE_TEST_SAFE_CALLS }],
    '@typescript-eslint/no-misused-promises': 'error',
    '@typescript-eslint/await-thenable': 'error',
    '@typescript-eslint/switch-exhaustiveness-check': 'error',
    '@typescript-eslint/no-unnecessary-type-assertion': 'error'
  }
});
