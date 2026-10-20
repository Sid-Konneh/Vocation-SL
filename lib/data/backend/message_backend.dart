import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../models/models.dart';
import 'supabase_backend.dart' show guardSupabase;

/// A PDF stored for sending in a message.
class MessageAttachment {
  const MessageAttachment({required this.path, required this.name});
  final String path;
  final String name;
}

/// A storage-safe version of a file name, always ending in .pdf.
String safePdfName(String fileName) {
  var base = fileName.trim();
  if (base.toLowerCase().endsWith('.pdf')) base = base.substring(0, base.length - 4);
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').replaceAll(RegExp(r'\s+'), '-');
  if (base.isEmpty) base = 'document';
  if (base.length > 80) base = base.substring(0, 80);
  return '$base.pdf';
}

/// Conversation between an employer and a candidate on one application.
/// Who is sending is decided by the database from the signed-in account;
/// [asEmployer] is only used by the demo backend.
abstract interface class MessageBackend {
  Future<List<AppMessage>> thread(String applicationId);

  /// Sends a message; [attachment] is a PDF already stored with [uploadAttachment].
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer, MessageAttachment? attachment});

  /// Stores a PDF in the sender's own folder, ready to send with a message
  /// (one upload can be sent to several applicants).
  Future<MessageAttachment> uploadAttachment(String fileName, Uint8List bytes);

  /// A short-lived link to open an attachment.
  Future<String> attachmentUrl(String storagePath);

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
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer, MessageAttachment? attachment}) => guardSupabase(() async {
        // sender_role is overwritten by the database; it is sent only to satisfy the column check.
        final row = await _client
            .from('application_messages')
            .insert({
              'application_id': applicationId,
              'body': body.trim().isEmpty && attachment != null ? 'Sent a document: ${attachment.name}' : body,
              'sender_role': asEmployer ? 'employer' : 'candidate',
              if (attachment != null) ...{'attachment_path': attachment.path, 'attachment_name': attachment.name},
            })
            .select()
            .single();
        return AppMessage.fromJson(row);
      });

  @override
  Future<MessageAttachment> uploadAttachment(String fileName, Uint8List bytes) => guardSupabase(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) throw const ValidationException('Sign in again to send files.');
        final name = safePdfName(fileName);
        final path = '$uid/messages/${DateTime.now().millisecondsSinceEpoch}-$name';
        await _client.storage.from('documents').uploadBinary(path, bytes, fileOptions: const sb.FileOptions(contentType: 'application/pdf'));
        return MessageAttachment(path: path, name: fileName.trim().isEmpty ? name : fileName.trim());
      });

  @override
  Future<String> attachmentUrl(String storagePath) =>
      guardSupabase(() => _client.storage.from('documents').createSignedUrl(storagePath, 60 * 30));

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
  Future<AppMessage> send(String applicationId, String body, {required bool asEmployer, MessageAttachment? attachment}) async {
    var text = body.trim();
    if (text.isEmpty && attachment != null) text = 'Sent a document: ${attachment.name}';
    if (text.isEmpty) throw const ValidationException('Write a message first.');
    final m = AppMessage(
      id: 'm-${++_seq}',
      applicationId: applicationId,
      fromEmployer: asEmployer,
      body: text,
      createdAt: DateTime.now(),
      attachmentPath: attachment?.path,
      attachmentName: attachment?.name,
    );
    _messages.add(m);
    return m;
  }

  @override
  Future<MessageAttachment> uploadAttachment(String fileName, Uint8List bytes) async =>
      // An empty path tells the viewer the file stayed on this device.
      MessageAttachment(path: '', name: fileName.trim().isEmpty ? 'document.pdf' : fileName.trim());

  @override
  Future<String> attachmentUrl(String storagePath) async =>
      throw const ValidationException('Files in demo mode stay on this device and can\'t be previewed.');

  @override
  Future<void> markRead(String applicationId) async {
    // Demo mode has one person playing both sides; nothing to track.
  }

  @override
  Future<Map<String, int>> unreadReplies() async => const {};
}
