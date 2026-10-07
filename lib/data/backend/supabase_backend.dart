import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/errors.dart';
import '../../models/models.dart';
import 'backend.dart';

/// Supabase implementation of [VocationBackend].
///
/// Schema, row-level security and seed data live in /supabase. Complex
/// nested objects (profile, application documents) are stored as jsonb so the
/// Dart models map one-to-one.
class SupabaseBackend implements VocationBackend {
  SupabaseBackend(this._client);

  final sb.SupabaseClient _client;
  final _uuid = const Uuid();

  static const _jobSelect = '*, company:companies(*)';
  static const _bucket = 'documents';

  @override
  String get name => 'Supabase';

  Future<T> _run<T>(Future<T> Function() body) => guardSupabase(body);

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  // ---- Auth ------------------------------------------------------------------

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get authChanges => _client.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();

  @override
  bool get supportsGoogleSignIn => true;

  @override
  UserRole? get currentRole {
    final r = _client.auth.currentUser?.userMetadata?['role'];
    return UserRole.values.where((v) => v.name == r).firstOrNull;
  }

  @override
  Future<void> setRole(UserRole role) => _run(() async {
        await _client.auth.updateUser(sb.UserAttributes(data: {'role': role.name}));
      });

  /// Where Supabase sends the user back after OAuth, email confirmation or
  /// password reset: the current site on web, the app's deep link on mobile.
  /// The trailing slash matters: Supabase matches it against allow-list
  /// entries like "https://site/**"; a bare origin falls back to the Site URL.
  String get _redirect => kIsWeb ? '${Uri.base.origin}/' : AppConfig.mobileAuthRedirect;

  @override
  Future<String> signIn({required String email, required String password}) => _run(() async {
        final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
        return res.user!.id;
      });

