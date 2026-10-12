const piCrustVersionDefault = '1.1.0'; // x-release-please-version

const piCrustVersion = String.fromEnvironment(
  'PI_CRUST_VERSION',
  defaultValue: piCrustVersionDefault,
);
