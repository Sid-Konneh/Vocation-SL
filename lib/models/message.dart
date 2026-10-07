/// One message in the conversation on an application.
class AppMessage {
  const AppMessage({
    required this.id,
    required this.applicationId,
    required this.fromEmployer,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String applicationId;
  final bool fromEmployer;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  factory AppMessage.fromJson(Map<String, dynamic> j) => AppMessage(
        id: '${j['id']}',
        applicationId: j['application_id'] as String,
        fromEmployer: j['sender_role'] == 'employer',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.parse('${j['created_at']}'),
        readAt: j['read_at'] == null ? null : DateTime.tryParse('${j['read_at']}'),
      );
}
