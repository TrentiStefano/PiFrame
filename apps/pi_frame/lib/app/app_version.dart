const piFrameVersionDefault = '1.2.0'; // x-release-please-version

const piFrameVersion = String.fromEnvironment(
  'PI_FRAME_VERSION',
  defaultValue: piFrameVersionDefault,
);
