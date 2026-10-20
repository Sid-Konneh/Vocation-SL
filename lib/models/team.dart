/// A colleague with access to the company's jobs and candidates.
class TeamMember {
  const TeamMember({required this.userId, required this.role, required this.name, required this.email, this.addedAt});
  final String userId;

  /// 'owner' or 'recruiter'.
  final String role;
  final String name;
  final String email;
  final DateTime? addedAt;

  bool get isOwner => role == 'owner';

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: j['user_id'] as String,
        role: j['role'] as String? ?? 'recruiter',
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        addedAt: j['added_at'] == null ? null : DateTime.tryParse('${j['added_at']}'),
      );
}

/// The signed-in employer's launch offer: free postings left and until when.
class LaunchOffer {
  const LaunchOffer({required this.freePosts, required this.used, this.until, this.active = false});
  final int freePosts;
  final int used;
  final DateTime? until;
  final bool active;

  int get remaining => (freePosts - used).clamp(0, freePosts);
  bool get available => active && remaining > 0;

  static const none = LaunchOffer(freePosts: 0, used: 0);

  factory LaunchOffer.fromJson(Map<String, dynamic> j) => LaunchOffer(
        freePosts: (j['free_posts'] as num?)?.toInt() ?? 0,
        used: (j['used'] as num?)?.toInt() ?? 0,
        until: DateTime.tryParse('${j['until'] ?? ''}'),
        active: j['active'] as bool? ?? false,
      );
}
