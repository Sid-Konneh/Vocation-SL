import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../models/models.dart';
import 'supabase_backend.dart' show guardSupabase;

/// Interview time slots, employer reply times, talent search, hiring reports,
/// the support inbox and the weekly admin digest (supabase/release_1_2.sql).
/// Used by job seekers, employers and admins; the database decides what each
/// account may see and do.
abstract interface class HiringBackend {
  // Interview time slots
  /// The most recent times offered on an application (null if none).
  Future<InterviewProposal?> latestProposal(String applicationId);
  Future<void> proposeInterview(String applicationId, List<DateTime> slots, {String place = '', String note = ''});
  Future<void> chooseSlot(String proposalId, DateTime slot);

  /// How quickly a company usually replies to applicants.
  Future<ReplySpeed> replySpeed(String companyId);

  // Talent search
  Future<bool> myDiscoverable();
  Future<void> setDiscoverable(bool value);
  Future<List<TalentProfile>> searchTalent({String query = '', String location = '', String industry = '', int offset = 0});
  Future<void> inviteToApply(String userId, String jobId, {String note = ''});

  /// The full profile of someone who chose to be found (no phone, email or CV).
  Future<AppUser> talentProfile(String userId);

  /// The hiring report for one of the company's jobs.
  Future<JobReport> jobReport(String jobId);

  // Support inbox
  Future<List<SupportTicket>> myTickets();
  Future<List<SupportTicket>> allTickets();
  Future<List<SupportMessage>> supportThread(String ticketId);
  Future<String> openTicket({required String subject, required SupportCategory category, required String body, required UserRole side});
  Future<void> replySupport(String ticketId, String body);
  Future<void> setSupportStatus(String ticketId, SupportStatus status);

  // Weekly admin digest
  Future<WeeklyDigest> weeklyDigest();

  /// Sends the "weekly digest" notification to owners and admins now.
  Future<int> sendDigestNow();
}

class SupabaseHiringBackend implements HiringBackend {
  SupabaseHiringBackend(this._client);
  final sb.SupabaseClient _client;

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  Map<String, dynamic> _map(Object? r) => r is Map ? Map<String, dynamic>.from(r) : const {};

  @override
  Future<InterviewProposal?> latestProposal(String applicationId) async {
    try {
      final rows = await _client
          .from('interview_proposals')
          .select()
          .eq('application_id', applicationId)
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : InterviewProposal.fromJson(rows.first);
    } catch (_) {
      return null; // table not installed yet
    }
  }

  @override
  Future<void> proposeInterview(String applicationId, List<DateTime> slots, {String place = '', String note = ''}) =>
      guardSupabase(() => _client.rpc('propose_interview', params: {
            'p_app': applicationId,
            'p_slots': [for (final s in slots) s.toUtc().toIso8601String()],
            'p_place': place.trim(),
            'p_note': note.trim(),
          }));

  @override
  Future<void> chooseSlot(String proposalId, DateTime slot) => guardSupabase(
      () => _client.rpc('choose_interview_slot', params: {'p_proposal': proposalId, 'p_slot': slot.toUtc().toIso8601String()}));

  @override
  Future<ReplySpeed> replySpeed(String companyId) async {
    try {
      return ReplySpeed.fromJson(_map(await _client.rpc('employer_reply_speed', params: {'p_company': companyId})));
    } catch (_) {
      return ReplySpeed.unknown;
    }
  }

