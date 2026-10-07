import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/dev_settings.dart';
import '../../core/errors.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/storage/local_store.dart';
import '../../models/models.dart';
import '../demo/demo_companies.dart';
import '../demo/demo_jobs.dart';
import '../demo/demo_seed.dart';
import 'backend.dart';

/// A local stand-in for a real server.
///
/// It behaves like a network service: it adds latency, fails when the
/// device is offline, and can simulate server errors. Its "database" is kept
/// in Hive so applications and profile edits survive restarts. Employer
/// activity is simulated: applications you submit move through the pipeline
/// over a few minutes and generate notifications.
class DemoBackend implements VocationBackend {
  DemoBackend({required this.store, required this.connectivity, required this.devSettings}) {
    _jobs = {for (final j in buildDemoJobs(_now)) j.id: j};
    _companies = {for (final c in demoCompanies) c.id: c};
    _state = store.demoState() ?? _seed();
    _currentUserId = store.setting<String>('demo_session');
  }

  final LocalStore store;
  final ConnectivityService connectivity;
  DevSettings Function() devSettings;

  final _rand = Random();
  final _uuid = const Uuid();
  final DateTime _now = DateTime.now();
  late final Map<String, Job> _jobs;
  late final Map<String, Company> _companies;
  late Map<String, dynamic> _state;
  String? _currentUserId;

  @override
  String get name => 'Demo';

  Map<String, dynamic> _seed() {
    final user = buildDemoUser(_now);
    return {
      'seeded_at': _now.toIso8601String(),
      'accounts': {
        demoEmail: {'password': demoPassword, 'user_id': demoUserId},
      },
      'users': {demoUserId: user.toJson()},
      'applications': buildDemoApplications(_now, user).map((a) => a.toJson(includeLocal: false)).toList(),
      'notifications': buildDemoNotifications(_now).map((n) => n.toJson()).toList(),
      'saved': buildDemoSavedJobs(_now).map((s) => s.toJson()).toList(),
      'alerts': buildDemoAlerts(_now).map((a) => a.toJson()).toList(),
    };
  }

  Future<void> _persist() => store.saveDemoState(_state);

  Future<void> reset() async {
    _state = _seed();
    await _persist();
  }

  /// Simulates a network round trip.
  Future<void> _call() async {
    final dev = devSettings();
    final ms = dev.slowNetwork ? 2200 + _rand.nextInt(1200) : 250 + _rand.nextInt(450);
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (!connectivity.isOnline) throw const NetworkException();
    if (dev.failRequests && _rand.nextBool()) throw const ServerException('Simulated server error');
  }

  List<Map<String, dynamic>> _list(String key) => (_state[key] as List).cast<Map<String, dynamic>>();

  Job _withCompany(Job j) => j.withCompany(_companies[j.companyId]);

  // ---- Auth ------------------------------------------------------------------

  @override
  String? get currentUserId => _currentUserId;

  @override
  Stream<String?> get authChanges => const Stream.empty();

  @override
  bool get supportsGoogleSignIn => false;

  @override
  UserRole? get currentRole {
    final r = _currentUserId == null ? null : store.setting<String>('demo_role:$_currentUserId');
    return UserRole.values.where((v) => v.name == r).firstOrNull;
  }

  @override
  Future<void> setRole(UserRole role) async {
    if (_currentUserId != null) await store.setSetting('demo_role:$_currentUserId', role.name);
  }

  @override
  Future<void> signInWithGoogle() async =>
      throw const AuthException('Google sign-in is available when the app is connected to Supabase.');

  @override
  Future<void> sendPasswordReset(String email) async {
    await _call();
    // Demo mode has no email delivery; the UI shows the same confirmation either way.
  }

  @override
  Stream<void> get passwordRecovery => const Stream.empty();

  @override
  Future<void> updatePassword(String newPassword) async {
    await _call();
    final accounts = Map<String, dynamic>.from(_state['accounts'] as Map);
    for (final entry in accounts.entries) {
      final acct = Map<String, dynamic>.from(entry.value as Map);
      if (acct['user_id'] == _currentUserId) accounts[entry.key] = {...acct, 'password': newPassword};
    }
    _state['accounts'] = accounts;
    await _persist();
  }

  @override
  Future<String> signIn({required String email, required String password}) async {
    await _call();
    final accounts = Map<String, dynamic>.from(_state['accounts'] as Map);
    final acct = accounts[email.trim().toLowerCase()] as Map?;
    if (acct == null || acct['password'] != password) {
      throw const AuthException('That email and password don\'t match. Try the demo account below.');
    }
    _currentUserId = acct['user_id'] as String;
    await store.setSetting('demo_session', _currentUserId);
    return _currentUserId!;
  }

