/// One message in the conversation on an application.
class AppMessage {
  const AppMessage({
    required this.id,
    required this.applicationId,
    required this.fromEmployer,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.attachmentPath,
    this.attachmentName,
  });

  final String id;
  final String applicationId;
  final bool fromEmployer;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// A PDF sent with the message (offer letter, contract, signed copy...).
  final String? attachmentPath;
  final String? attachmentName;

  bool get hasAttachment => (attachmentName ?? '').isNotEmpty;

  factory AppMessage.fromJson(Map<String, dynamic> j) => AppMessage(
        id: '${j['id']}',
        applicationId: j['application_id'] as String,
        fromEmployer: j['sender_role'] == 'employer',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.parse('${j['created_at']}'),
        readAt: j['read_at'] == null ? null : DateTime.tryParse('${j['read_at']}'),
        attachmentPath: j['attachment_path'] as String?,
        attachmentName: j['attachment_name'] as String?,
      );
}