  @override
  Future<bool> myDiscoverable() async {
    try {
      final row = await _client.from('profiles').select('discoverable').eq('id', _uid()).maybeSingle();
      return row?['discoverable'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setDiscoverable(bool value) =>
      guardSupabase(() => _client.from('profiles').update({'discoverable': value}).eq('id', _uid()));

  @override
  Future<List<TalentProfile>> searchTalent({String query = '', String location = '', String industry = '', int offset = 0}) =>
      guardSupabase(() async {
        final rows = await _client.rpc('search_talent', params: {
          'p_query': query.trim(),
          'p_location': location,
          'p_industry': industry,
          'p_limit': 30,
          'p_offset': offset,
        }) as List;
        return [for (final r in rows) TalentProfile.fromJson(_map(r))];
      });

  @override
  Future<void> inviteToApply(String userId, String jobId, {String note = ''}) =>
      guardSupabase(() => _client.rpc('invite_to_apply', params: {'p_user': userId, 'p_job': jobId, 'p_note': note.trim()}));

  @override
  Future<AppUser> talentProfile(String userId) => guardSupabase(() async {
        final d = _map(await _client.rpc('talent_profile', params: {'p_user': userId}));
        return AppUser.fromJson({...d, 'id': userId, 'email': '', 'phone': ''});
      });

  @override
  Future<JobReport> jobReport(String jobId) =>
      guardSupabase(() async => JobReport.fromJson(_map(await _client.rpc('job_report', params: {'p_job': jobId}))));

  @override
  Future<List<SupportTicket>> myTickets() => guardSupabase(() async {
        final rows = await _client.from('support_tickets').select().eq('user_id', _uid()).order('last_message_at', ascending: false);
        return rows.map(SupportTicket.fromJson).toList();
      });

  @override
  Future<List<SupportTicket>> allTickets() => guardSupabase(() async {
        final rows = await _client.from('support_tickets').select().order('last_message_at', ascending: false).limit(300);
        final ids = {for (final r in rows) r['user_id'] as String}.toList();
        var people = <String, Map<String, dynamic>>{};
        if (ids.isNotEmpty) {
          try {
            final profiles = await _client.from('profiles').select('id, email, full_name').inFilter('id', ids);
            people = {for (final p in profiles) p['id'] as String: p};
          } catch (_) {}
        }
        return [
          for (final r in rows)
            SupportTicket.fromJson({
              ...r,
              'user_name': people[r['user_id']]?['full_name'] ?? '',
              'user_email': people[r['user_id']]?['email'] ?? '',
            }),
        ];
      });

  @override
  Future<List<SupportMessage>> supportThread(String ticketId) => guardSupabase(() async {
        final rows = await _client.from('support_messages').select().eq('ticket_id', ticketId).order('created_at');
        return rows.map(SupportMessage.fromJson).toList();
      });

  @override
  Future<String> openTicket({required String subject, required SupportCategory category, required String body, required UserRole side}) =>
      guardSupabase(() async => '${await _client.rpc('open_support_ticket', params: {
            'p_subject': subject.trim(),
            'p_category': category.name,
            'p_body': body.trim(),
            'p_side': side == UserRole.employer ? 'employer' : 'seeker',
          })}');

  @override
  Future<void> replySupport(String ticketId, String body) =>
      guardSupabase(() => _client.rpc('reply_support', params: {'p_ticket': ticketId, 'p_body': body.trim()}));

  @override
  Future<void> setSupportStatus(String ticketId, SupportStatus status) =>
      guardSupabase(() => _client.rpc('set_support_status', params: {'p_ticket': ticketId, 'p_status': status.name}));

  @override
  Future<WeeklyDigest> weeklyDigest() => guardSupabase(() async => WeeklyDigest(_map(await _client.rpc('admin_weekly_digest'))));

  @override
  Future<int> sendDigestNow() => guardSupabase(() async => ((await _client.rpc('send_weekly_digest')) as num?)?.toInt() ?? 0);
}

/// In-memory version for demo mode and tests. Job seeker, employer and admin
/// share it, so an interview offered on one side can be chosen on the other.
class DemoHiringBackend implements HiringBackend {
  DemoHiringBackend({this.userId = 'demo-user'}) {
    _seedSupport();
  }
  final String userId;

  final proposals = <InterviewProposal>[];
  bool discoverable = false;
  final invites = <(String userId, String jobId)>{};
  final tickets = <SupportTicket>[];
  final supportMessages = <SupportMessage>[];
  int digestsSent = 0;
  var _seq = 0;

  String _id(String p) => '$p-${++_seq}';

  @override
  Future<InterviewProposal?> latestProposal(String applicationId) async =>
      proposals.where((p) => p.applicationId == applicationId).lastOrNull;

