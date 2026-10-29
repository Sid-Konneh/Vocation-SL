import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../data/backend/supabase_backend.dart' show guardSupabase;
import '../../models/models.dart';
import 'employer_backend.dart';

class SupabaseEmployerBackend implements EmployerBackend {
  SupabaseEmployerBackend(this._client);
  final sb.SupabaseClient _client;

  static const _bucket = 'documents';
  static const _jobSelect = '*, company:companies(*)';

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<Company?> myCompany() => guardSupabase(() async {
        final uid = _uid();
        final rows = await _client.from('company_members').select('company:companies(*)').eq('user_id', uid).limit(1);
        if (rows.isNotEmpty && rows.first['company'] != null) {
          return Company.fromJson(Map<String, dynamic>.from(rows.first['company'] as Map));
        }
        // Fallback: a company this account created (owner) even if its
        // membership row is missing.
        final owned = await _client.from('companies').select().eq('owner_id', uid).order('created_at').limit(1);
        return owned.isEmpty ? null : Company.fromJson(owned.first);
      });

  @override
  Future<Company> registerCompany(Company draft) => guardSupabase(() async {
        // An account has one company: if it already has one (e.g. the form was
        // submitted twice), update that company instead of creating another.
        final existing = await myCompany();
        if (existing != null) {
          final updated = await _client.from('companies').update(draft.toEmployerJson()).eq('id', existing.id).select().single();
          return Company.fromJson(updated);
        }
        final row = await _client.from('companies').insert(draft.toEmployerJson()).select().single();
        return Company.fromJson(row);
      });

  @override
  Future<Company> updateCompany(Company company) => guardSupabase(() async {
        final row = await _client.from('companies').update(company.toEmployerJson()).eq('id', company.id).select().single();
        return Company.fromJson(row);
      });

  @override
  Future<Company> uploadLogo(Company company, Uint8List bytes, String fileName) => guardSupabase(() async {
        final ext = fileName.split('.').last.toLowerCase();
        final type = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
        // Stored under the uploader's own folder (logos/<user id>/...), which the
        // storage policy allows for any signed-in user, so a brand-new company
        // can add its logo straight away. A new file name each time means
        // browsers and CDNs never show a stale logo.
        final path = '${_uid()}/${company.id}-logo-${DateTime.now().millisecondsSinceEpoch}.${ext == 'jpeg' ? 'jpg' : ext}';
        await _client.storage.from('logos').uploadBinary(path, bytes, fileOptions: sb.FileOptions(contentType: type));
        final url = _client.storage.from('logos').getPublicUrl(path);
        final row = await _client.from('companies').update({'logo_url': url}).eq('id', company.id).select().single();
        return Company.fromJson(row);
      });

