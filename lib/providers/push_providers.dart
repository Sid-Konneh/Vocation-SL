import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push_service.dart';
import 'session_providers.dart';

/// Null when push alerts aren't set up (demo mode, or Firebase not configured).
final pushServiceProvider = Provider<PushService?>((ref) => null);

/// Whether this device shows alerts when the app is closed.
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>((ref) async {
  ref.watch(sessionProvider);
  final push = ref.watch(pushServiceProvider);
  if (push == null) return PushPermission.unsupported;
  return push.permission();
});
