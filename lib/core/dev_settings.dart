import 'storage/local_store.dart';

/// Switches for testing network conditions on a real device or in the browser.
class DevSettings {
  const DevSettings({this.simulateOffline = false, this.slowNetwork = false, this.failRequests = false});

  final bool simulateOffline;
  final bool slowNetwork;

  /// Makes roughly half of backend calls fail with a server error.
  final bool failRequests;

  DevSettings copyWith({bool? simulateOffline, bool? slowNetwork, bool? failRequests}) => DevSettings(
        simulateOffline: simulateOffline ?? this.simulateOffline,
        slowNetwork: slowNetwork ?? this.slowNetwork,
        failRequests: failRequests ?? this.failRequests,
      );

  static DevSettings load(LocalStore store) {
    final m = store.setting<Map<String, dynamic>>('dev') ?? const {};
    return DevSettings(
      simulateOffline: m['offline'] as bool? ?? false,
      slowNetwork: m['slow'] as bool? ?? false,
      failRequests: m['fail'] as bool? ?? false,
    );
  }

  Future<void> save(LocalStore store) =>
      store.setSetting('dev', {'offline': simulateOffline, 'slow': slowNetwork, 'fail': failRequests});
}