  @override
  Future<String> uploadJobAdvert(Uint8List bytes, String fileName) => guardSupabase(() async {
        var ext = fileName.split('.').last.toLowerCase();
        if (ext == 'jpeg') ext = 'jpg';
        final type = switch (ext) { 'pdf' => 'application/pdf', 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
        // Same folder rule as logos (job-adverts/<user id>/...); a new name
        // each time so a replaced advert is never served from cache.
        final path = '${_uid()}/${DateTime.now().millisecondsSinceEpoch}-advert.$ext';
        await _client.storage.from('job-adverts').uploadBinary(path, bytes, fileOptions: sb.FileOptions(contentType: type));
        return _client.storage.from('job-adverts').getPublicUrl(path);
      });

  @override
  Future<List<Job>> myJobs(String companyId) => guardSupabase(() async {
        final rows = await _client.from('jobs').select(_jobSelect).eq('company_id', companyId).order('updated_at', ascending: false);
        return rows.map(Job.fromJson).toList();
      });

  Map<String, dynamic> _jobFields(Job j, JobStatus status) => {
        'company_id': j.companyId,
        'title': j.title.trim(),
        'location': j.location,
        'employment_type': j.employmentType.name,
        'work_mode': j.workMode.name,
        'industry': j.industry.name,
        'experience_level': j.experienceLevel.name,
        'salary_min': j.salaryMin,
        'salary_max': j.salaryMax,
        'currency': j.currency,
        'salary_period': j.salaryPeriod,
        'deadline': j.deadline.toUtc().toIso8601String(),
        'about': j.about.trim(),
        'description': j.description.trim(),
        'responsibilities': j.responsibilities,
        'requirements': j.requirements,
        'preferred': j.preferred,
        'skills': j.skills,
        'benefits': j.benefits,
        'documents_requested': j.documentsRequested,
        'documents_note': j.documentsRequested ? j.documentsNote.trim() : '',
        'apply_url': j.applyUrl.trim(),
        'advert_url': j.advertUrl,
        'screening': j.screening.map((q) => q.toJson()).toList(),
        'status': status.name,
      };

  @override
  Future<Job> saveJob(Job job, {required JobStatus status}) => guardSupabase(() async {
        final fields = _jobFields(job, status);
        final row = job.id.isEmpty
            ? await _client.from('jobs').insert(fields).select(_jobSelect).single()
            : await _client.from('jobs').update(fields).eq('id', job.id).select(_jobSelect).single();
        return Job.fromJson(row);
      });

  @override
  Future<Job> setJobStatus(String jobId, JobStatus status) => guardSupabase(() async {
        final row = await _client.from('jobs').update({'status': status.name}).eq('id', jobId).select(_jobSelect).single();
        return Job.fromJson(row);
      });

  @override
  Future<void> deleteDraft(String jobId) => guardSupabase(() async {
        await _client.from('jobs').delete().eq('id', jobId).inFilter('status', ['draft', 'declined', 'rejected']);
      });

  JobApplication _appFromRow(Map<String, dynamic> row) {
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
  }

  @override
  Future<List<JobApplication>> applications(String companyId) => guardSupabase(() async {
        final rows = await _client
            .from('applications')
            .select('*, job:jobs!inner($_jobSelect)')
            .eq('job.company_id', companyId)
            .order('submitted_at', ascending: false);
        return rows.map(_appFromRow).toList();
      });

  @override
  Future<JobApplication> updateApplication(
    JobApplication application, {
    ApplicationStatus? status,
    String? employerMessage,
    DateTime? interviewAt,
    bool clearInterview = false,
  }) =>
      guardSupabase(() async {
        final data = application.toJson(includeLocal: false)
          ..['employer_message'] = employerMessage ?? application.employerMessage
          ..['interview_at'] = clearInterview ? null : (interviewAt ?? application.interviewAt)?.toUtc().toIso8601String();
        final row = await _client
            .from('applications')
            .update({'status': (status ?? application.status).name, 'data': data})
            .eq('id', application.id)
            .select('*, job:jobs($_jobSelect)')
            .single();
        return _appFromRow(row);
      });

  @override
  Future<AppUser?> applicantProfile(String userId) => guardSupabase(() async {
        final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
        if (row == null) return null;
        final data = Map<String, dynamic>.from(row['data'] as Map? ?? const {});
        return AppUser.fromJson({...data, 'id': userId, 'email': row['email'] ?? data['email'] ?? '', 'full_name': data['full_name'] ?? row['full_name'] ?? ''});
      });

  @override
  Future<List<Invoice>> invoices(String companyId) => guardSupabase(() async {
        final rows = await _client.from('invoices').select().eq('company_id', companyId).neq('status', 'draft').order('created_at', ascending: false);
        return rows.map(Invoice.fromJson).toList();
      });

  @override
  Future<String> documentUrl(String storagePath) =>
      guardSupabase(() => _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 30));

  @override
  Future<LaunchOffer> launchOffer() async {
    try {
      final r = await _client.rpc('launch_offer_status');
      return r is Map ? LaunchOffer.fromJson(Map<String, dynamic>.from(r)) : LaunchOffer.none;
    } catch (_) {
      return LaunchOffer.none; // function not installed yet
    }
  }

  @override
  Future<String> requestFeatured(String jobId) =>
      guardSupabase(() async => '${await _client.rpc('request_featured', params: {'p_job': jobId})}');

  @override
  Future<List<TeamMember>> team() => guardSupabase(() async {
        final rows = await _client.rpc('team_members') as List;
        return [for (final r in rows) TeamMember.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<void> addTeamMember(String email) => guardSupabase(() => _client.rpc('add_team_member', params: {'p_email': email.trim()}));

  @override
  Future<void> removeTeamMember(String userId) => guardSupabase(() => _client.rpc('remove_team_member', params: {'p_user': userId}));
}