  @override
  Future<String> signUp({required String fullName, required String email, required String password}) async {
    await _call();
    final key = email.trim().toLowerCase();
    final accounts = Map<String, dynamic>.from(_state['accounts'] as Map);
    if (accounts.containsKey(key)) throw const AuthException('An account with this email already exists. Sign in instead.');
    final id = _uuid.v4();
    accounts[key] = {'password': password, 'user_id': id};
    _state['accounts'] = accounts;
    final users = Map<String, dynamic>.from(_state['users'] as Map);
    users[id] = AppUser(id: id, fullName: fullName.trim(), email: key).toJson();
    _state['users'] = users;
    await _persist();
    _currentUserId = id;
    await store.setSetting('demo_session', id);
    return id;
  }

  @override
  Future<void> signOut() async {
    _currentUserId = null;
    await store.removeSetting('demo_session');
  }

  // ---- Catalogue -------------------------------------------------------------

  @override
  Future<List<Company>> fetchCompanies() async {
    await _call();
    return _companies.values.toList();
  }

  @override
  Future<PageResult<Job>> searchJobs(JobFilter filter, {required int page, required int pageSize}) async {
    await _call();
    final all = filter.apply(_jobs.values.map(_withCompany));
    final start = page * pageSize;
    final items = start >= all.length ? <Job>[] : all.sublist(start, min(start + pageSize, all.length));
    return PageResult(items: items, page: page, hasMore: start + pageSize < all.length, total: all.length);
  }

  @override
  Future<Job> fetchJob(String id) async {
    await _call();
    final j = _jobs[id];
    if (j == null) throw const NotFoundException();
    return _withCompany(j);
  }

  @override
  Future<void> recordJobView(String jobId) async {}

  // ---- Profile ---------------------------------------------------------------

