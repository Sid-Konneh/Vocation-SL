import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../data/backend/supabase_backend.dart' show guardSupabase;
import '../../models/models.dart';
import 'admin_backend.dart';

class SupabaseAdminBackend implements AdminBackend {
  SupabaseAdminBackend(this._client);
  final sb.SupabaseClient _client;

  /// Lists are capped; the dashboard searches and filters within them.
  static const _cap = 1000;

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<AdminRole?> myRole() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client.from('admins').select('role').eq('user_id', uid).maybeSingle();
      return AdminRole.fromName(row?['role']);
    } catch (_) {
      return null; // admin tables not installed, or offline
    }
  }

  @override
  Future<AdminStats> stats() => guardSupabase(() async {
        final r = await _client.rpc('admin_stats');
        return AdminStats.fromJson(Map<String, dynamic>.from(r as Map));
      });

  // ---- Jobs ------------------------------------------------------------------

  @override
  Future<List<Job>> jobs() => guardSupabase(() async {
        final rows = await _client.from('jobs').select('*, company:companies(*)').order('updated_at', ascending: false).limit(_cap);
        return rows.map(Job.fromJson).toList();
      });

  @override
  Future<void> setJobStatus(String jobId, JobStatus status, {String note = ''}) => guardSupabase(() async => _client.from('jobs').update({
        'status': status.name,
        if (status == JobStatus.declined || status == JobStatus.rejected) 'review_note': note,
      }).eq('id', jobId));

  @override
  Future<void> setJobFeatured(String jobId, bool featured) =>
      guardSupabase(() async => _client.from('jobs').update({'featured': featured}).eq('id', jobId));

  @override
  Future<void> deleteJob(String jobId) => guardSupabase(() async => _client.from('jobs').delete().eq('id', jobId));

  // ---- Companies ---------------------------------------------------------------

  @override
  Future<List<AdminCompany>> companies() => guardSupabase(() async {
        final rows = await _client
            .from('companies')
            .select('*, members:company_members(count), jobs(count)')
            .order('created_at', ascending: false)
            .limit(_cap);
        return rows.map(AdminCompany.fromJson).toList();
      });

  @override
  Future<void> setCompanyStatus(String companyId, CompanyStatus status) =>
      guardSupabase(() async => _client.from('companies').update({'status': status.name}).eq('id', companyId));

  @override
  Future<void> setCompanyVerified(String companyId, bool verified) =>
      guardSupabase(() async => _client.from('companies').update({'verified': verified}).eq('id', companyId));

  // ---- Users -------------------------------------------------------------------

  @override
  Future<List<AdminUser>> users() => guardSupabase(() async {
        final rows = await _client.from('profiles').select().order('created_at', ascending: false).limit(_cap);
        return rows.map(AdminUser.fromJson).toList();
      });

  @override
  Future<void> setUserSuspended(String userId, bool suspended, {String? reason}) => guardSupabase(() async {
        await _client.from('profiles').update({'suspended': suspended, 'suspended_reason': suspended ? reason : null}).eq('id', userId);
      });

  @override
  Future<void> deleteUser(String userId) => guardSupabase(() async => _client.rpc('admin_delete_user', params: {'target': userId}));

  @override
  Future<UserLoginInfo?> userLogin(String userId) => guardSupabase(() async {
        final r = await _client.rpc('admin_user_login', params: {'target': userId});
        return r == null ? null : UserLoginInfo.fromJson(Map<String, dynamic>.from(r as Map));
      });

  // ---- Applications ---------------------------------------------------------------

  @override
  Future<List<JobApplication>> applications() => guardSupabase(() async {
        final rows = await _client
            .from('applications')
            .select('*, job:jobs(*, company:companies(*))')
            .order('submitted_at', ascending: false)
            .limit(_cap);
        return rows.map((row) {
          final data = Map<String, dynamic>.from(row['data'] as Map? ?? const {});
          final app = JobApplication.fromJson({
            ...data,
            'id': row['id'],
            'status': row['status'],
            'user_id': row['user_id'],
            'job_id': row['job_id'],
            'submitted_at': row['submitted_at'] ?? data['submitted_at'],
          });
          final job = row['job'];
          return job is Map ? app.copyWith(job: () => Job.fromJson(Map<String, dynamic>.from(job))) : app;
        }).toList();
      });

  @override
  Future<String> documentUrl(String storagePath) =>
      guardSupabase(() => _client.storage.from('documents').createSignedUrl(storagePath, 60 * 30));

  // ---- Reports -------------------------------------------------------------------

  @override
  Future<List<Report>> reports() => guardSupabase(() async {
        final rows = await _client.from('reports').select().order('created_at', ascending: false).limit(_cap);
        return rows.map(Report.fromJson).toList();
      });

  @override
  Future<void> updateReport(String reportId, ReportStatus status, {String note = ''}) => guardSupabase(() async {
        await _client.from('reports').update({
          'status': status.name,
          'admin_note': note,
          if (!status.isOpen) 'resolved_at': DateTime.now().toUtc().toIso8601String(),
          if (!status.isOpen) 'resolved_by': _uid(),
        }).eq('id', reportId);
      });

  // ---- Content -------------------------------------------------------------------

  @override
  Future<List<Announcement>> announcements() => guardSupabase(() async {
        final rows = await _client.from('announcements').select().order('created_at', ascending: false);
        return rows.map(Announcement.fromJson).toList();
      });

  @override
  Future<void> saveAnnouncement(Announcement a) => guardSupabase(() async {
        final data = {...a.toJson(), 'updated_at': DateTime.now().toUtc().toIso8601String()};
        if (a.id.isEmpty) {
          await _client.from('announcements').insert(data);
        } else {
          await _client.from('announcements').update(data).eq('id', a.id);
        }
      });

  @override
  Future<void> deleteAnnouncement(String id) => guardSupabase(() async => _client.from('announcements').delete().eq('id', id));

  @override
  Future<List<SitePage>> pages() => guardSupabase(() async {
        final rows = await _client.from('site_pages').select().order('slug');
        return rows.map(SitePage.fromJson).toList();
      });

  @override
  Future<void> savePage(String slug, String title, String body) => guardSupabase(() async {
        await _client.from('site_pages').upsert({
          'slug': slug,
          'title': title,
          'body': body,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': _uid(),
        });
      });

  // ---- Settings ------------------------------------------------------------------

  @override
  Future<PlatformSettings> settings() => guardSupabase(() async {
        final rows = await _client.from('platform_settings').select();
        return PlatformSettings.fromRows(List<Map<String, dynamic>>.from(rows));
      });

  @override
  Future<void> saveSettings(PlatformSettings s) => guardSupabase(() async {
        final uid = _uid();
        final now = DateTime.now().toUtc().toIso8601String();
        await _client.from('platform_settings').upsert([for (final r in s.toRows()) {...r, 'updated_at': now, 'updated_by': uid}]);
      });

  // ---- Team ----------------------------------------------------------------------

  @override
  Future<List<AdminMember>> team() => guardSupabase(() async {
        final rows = await _client.from('admins').select().order('created_at');
        if (rows.isEmpty) return <AdminMember>[];
        final ids = rows.map((r) => r['user_id'] as String).toList();
        final profiles = await _client.from('profiles').select('id, email, full_name').inFilter('id', ids);
        final byId = {for (final p in profiles) p['id'] as String: p};
        return rows.map((r) => AdminMember.fromJson({...r, 'profile': byId[r['user_id']]})).toList();
      });

  @override
  Future<void> addMember(String email, AdminRole role) => guardSupabase(() async {
        final p = await _client.from('profiles').select('id').ilike('email', email.trim()).maybeSingle();
        if (p == null) throw const ValidationException('No account uses that email. Ask them to sign up first.');
        await _client.from('admins').upsert({'user_id': p['id'], 'role': role.name});
      });

  @override
  Future<void> setMemberRole(String userId, AdminRole role) =>
      guardSupabase(() async => _client.from('admins').update({'role': role.name}).eq('user_id', userId));

  @override
  Future<void> removeMember(String userId) => guardSupabase(() async => _client.from('admins').delete().eq('user_id', userId));

  // ---- Invoices ------------------------------------------------------------------

  @override
  Future<List<Invoice>> invoices() => guardSupabase(() async {
        final rows = await _client.from('invoices').select().order('created_at', ascending: false).limit(_cap);
        return rows.map(Invoice.fromJson).toList();
      });

  @override
  Future<void> saveInvoice(Invoice invoice) =>
      guardSupabase(() async => _client.from('invoices').update(invoice.toJson()).eq('id', invoice.id));

  @override
  Future<void> deleteInvoice(String id) => guardSupabase(() async => _client.from('invoices').delete().eq('id', id));

  // ---- Activity ------------------------------------------------------------------

  @override
  Future<List<AuditEntry>> activity({int limit = 300}) => guardSupabase(() async {
        final rows = await _client.from('audit_log').select().order('created_at', ascending: false).limit(limit);
        return rows.map(AuditEntry.fromJson).toList();
      });
}
