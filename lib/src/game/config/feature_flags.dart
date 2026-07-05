/// Compile-time feature flags for the app.
///
/// The Online tab is transport-only scaffolding (see
/// `backgammon_online_panel.dart`) and is hidden by default so players don't
/// hit a dead feature. Re-enable it without a code change via:
///   flutter build web --dart-define=ONLINE_TAB_ENABLED=true
const bool kOnlineTabEnabled = bool.fromEnvironment(
  'ONLINE_TAB_ENABLED',
  defaultValue: false,
);
