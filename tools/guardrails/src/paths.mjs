/**
 * Path and file-kind helpers shared by the guardrail modules. Pure: no I/O.
 */

/** Repository paths are compared with `/` separators, whatever the OS gave us. */
export const toPosix = (path) => path.replaceAll('\\', '/');

/** The last segment of a `/`-separated path. */
export const basename = (path) => path.slice(path.lastIndexOf('/') + 1);

/** JavaScript and TypeScript source extensions, without the dot. */
export const SCRIPT_EXTENSIONS = ['ts', 'tsx', 'mts', 'cts', 'js', 'jsx', 'mjs', 'cjs'];

const anyOf = (extensions) => `(?:${extensions.join('|')})`;

/** A file name or path ending in one of the given extensions. */
const endsWith = (extensions) => new RegExp(`\\.${anyOf(extensions)}$`);

export const DART_FILE = endsWith(['dart']);
export const SCRIPT_FILE = endsWith(SCRIPT_EXTENSIONS);
/** Every file the escape-hatch audit reads: Dart plus JavaScript and TypeScript. */
export const SOURCE_FILE = endsWith(['dart', ...SCRIPT_EXTENSIONS]);
/** A test file by name: `*_test.dart`, or `*.test.*` / `*.spec.*` with a script extension. */
export const TEST_FILE_NAME = new RegExp(`(?:_test\\.dart|\\.(?:test|spec)\\.${anyOf(SCRIPT_EXTENSIONS)})$`);