  @override
  Future<void> proposeInterview(String applicationId, List<DateTime> slots, {String place = '', String note = ''}) async {
    final s = {...slots}.toList()..sort();
    if (s.isEmpty) throw const ValidationException('Choose at least one interview time.');
    if (s.length > 3) throw const ValidationException('Offer up to 3 interview times.');
    if (s.any((x) => x.isBefore(DateTime.now().add(const Duration(hours: 1))))) {
      throw const ValidationException('Interview times must be at least an hour from now.');
    }
    for (var i = 0; i < proposals.length; i++) {
      final p = proposals[i];
      if (p.applicationId == applicationId && p.status != InterviewProposalStatus.cancelled) {
        proposals[i] = InterviewProposal(
            id: p.id, applicationId: p.applicationId, slots: p.slots, status: InterviewProposalStatus.cancelled, createdAt: p.createdAt, place: p.place, note: p.note);
      }
    }
    proposals.add(InterviewProposal(
      id: _id('ip'),
      applicationId: applicationId,
      slots: s,
      status: InterviewProposalStatus.open,
      createdAt: DateTime.now(),
      place: place.trim(),
      note: note.trim(),
    ));
  }

  @override
  Future<void> chooseSlot(String proposalId, DateTime slot) async {
    final i = proposals.indexWhere((p) => p.id == proposalId);
    if (i < 0) throw const NotFoundException('Interview times not found.');
    final p = proposals[i];
    if (!p.isOpen) throw const ValidationException('These interview times are no longer available.');
    if (!p.slots.contains(slot)) throw const ValidationException('Choose one of the times offered.');
    proposals[i] = InterviewProposal(
      id: p.id,
      applicationId: p.applicationId,
      slots: p.slots,
      status: InterviewProposalStatus.chosen,
      createdAt: p.createdAt,
      place: p.place,
      note: p.note,
      chosenAt: slot,
    );
  }

  @override
  Future<ReplySpeed> replySpeed(String companyId) async =>
      const ReplySpeed(applications: 14, replied: 11, medianHours: 52, repliedWithin7Days: 10);

  @override
  Future<bool> myDiscoverable() async => discoverable;

  @override
  Future<void> setDiscoverable(bool value) async => discoverable = value;

  static final _talent = [
    TalentProfile.fromJson({
      'user_id': 't-1',
      'full_name': 'Aminata Sesay',
      'headline': 'Accountant · ACCA part-qualified',
      'location': 'Freetown',
      'about': 'Five years of bookkeeping, payroll and month-end close for NGOs and trading companies.',
      'skills': ['Bookkeeping', 'QuickBooks', 'Excel', 'Payroll', 'Tax returns'],
      'experience': [
        {'title': 'Accounts Officer', 'company': 'Freetown Traders Ltd', 'start': '2021-02-01'},
        {'title': 'Accounts Assistant', 'company': 'Hope Relief SL', 'start': '2019-01-01', 'end': '2021-01-01'},
      ],
      'education': [
        {'degree': 'BSc', 'field': 'Accounting', 'school': 'Fourah Bay College', 'end_year': 2018},
      ],
      'languages': [
        {'name': 'English', 'level': 'Fluent'},
        {'name': 'Krio', 'level': 'Native'},
      ],
      'updated_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
    }),
    TalentProfile.fromJson({
      'user_id': 't-2',
      'full_name': 'Mohamed Kanu',
      'headline': 'Sales and customer service',
      'location': 'Bo',
      'about': 'Field sales across the Southern Province; I meet targets and know the market.',
      'skills': ['Sales', 'Customer service', 'Negotiation', 'Motorbike licence'],
      'experience': [
        {'title': 'Sales Representative', 'company': 'Bo Distributors', 'start': '2022-05-01'},
      ],
      'education': [
        {'degree': 'Diploma', 'field': 'Business Studies', 'school': 'Njala University', 'end_year': 2021},
      ],
      'languages': [
        {'name': 'English', 'level': 'Good'},
        {'name': 'Mende', 'level': 'Native'},
      ],
      'updated_at': DateTime.now().subtract(const Duration(days: 6)).toIso8601String(),
    }),
    TalentProfile.fromJson({
      'user_id': 't-3',
      'full_name': 'Isata Koroma',
      'headline': 'Registered nurse',
      'location': 'Kenema',
      'about': 'Maternal and child health nurse with community outreach experience.',
      'skills': ['Nursing', 'Maternal health', 'Vaccination', 'Patient records'],
      'experience': [
        {'title': 'Staff Nurse', 'company': 'Kenema Government Hospital', 'start': '2020-03-01'},
      ],
      'education': [
        {'degree': 'Diploma', 'field': 'Nursing', 'school': 'National School of Nursing', 'end_year': 2019},
      ],
      'updated_at': DateTime.now().subtract(const Duration(days: 11)).toIso8601String(),
    }),
  ];

