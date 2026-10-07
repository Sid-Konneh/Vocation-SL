import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend/message_backend.dart';
import '../models/models.dart';
import 'session_providers.dart';

/// Overridden in main.dart with the Supabase version when live.
final messageBackendProvider = Provider<MessageBackend>((ref) => DemoMessageBackend());

/// The conversation on one application.
final messageThreadProvider = FutureProvider.autoDispose.family<List<AppMessage>, String>((ref, applicationId) {
  ref.watch(sessionProvider);
  return ref.watch(messageBackendProvider).thread(applicationId);
});

/// Unread candidate replies per application, for the employer's candidate list.
final unreadRepliesProvider = FutureProvider.autoDispose<Map<String, int>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(messageBackendProvider).unreadReplies();
});