  @override
  Future<String> signUp({required String fullName, required String email, required String password}) => _run(() async {
        final res = await _client.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': fullName.trim()},
          emailRedirectTo: _redirect,
        );
        final user = res.user;
        if (user == null || res.session == null) throw EmailConfirmationRequired(email.trim());
        return user.id;
      });

  @override
  Future<void> signInWithGoogle({UserRole? intent}) => _run(() async {
        final redirect = kIsWeb && intent != null ? '$_redirect?role=${intent.name}' : _redirect;
        final launched = await _client.auth.signInWithOAuth(sb.OAuthProvider.google, redirectTo: redirect);
        if (!launched) throw const AuthException('Couldn\'t open Google sign-in. Try again.');
      });

  @override
  Future<void> sendPasswordReset(String email) => _run(() async {
        await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect);
      });

  @override
  Stream<void> get passwordRecovery =>
      _client.auth.onAuthStateChange.where((s) => s.event == sb.AuthChangeEvent.passwordRecovery);

  @override
  Future<void> updatePassword(String newPassword) => _run(() async {
        await _client.auth.updateUser(sb.UserAttributes(password: newPassword));
      });

  @override
  Future<void> signOut() => _run(() => _client.auth.signOut());

  @override
  Future<void> deleteAccount() => _run(() async {
        final uid = _uid();
        // 1. Files can only be removed through the Storage API (best effort).
        await _removeFolder(_bucket, uid);
        try {
          final mine = await _client.from('company_members').select('company_id').eq('user_id', uid);
          for (final row in mine) {
            final cid = row['company_id'] as String;
            final members = await _client.from('company_members').select('user_id').eq('company_id', cid);
            if (members.length <= 1) await _removeFolder('logos', cid);
          }
        } catch (_) {
          // Not an employer, or employer tables not installed.
        }
        // 2. Delete the account and its data in the database.
        await _client.rpc('delete_my_account');
        // 3. The session belongs to a deleted user; clear it locally.
        try {
          await _client.auth.signOut(scope: sb.SignOutScope.local);
        } catch (_) {}
      });

  Future<void> _removeFolder(String bucket, String folder) async {
    try {
      final files = await _client.storage.from(bucket).list(path: folder);
      if (files.isEmpty) return;
      await _client.storage.from(bucket).remove([for (final f in files) '$folder/${f.name}']);
    } catch (_) {
      // Missing bucket or no permission: nothing to remove.
    }
  }

  // ---- Platform content --------------------------------------------------------

  @override
  Future<List<Announcement>> fetchAnnouncements() => _run(() async {
        try {
          final rows = await _client.from('announcements').select().eq('active', true).order('created_at', ascending: false).limit(5);
          final now = DateTime.now();
          return rows.map(Announcement.fromJson).where((a) => a.isLiveAt(now)).toList();
        } on sb.PostgrestException {
          return const <Announcement>[]; // admin tables not installed yet
        }
      });

  @override
  Future<SitePage?> fetchPage(String slug) => _run(() async {
        try {
          final row = await _client.from('site_pages').select().eq('slug', slug).maybeSingle();
          return row == null ? null : SitePage.fromJson(row);
        } on sb.PostgrestException {
          return null;
        }
      });

  @override
  Future<PlatformSettings> fetchPlatformSettings() => _run(() async {
        try {
          final rows = await _client.from('platform_settings').select();
          return PlatformSettings.fromRows(List<Map<String, dynamic>>.from(rows));
        } on sb.PostgrestException {
          return const PlatformSettings();
        }
      });

  @override
  Future<bool> isSuspended() => _run(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) return false;
        try {
          final row = await _client.from('profiles').select('suspended').eq('id', uid).maybeSingle();
          return row?['suspended'] as bool? ?? false;
        } on sb.PostgrestException {
          return false; // column not installed yet
        }
      });

  @override
  Future<void> submitReport({required ReportTarget type, required String targetId, required String targetLabel, required String reason, String details = ''}) =>
      _run(() async {
        await _client.from('reports').insert({
          'reporter_id': _uid(),
          'target_type': type.name,
          'target_id': targetId,
          'target_label': targetLabel,
          'reason': reason,
          'details': details,
        });
      });

  // ---- Catalogue -------------------------------------------------------------

  @override
  Future<List<Company>> fetchCompanies() => _run(() async {
        final rows = await _client.from('companies').select();
        return rows.map(Company.fromJson).toList();
      });

  @override
  Future<PageResult<Job>> searchJobs(JobFilter f, {required int page, required int pageSize}) => _run(() async {
        var q = _client.from('jobs').select(_jobSelect);
        final text = f.query.trim().toLowerCase();
        for (final term in text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty)) {
          q = q.ilike('search_text', '%$term%');
        }
        if (f.locations.isNotEmpty) q = q.inFilter('location', f.locations.toList());
        if (f.employmentTypes.isNotEmpty) q = q.inFilter('employment_type', f.employmentTypes.map((e) => e.name).toList());
        if (f.industries.isNotEmpty) q = q.inFilter('industry', f.industries.map((e) => e.name).toList());
        if (f.experienceLevels.isNotEmpty) q = q.inFilter('experience_level', f.experienceLevels.map((e) => e.name).toList());
        if (f.workModes.isNotEmpty) q = q.inFilter('work_mode', f.workModes.map((e) => e.name).toList());
        if (f.companyId != null) q = q.eq('company_id', f.companyId!);
        if (f.minSalary != null) q = q.gte('salary_max', f.minSalary!);
        final days = f.datePosted.days;
        if (days != null) q = q.gte('posted_at', DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String());

        final ordered = switch (f.sort) {
          JobSort.newest => q.order('posted_at', ascending: false),
          JobSort.salary => q.order('salary_max', ascending: false, nullsFirst: false),
          JobSort.deadline => q.order('deadline', ascending: true),
          JobSort.relevance => q.order('featured', ascending: false).order('posted_at', ascending: false),
        };
        final from = page * pageSize;
        final rows = await ordered.range(from, from + pageSize - 1);
        final items = rows.map(Job.fromJson).toList();
        return PageResult(items: items, page: page, hasMore: items.length == pageSize);
      });

  @override
  Future<Job> fetchJob(String id) => _run(() async {
        final row = await _client.from('jobs').select(_jobSelect).eq('id', id).single();
        return Job.fromJson(row);
      });

  @override
  Future<void> recordJobView(String jobId) async {
    try {
      await _client.rpc('record_job_view', params: {'p_job': jobId});
    } catch (_) {
      // Analytics only: never block or fail the job page.
    }
  }

  // ---- Profile ---------------------------------------------------------------

  @override
  Future<AppUser> fetchUser(String userId) => _run(() async {
        var row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
        if (row == null) {
          // No profile yet (e.g. account created before the sign-up trigger existed).
          final auth = _client.auth.currentUser;
          final meta = auth?.userMetadata ?? const {};
          final name = (meta['full_name'] ?? meta['name'] ?? auth?.email?.split('@').first ?? '').toString();
          final fresh = AppUser(id: userId, fullName: name, email: auth?.email ?? '');
          await updateUser(fresh);
          row = {'id': userId, 'email': fresh.email, 'full_name': name, 'data': fresh.toJson()};
        }
        final data = Map<String, dynamic>.from(row['data'] as Map? ?? const {});
        return AppUser.fromJson({
          ...data,
          'id': userId,
          'email': row['email'] ?? data['email'] ?? _client.auth.currentUser?.email ?? '',
          'full_name': data['full_name'] ?? row['full_name'] ?? '',
        });
      });

  @override
  Future<AppUser> updateUser(AppUser user) => _run(() async {
        await _client.from('profiles').upsert({
          'id': user.id,
          'email': user.email,
          'full_name': user.fullName,
          'data': user.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        return user;
      });

  @override
  Future<String> documentUrl(String storagePath) => _run(() => _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 30));

  @override
  Future<String> uploadDocument({required String userId, required String fileName, required Uint8List bytes}) => _run(() async {
        final path = '$userId/${_uuid.v4()}-$fileName';
        await _client.storage.from(_bucket).uploadBinary(path, bytes);
        return path;
      });

  // ---- Applications ----------------------------------------------------------

  JobApplication _appFromRow(Map<String, dynamic> row) {
    final data = Map<String, dynamic>.from(row['data'] as Map);
    final app = JobApplication.fromJson({...data, 'id': row['id'], 'status': row['status'], 'user_id': row['user_id'], 'job_id': row['job_id']});
    final job = row['job'];
    return job is Map ? app.copyWith(job: () => Job.fromJson(Map<String, dynamic>.from(job))) : app;
  }

  @override
  Future<List<JobApplication>> fetchApplications(String userId) => _run(() async {
        final rows = await _client
            .from('applications')
            .select('*, job:jobs($_jobSelect)')
            .eq('user_id', userId)
            .order('updated_at', ascending: false);
        return rows.map(_appFromRow).toList();
      });

  @override
  Future<JobApplication> submitApplication(JobApplication a) => _run(() async {
        final row = await _client
            .from('applications')
            .insert({
              'id': a.id,
              'user_id': _uid(),
              'job_id': a.jobId,
              'status': a.status.name,
              'submitted_at': a.submittedAt.toUtc().toIso8601String(),
              'data': a.toJson(includeLocal: false),
            })
            .select('*, job:jobs($_jobSelect)')
            .single();
        return _appFromRow(row);
      });

  @override
  Future<JobApplication> withdrawApplication(String id, {String? reason}) => _run(() async {
        final current = await _client.from('applications').select().eq('id', id).single();
        final app = _appFromRow(current);
        final updated = app.copyWith(
          status: ApplicationStatus.withdrawn,
          history: [...app.history, StatusEvent(status: ApplicationStatus.withdrawn, at: DateTime.now(), note: reason)],
        );
        final row = await _client
            .from('applications')
            .update({'status': 'withdrawn', 'data': updated.toJson(includeLocal: false)})
            .eq('id', id)
            .select('*, job:jobs($_jobSelect)')
            .single();
        return _appFromRow(row);
      });

  // ---- Notifications ---------------------------------------------------------

  @override
  Future<List<AppNotification>> fetchNotifications(String userId) => _run(() async {
        final rows = await _client.from('notifications').select().eq('user_id', userId).order('created_at', ascending: false).limit(200);
        return rows.map(AppNotification.fromJson).toList();
      });

  @override
  Future<void> markNotificationsRead(String userId, List<String> ids) => _run(() async {
        var q = _client.from('notifications').update({'read': true}).eq('user_id', userId);
        if (ids.isNotEmpty) q = q.inFilter('id', ids);
        await q;
      });

  @override
  Future<void> deleteNotification(String id) => _run(() async {
        await _client.from('notifications').delete().eq('id', id);
      });

  // ---- Saved -----------------------------------------------------------------

  @override
  Future<List<SavedJob>> fetchSavedJobs(String userId) => _run(() async {
        final rows = await _client.from('saved_jobs').select('*, job:jobs($_jobSelect)').eq('user_id', userId).order('saved_at', ascending: false);
        return rows.map((r) {
          final s = SavedJob.fromJson(r);
          final job = r['job'];
          return job is Map ? s.withJob(Job.fromJson(Map<String, dynamic>.from(job))) : s;
        }).toList();
      });

  @override
  Future<void> saveJob(SavedJob s) => _run(() async {
        await _client.from('saved_jobs').upsert({...s.toJson(), 'user_id': _uid()});
      });

  @override
  Future<void> unsaveJob(String userId, String jobId) => _run(() async {
        await _client.from('saved_jobs').delete().eq('user_id', userId).eq('job_id', jobId);
      });

  @override
  Future<List<JobAlert>> fetchAlerts(String userId) => _run(() async {
        final rows = await _client.from('job_alerts').select().eq('user_id', userId).order('created_at', ascending: false);
        return rows.map((r) => JobAlert.fromJson({...Map<String, dynamic>.from(r['data'] as Map), 'id': r['id'], 'user_id': r['user_id']})).toList();
      });

  @override
  Future<JobAlert> upsertAlert(JobAlert a) => _run(() async {
        await _client.from('job_alerts').upsert({
          'id': a.id,
          'user_id': _uid(),
          'data': a.toJson(),
          'created_at': a.createdAt.toUtc().toIso8601String(),
        });
        return a;
      });

  @override
  Future<void> deleteAlert(String id) => _run(() async {
        await _client.from('job_alerts').delete().eq('id', id);
      });
}

/// Runs a Supabase call and maps its errors to [AppException]s.
Future<T> guardSupabase<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on sb.AuthException catch (e) {
    throw AuthException(e.message);
  } on sb.PostgrestException catch (e) {
    if (e.code == 'PGRST116') throw const NotFoundException();
    throw ServerException('${e.message}${e.code == null ? '' : ' (${e.code})'}');
  } on sb.StorageException catch (e) {
    throw ServerException(e.message);
  } on AppException {
    rethrow;
  } catch (e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup') || s.contains('XMLHttpRequest')) {
      throw const NetworkException();
    }
    throw ServerException(s);
  }
}