  @override
  Future<List<TalentProfile>> searchTalent({String query = '', String location = '', String industry = '', int offset = 0}) async {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return [
      for (final t in _talent)
        if ((location.isEmpty || t.location == location) &&
            terms.every((q) => [t.fullName, t.headline, t.about, ...t.skills, ...t.experience].join(' ').toLowerCase().contains(q)))
          TalentProfile(
            userId: t.userId,
            fullName: t.fullName,
            headline: t.headline,
            location: t.location,
            about: t.about,
            skills: t.skills,
            experience: t.experience,
            education: t.education,
            languages: t.languages,
            updatedAt: t.updatedAt,
            invitedJobIds: [for (final i in invites) if (i.$1 == t.userId) i.$2],
          ),
    ].skip(offset).toList();
  }

  @override
  Future<void> inviteToApply(String userId, String jobId, {String note = ''}) async {
    if (!invites.add((userId, jobId))) throw const ValidationException('You\'ve already invited them to this job.');
  }

  @override
  Future<AppUser> talentProfile(String userId) async {
    final t = _talent.where((x) => x.userId == userId).firstOrNull;
    if (t == null) throw const NotFoundException('This person is no longer open to employers.');
    return AppUser(
      id: t.userId,
      fullName: t.fullName,
      email: '',
      headline: t.headline,
      location: t.location,
      about: t.about,
      skills: t.skills,
      experience: [
        Experience(
          title: t.headline.split('·').first.trim(),
          company: t.experience.isEmpty ? '' : t.experience.first.split('·').last.split('(').first.trim(),
          location: t.location,
          start: DateTime(2021, 2),
          description: 'Sample experience for demo mode.',
        ),
      ],
      languages: [for (final l in t.languages) LanguageSkill(name: l.split(' (').first, level: l.contains('(') ? l.split('(').last.replaceAll(')', '') : '')],
      preferences: JobPreferences(titles: [t.headline.split('·').first.trim()], locations: {t.location}),
    );
  }

  @override
  Future<JobReport> jobReport(String jobId) async {
    final now = DateTime.now();
    return JobReport.fromJson({
      'job_id': jobId,
      'title': 'Sample job',
      'status': 'published',
      'location': 'Freetown',
      'posted_at': now.subtract(const Duration(days: 12)).toIso8601String(),
      'deadline': now.add(const Duration(days: 18)).toIso8601String(),
      'views': 214,
      'apply_clicks': 0,
      'applies_externally': false,
      'applications': 18,
      'withdrawn': 1,
      'current': {'applied': 5, 'viewed': 4, 'shortlisted': 3, 'interview': 2, 'offer': 1, 'hired': 1, 'rejected': 1, 'withdrawn': 1},
      'reached': {'shortlisted': 7, 'interview': 4, 'offer': 2, 'hired': 1},
      'sources': {'home': 6, 'search': 4, 'alert': 3, 'link': 3, 'invite': 1, 'unknown': 1},
      'invites_sent': 4,
      'invited_applied': 1,
      'replied': 13,
      'median_reply_hours': 41.5,
      'first_hire_days': 10.2,
      'by_day': [for (var d = 11; d >= 0; d--) {'day': now.subtract(Duration(days: d)).toIso8601String(), 'n': [3, 4, 2, 1, 2, 0, 1, 2, 1, 0, 1, 1][11 - d]}],
      'generated_at': now.toIso8601String(),
    });
  }

