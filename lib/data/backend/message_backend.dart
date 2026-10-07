import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../models/models.dart';
import 'supabase_backend.dart' show guardSupabase;

/// Conversation between an employer and a candidate on one application.
/// Who is sending is decided by the database from the signed-in account;
/// [asEmployer] is only used by the demo backend.
abstract interface class MessageBackend {
  Future<List<AppMessage>> thread(String applicationId);
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer});

  /// Marks the other side's messages as read.
  Future<void> markRead(String applicationId);

  /// Unread messages from candidates, per application (for employers).
  Future<Map<String, int>> unreadReplies();
}

class SupabaseMessageBackend implements MessageBackend {
  SupabaseMessageBackend(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<List<AppMessage>> thread(String applicationId) => guardSupabase(() async {
        final rows = await _client.from('application_messages').select().eq('application_id', applicationId).order('created_at');
        return rows.map(AppMessage.fromJson).toList();
      });

  @override
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer}) => guardSupabase(() async {
        // sender_role is overwritten by the database; it is sent only to satisfy the column check.
        final row = await _client
            .from('application_messages')
            .insert({'application_id': applicationId, 'body': body, 'sender_role': asEmployer ? 'employer' : 'candidate'})
            .select()
            .single();
        return AppMessage.fromJson(row);
      });

  @override
  Future<void> markRead(String applicationId) async {
    try {
      await _client.rpc('mark_messages_read', params: {'app_id': applicationId});
    } catch (_) {
      // Not critical.
    }
  }

  @override
  Future<Map<String, int>> unreadReplies() async {
    try {
      final rows = await _client.from('application_messages').select('application_id').eq('sender_role', 'candidate').isFilter('read_at', null);
      final m = <String, int>{};
      for (final r in rows) {
        final id = r['application_id'] as String;
        m[id] = (m[id] ?? 0) + 1;
      }
      return m;
    } catch (_) {
      return const {}; // messages table not installed yet
    }
  }
}

/// In-memory threads for demo mode and tests, shared by both sides.
/// (The reply-only rule is shown by the thread widget; the database enforces it live.)
class DemoMessageBackend implements MessageBackend {
  final _messages = <AppMessage>[];
  var _seq = 0;

  @override
  Future<List<AppMessage>> thread(String applicationId) async => _messages.where((m) => m.applicationId == applicationId).toList();

  @override
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer}) async {
    final text = body.trim();
    if (text.isEmpty) throw const ValidationException('Write a message first.');
    final m = AppMessage(id: 'm-${++_seq}', applicationId: applicationId, fromEmployer: asEmployer, body: text, createdAt: DateTime.now());
    _messages.add(m);
    return m;
  }

  @override
  Future<void> markRead(String applicationId) async {
    // Demo mode has one person playing both sides; nothing to track.
  }

  @override
  Future<Map<String, int>> unreadReplies() async => const {};
}
