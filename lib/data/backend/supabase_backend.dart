import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

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

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on sb.AuthException catch (e) {
      throw AuthException(e.message);
    } on sb.PostgrestException catch (e) {
      if (e.code == 'PGRST116') throw const NotFoundException();
      throw ServerException(e.message);
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

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  // ---- Auth ------------------------------------------------------------------

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<String> signIn({required String email, required String password}) => _run(() async {
        final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
        return res.user!.id;
      });

  @override
  Future<String> signUp({required String fullName, required String email, required String password}) => _run(() async {
        final res = await _client.auth.signUp(email: email.trim(), password: password, data: {'full_name': fullName.trim()});
        final user = res.user;
        if (user == null) throw const AuthException('Check your email to confirm your account, then sign in.');
        if (res.session == null) throw const AuthException('Check your email to confirm your account, then sign in.');
        return user.id;
      });

  @override
  Future<void> signOut() => _run(() => _client.auth.signOut());

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

  // ---- Profile ---------------------------------------------------------------

  @override
  Future<AppUser> fetchUser(String userId) => _run(() async {
        final row = await _client.from('profiles').select().eq('id', userId).single();
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