  void _seedSupport() {
    final at = DateTime.now().subtract(const Duration(days: 1, hours: 3));
    tickets.add(SupportTicket(
      id: 'st-demo',
      userId: userId,
      subject: 'How do I change my CV?',
      category: SupportCategory.applications,
      status: SupportStatus.answered,
      createdAt: at,
      lastMessageAt: at.add(const Duration(hours: 2)),
      userName: 'Demo user',
      userEmail: 'demo@vocationsl.app',
    ));
    supportMessages.addAll([
      SupportMessage(id: 'sm-1', ticketId: 'st-demo', fromStaff: false, body: 'I want to replace the CV I uploaded last month.', createdAt: at),
      SupportMessage(
        id: 'sm-2',
        ticketId: 'st-demo',
        fromStaff: true,
        body: 'Go to Profile, then tap your CV and choose "Replace". Applications you already sent keep the old CV.',
        createdAt: at.add(const Duration(hours: 2)),
      ),
    ]);
  }

  @override
  Future<List<SupportTicket>> myTickets() async =>
      tickets.where((t) => t.userId == userId).toList()..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

  @override
  Future<List<SupportTicket>> allTickets() async => List.of(tickets)..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

  @override
  Future<List<SupportMessage>> supportThread(String ticketId) async => supportMessages.where((m) => m.ticketId == ticketId).toList();

  @override
  Future<String> openTicket({required String subject, required SupportCategory category, required String body, required UserRole side}) async {
    if (subject.trim().length < 3) throw const ValidationException('Add a short subject.');
    if (body.trim().length < 10) throw const ValidationException('Tell us a little more (at least 10 characters).');
    final now = DateTime.now();
    final t = SupportTicket(
      id: _id('st'),
      userId: userId,
      subject: subject.trim(),
      category: category,
      status: SupportStatus.open,
      createdAt: now,
      lastMessageAt: now,
      side: side,
      userName: 'Demo user',
      userEmail: 'demo@vocationsl.app',
    );
    tickets.add(t);
    supportMessages.add(SupportMessage(id: _id('sm'), ticketId: t.id, fromStaff: false, body: body.trim(), createdAt: now));
    return t.id;
  }

  /// In the demo, replies from the admin dashboard count as staff replies.
  bool replyAsStaff = false;

  @override
  Future<void> replySupport(String ticketId, String body) async {
    if (body.trim().isEmpty) throw const ValidationException('Write a message first.');
    final i = tickets.indexWhere((t) => t.id == ticketId);
    if (i < 0) throw const NotFoundException('Request not found.');
    final now = DateTime.now();
    supportMessages.add(SupportMessage(id: _id('sm'), ticketId: ticketId, fromStaff: replyAsStaff, body: body.trim(), createdAt: now));
    tickets[i] = tickets[i].copyWith(status: replyAsStaff ? SupportStatus.answered : SupportStatus.open, lastMessageAt: now);
  }

  @override
  Future<void> setSupportStatus(String ticketId, SupportStatus status) async {
    final i = tickets.indexWhere((t) => t.id == ticketId);
    if (i >= 0) tickets[i] = tickets[i].copyWith(status: status);
  }

  @override
  Future<WeeklyDigest> weeklyDigest() async {
    final now = DateTime.now();
    return WeeklyDigest({
      'from': now.subtract(const Duration(days: 7)).toIso8601String(),
      'to': now.toIso8601String(),
      'new_users': 42,
      'new_users_prev': 35,
      'new_employers': 3,
      'new_employers_prev': 2,
      'new_employer_names': ['Lumley Trading Co.', 'Bo Distributors', 'Hope Relief SL'],
      'companies_pending': 1,
      'jobs_new': 6,
      'jobs_new_prev': 4,
      'jobs_pending': 2,
      'jobs_live': 19,
      'applications': 87,
      'applications_prev': 64,
      'revenue_paid': 17250,
      'revenue_paid_prev': 11500,
      'unpaid_count': 2,
      'unpaid_total': 11500,
      'overdue_count': 1,
      'reports_open': 1,
      'flagged_jobs': 1,
      'support_open': tickets.where((t) => t.status == SupportStatus.open).length,
      'referrals_to_pay': 1,
    });
  }

  @override
  Future<int> sendDigestNow() async => ++digestsSent;
}
