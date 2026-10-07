import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks whether the app should treat itself as online.
///
/// Combines the device's connectivity with the developer "simulate offline"
/// switch so offline behaviour can be tested without turning off Wi-Fi.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _deviceOnline = true;
  bool _simulateOffline = false;

  bool get isOnline => _deviceOnline && !_simulateOffline;
  Stream<bool> get changes => _controller.stream;

  Future<void> init({bool simulateOffline = false}) async {
    _simulateOffline = simulateOffline;
    try {
      _deviceOnline = _hasNetwork(await _connectivity.checkConnectivity());
      _sub = _connectivity.onConnectivityChanged.listen((r) => _set(device: _hasNetwork(r)));
    } catch (_) {
      // Plugin unavailable (e.g. tests): assume online.
      _deviceOnline = true;
    }
  }

  set simulateOffline(bool value) => _set(simulated: value);

  void _set({bool? device, bool? simulated}) {
    final before = isOnline;
    if (device != null) _deviceOnline = device;
    if (simulated != null) _simulateOffline = simulated;
    if (before != isOnline) _controller.add(isOnline);
  }

  static bool _hasNetwork(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