  @override
  Future<AppUser> fetchUser(String userId) async {
    await _call();
    final raw = (_state['users'] as Map)[userId];
    if (raw == null) throw const NotFoundException('User not found');
    return AppUser.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  @override
  Future<AppUser> updateUser(AppUser user) async {
    await _call();
    final users = Map<String, dynamic>.from(_state['users'] as Map);
    users[user.id] = user.toJson();
    _state['users'] = users;
    await _persist();
    return user;
  }

  @override
  Future<String> uploadDocument({required String userId, required String fileName, required Uint8List bytes}) async {
    await _call();
    // Simulate upload time proportional to file size (capped).
    await Future<void>.delayed(Duration(milliseconds: min(1500, bytes.length ~/ 400)));
    return 'demo/$userId/${_uuid.v4()}-$fileName';
  }

  // ---- Applications ----------------------------------------------------------

  @override
  Future<List<JobApplication>> fetchApplications(String userId) async {
    await _call();
    await _advanceSimulatedPipeline(userId);
    return _list('applications')
        .where((a) => a['user_id'] == userId)
        .map((a) {
          final app = JobApplication.fromJson(a);
          final j = _jobs[app.jobId];
          return app.copyWith(job: () => j == null ? null : _withCompany(j));
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<JobApplication> submitApplication(JobApplication application) async {
    await _call();
    final apps = _list('applications');
    if (apps.any((a) => a['user_id'] == application.userId && a['job_id'] == application.jobId && a['status'] != 'withdrawn')) {
      throw const ValidationException('You have already applied for this job.');
    }
    final saved = application.copyWith(pendingSync: false);
    apps.add({...saved.toJson(includeLocal: false), 'simulate': true});
    final job = _jobs[application.jobId];
    _notify(
      application.userId,
      NotificationType.submitted,
      'Application submitted',
      'Your application for ${job?.title ?? 'the job'} was sent to ${_companies[job?.companyId]?.name ?? 'the employer'}.',
      jobId: application.jobId,
      appId: application.id,
    );
    await _persist();
    return saved.copyWith(job: () => job == null ? null : _withCompany(job));
  }

  @override
  Future<JobApplication> withdrawApplication(String applicationId, {String? reason}) async {
    await _call();
    final apps = _list('applications');
    final i = apps.indexWhere((a) => a['id'] == applicationId);
    if (i < 0) throw const NotFoundException();
    final app = JobApplication.fromJson(apps[i]);
    final updated = app.copyWith(
      status: ApplicationStatus.withdrawn,
      history: [...app.history, StatusEvent(status: ApplicationStatus.withdrawn, at: DateTime.now(), note: reason)],
    );
    apps[i] = updated.toJson(includeLocal: false);
    await _persist();
    final j = _jobs[app.jobId];
    return updated.copyWith(job: () => j == null ? null : _withCompany(j));
  }

  /// Moves applications submitted in this install along the hiring pipeline.
  Future<void> _advanceSimulatedPipeline(String userId) async {
    const steps = [
      (after: Duration(seconds: 40), status: ApplicationStatus.viewed),
      (after: Duration(minutes: 2), status: ApplicationStatus.shortlisted),
      (after: Duration(minutes: 4), status: ApplicationStatus.interview),
    ];
    final apps = _list('applications');
    var changed = false;
    for (var i = 0; i < apps.length; i++) {
      final raw = apps[i];
      if (raw['user_id'] != userId || raw['simulate'] != true) continue;
      var app = JobApplication.fromJson(raw);
      if (app.status.isClosed) continue;
      final job = _jobs[app.jobId];
      final company = _companies[job?.companyId]?.name ?? 'The employer';
      for (final step in steps) {
        final reached = app.history.any((e) => e.status == step.status);
        final due = DateTime.now().difference(app.submittedAt) >= step.after;
        if (reached || !due) continue;
        final at = app.submittedAt.add(step.after);
        app = app.copyWith(status: step.status, history: [...app.history, StatusEvent(status: step.status, at: at)]);
        switch (step.status) {
          case ApplicationStatus.viewed:
            _notify(userId, NotificationType.viewed, 'Application viewed', '$company viewed your application for ${job?.title}.',
                jobId: app.jobId, appId: app.id, at: at);
          case ApplicationStatus.shortlisted:
            _notify(userId, NotificationType.shortlisted, 'You were shortlisted', '$company shortlisted you for ${job?.title}.',
                jobId: app.jobId, appId: app.id, at: at);
          case ApplicationStatus.interview:
            final interviewAt = DateTime(at.year, at.month, at.day, 11).add(const Duration(days: 4));
            app = app.copyWith(
              interviewAt: () => interviewAt,
              employerMessage: () =>
                  'Thank you for applying. We would like to meet you for an interview. Please confirm your availability by replying to our email.',
            );
            _notify(userId, NotificationType.interview, 'Interview invitation', '$company invited you to interview for ${job?.title}.',
                jobId: app.jobId, appId: app.id, at: at);
            _notify(userId, NotificationType.message, 'New message from $company', 'Please confirm your interview availability.',
                jobId: app.jobId, appId: app.id, at: at);
          default:
            break;
        }
        changed = true;
      }
      apps[i] = {...app.toJson(includeLocal: false), 'simulate': true};
    }
    if (changed) await _persist();
  }

  // ---- Notifications ---------------------------------------------------------

  void _notify(String userId, NotificationType type, String title, String body, {String? jobId, String? appId, DateTime? at}) {
    final userRaw = (_state['users'] as Map)[userId];
    if (userRaw != null) {
      final prefs = AppUser.fromJson(Map<String, dynamic>.from(userRaw as Map)).notificationPreferences;
      if (!prefs.allows(type)) return;
    }
    _list('notifications').add(AppNotification(
      id: _uuid.v4(),
      userId: userId,
      type: type,
      title: title,
      body: body,
      createdAt: at ?? DateTime.now(),
      jobId: jobId,
      applicationId: appId,
    ).toJson());
  }

  @override
  Future<List<AppNotification>> fetchNotifications(String userId) async {
    await _call();
    await _advanceSimulatedPipeline(userId);
    return _list('notifications').where((n) => n['user_id'] == userId).map(AppNotification.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> markNotificationsRead(String userId, List<String> ids) async {
    await _call();
    final set = ids.toSet();
    for (final n in _list('notifications')) {
      if (n['user_id'] == userId && (set.isEmpty || set.contains(n['id']))) n['read'] = true;
    }
    await _persist();
  }

  @override
  Future<void> deleteNotification(String id) async {
    await _call();
    _list('notifications').removeWhere((n) => n['id'] == id);
    await _persist();
  }

  // ---- Saved -----------------------------------------------------------------

  @override
  Future<List<SavedJob>> fetchSavedJobs(String userId) async {
    await _call();
    return _list('saved')
        .where((s) => s['user_id'] == userId)
        .map(SavedJob.fromJson)
        .map((s) => s.withJob(_jobs[s.jobId] == null ? null : _withCompany(_jobs[s.jobId]!)))
        .toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  @override
  Future<void> saveJob(SavedJob saved) async {
    await _call();
    final list = _list('saved');
    if (!list.any((s) => s['user_id'] == saved.userId && s['job_id'] == saved.jobId)) list.add(saved.toJson());
    await _persist();
  }

  @override
  Future<void> unsaveJob(String userId, String jobId) async {
    await _call();
    _list('saved').removeWhere((s) => s['user_id'] == userId && s['job_id'] == jobId);
    await _persist();
  }

  @override
  Future<List<JobAlert>> fetchAlerts(String userId) async {
    await _call();
    return _list('alerts').where((a) => a['user_id'] == userId).map(JobAlert.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<JobAlert> upsertAlert(JobAlert alert) async {
    await _call();
    final list = _list('alerts');
    final i = list.indexWhere((a) => a['id'] == alert.id);
    if (i >= 0) {
      list[i] = alert.toJson();
    } else {
      list.add(alert.toJson());
      final matches = alert.filter.apply(_jobs.values.map(_withCompany));
      if (matches.isNotEmpty) {
        _notify(
          alert.userId,
          NotificationType.savedSearch,
          '${matches.length} ${matches.length == 1 ? 'job matches' : 'jobs match'} "${alert.name}"',
          matches.length == 1 ? matches.first.title : '${matches.first.title} and ${matches.length - 1} more',
          jobId: matches.first.id,
        );
      }
    }
    await _persist();
    return alert;
  }

  @override
  Future<void> deleteAlert(String alertId) async {
    await _call();
    _list('alerts').removeWhere((a) => a['id'] == alertId);
    await _persist();
  }
}
