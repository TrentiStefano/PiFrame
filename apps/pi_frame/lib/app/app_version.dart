const piFrameVersionDefault = '1.0.0'; // x-release-please-version

const piFrameVersion = String.fromEnvironment(
  'PI_FRAME_VERSION',
  defaultValue: piFrameVersionDefault,
);
