import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../providers/referral_providers.dart';
import '../../services/export_service.dart';
import '../../widgets/common.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

/// One month of growth figures.
class TractionMonth {
  TractionMonth(this.month);
  final DateTime month;
  int seekers = 0;
  int employers = 0;
  int companies = 0;
  int jobs = 0;
  int applications = 0;
  int hires = 0;
  int referrals = 0;
  double revenue = 0;
}

/// Real usage figures for investors, partners and the business plan:
/// totals, month-by-month growth and reach. Nothing here is estimated.
class TractionReport {
  TractionReport({
    required this.asOf,
    required this.months,
    required this.users,
    required this.seekers,
    required this.employerUsers,
    required this.activeUsers30d,
    required this.companies,
    required this.approvedCompanies,
    required this.jobsPosted,
    required this.liveJobs,
    required this.applications,
    required this.hires,
    required this.interviews,
    required this.revenuePaid,
    required this.freePostings,
    required this.referrals,
    required this.referralsQualified,
    required this.jobDistricts,
    required this.seekerDistricts,
    required this.seekersOutsideWestern,
    required this.seekersWithCv,
  });

  final DateTime asOf;
  final List<TractionMonth> months;
  final int users, seekers, employerUsers, activeUsers30d;
  final int companies, approvedCompanies, jobsPosted, liveJobs;
  final int applications, hires, interviews;
  final double revenuePaid;
  final int freePostings, referrals, referralsQualified;
  final int jobDistricts, seekerDistricts, seekersOutsideWestern, seekersWithCv;

  double get applicationsPerJob => jobsPosted == 0 ? 0 : applications / jobsPosted;

  static bool _western(String location) {
    final l = location.toLowerCase();
    return l.contains('freetown') || l.contains('western') || l.contains('waterloo') || l.contains('lumley') || l.contains('wellington');
  }

  factory TractionReport.compute({
    required List<AdminUser> users,
    required List<AdminCompany> companies,
    required List<Job> jobs,
    required List<JobApplication> applications,
    required List<Invoice> invoices,
    required List<Referral> referrals,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final months = [for (var i = 11; i >= 0; i--) TractionMonth(DateTime(today.year, today.month - i))];
    TractionMonth? bucket(DateTime? d) =>
        d == null ? null : months.where((m) => m.month.year == d.year && m.month.month == d.month).firstOrNull;

    for (final u in users) {
      final m = bucket(u.createdAt);
      if (m == null) continue;
      if (u.role == 'employer') {
        m.employers++;
      } else {
        m.seekers++;
      }
    }
    for (final c in companies) {
      bucket(c.createdAt)?.companies++;
    }
    final posted = jobs.where((j) => j.status == JobStatus.published || j.status == JobStatus.closed).toList();
    for (final j in posted) {
      bucket(j.postedAt)?.jobs++;
    }
    for (final a in applications) {
      bucket(a.submittedAt)?.applications++;
    }
    final hired = applications.where((a) => a.status == ApplicationStatus.hired).toList();
    for (final a in hired) {
      bucket(a.updatedAt)?.hires++;
    }
    final paid = invoices.where((i) => i.status == InvoiceStatus.paid && !i.launchFree).toList();
    for (final i in paid) {
      bucket(i.paidAt)?.revenue += i.taxable;
    }
    for (final r in referrals) {
      bucket(r.createdAt)?.referrals++;
    }

    final seekerProfiles = users.where((u) => u.role != 'employer').toList();
    final seekerLocations = seekerProfiles.map((u) => u.location.trim()).where((l) => l.isNotEmpty).toList();
    return TractionReport(
      asOf: today,
      months: months,
      users: users.length,
      seekers: seekerProfiles.length,
      employerUsers: users.where((u) => u.role == 'employer').length,
      activeUsers30d: users.where((u) => u.lastSeenAt != null && today.difference(u.lastSeenAt!).inDays <= 30).length,
      companies: companies.length,
      approvedCompanies: companies.where((c) => c.company.isApproved).length,
      jobsPosted: posted.length,
      liveJobs: jobs.where((j) => j.status == JobStatus.published && !j.isClosed).length,
      applications: applications.length,
      hires: hired.length,
      interviews: applications.where((a) => a.interviewAt != null || a.status == ApplicationStatus.interview).length,
      revenuePaid: paid.fold(0, (s, i) => s + i.taxable),
      freePostings: invoices.where((i) => i.launchFree).length,
      referrals: referrals.where((r) => r.status != ReferralStatus.rejected).length,
      referralsQualified: referrals.where((r) => r.status == ReferralStatus.qualified || r.status == ReferralStatus.rewarded).length,
      jobDistricts: posted.map((j) => j.location).toSet().length,
      seekerDistricts: seekerLocations.toSet().length,
      seekersOutsideWestern: seekerLocations.where((l) => !_western(l)).length,
      seekersWithCv: seekerProfiles.where((u) => u.profileData['resume'] != null).length,
    );
  }

  /// Plain-language summary to paste into the pitch deck or plan.
  String summary() {
    final d = DateFormat('d MMMM yyyy').format(asOf);
    final n = NumberFormat('#,##0');
    return 'Vocation SL traction as of $d (from the live admin dashboard):\n'
        '• ${n.format(seekers)} job seekers and ${n.format(companies)} employers registered (${n.format(approvedCompanies)} approved)\n'
        '• ${n.format(jobsPosted)} jobs posted in ${n.format(jobDistricts)} districts/towns; ${n.format(liveJobs)} live now\n'
        '• ${n.format(applications)} applications (${applicationsPerJob.toStringAsFixed(1)} per job), ${n.format(interviews)} interviews, ${n.format(hires)} hires recorded\n'
        '• ${n.format(activeUsers30d)} people active in the last 30 days\n'
        '• SLE ${n.format(revenuePaid.round())} revenue received (excl. GST); ${n.format(freePostings)} free launch-offer postings\n'
        '• ${n.format(referrals)} employers referred by job seekers (${n.format(referralsQualified)} with jobs live)';
  }
}

final tractionProvider = FutureProvider.autoDispose<TractionReport>((ref) async {
  final results = await Future.wait([
    ref.watch(adminUsersProvider.future),
    ref.watch(adminCompaniesProvider.future),
    ref.watch(adminJobsProvider.future),
    ref.watch(adminApplicationsProvider.future),
    ref.watch(adminInvoicesProvider.future),
    ref.watch(adminReferralsProvider.future).catchError((_) => <Referral>[]),
  ]);
  return TractionReport.compute(
    users: results[0] as List<AdminUser>,
    companies: results[1] as List<AdminCompany>,
    jobs: results[2] as List<Job>,
    applications: results[3] as List<JobApplication>,
    invoices: results[4] as List<Invoice>,
    referrals: results[5] as List<Referral>,
  );
});

class AdminTractionScreen extends ConsumerWidget {
  const AdminTractionScreen({super.key});

  void _download(TractionReport t) {
    final f = DateFormat('MMM yyyy');
    ExportService.save(
      'vocation-sl-traction-${DateFormat('yyyy-MM-dd').format(t.asOf)}.csv',
      ExportService.csv(
        ['Month', 'New job seekers', 'New employer accounts', 'New companies', 'Jobs posted', 'Applications', 'Hires', 'Referrals', 'Revenue received excl GST (SLE)'],
        [
          for (final m in t.months)
            [f.format(m.month), m.seekers, m.employers, m.companies, m.jobs, m.applications, m.hires, m.referrals, m.revenue.toStringAsFixed(0)],
          ['Total (all time)', t.seekers, t.employerUsers, t.companies, t.jobsPosted, t.applications, t.hires, t.referrals, t.revenuePaid.toStringAsFixed(0)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tractionProvider);
    return EmployerPage(
      title: 'Traction',
      subtitle: 'Real growth figures for the pitch deck, business plan and partners. Nothing here is estimated.',
      onRefresh: () async {
        for (final p in [adminUsersProvider, adminCompaniesProvider, adminJobsProvider, adminApplicationsProvider, adminInvoicesProvider, adminReferralsProvider]) {
          ref.invalidate(p);
        }
      },
      actions: [
        if (async.hasValue) ...[
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: async.value!.summary()));
              if (context.mounted) showSnack(context, 'Summary copied. Paste it into the deck or plan.');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy summary'),
          ),
          FilledButton.icon(
            onPressed: () => _download(async.value!),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Download spreadsheet'),
          ),
        ],
      ],
      children: [
        AdminAsync<TractionReport>(
          value: async,
          onRetry: () => ref.invalidate(tractionProvider),
          builder: (t) {
            final last = t.months.last;
            final prev = t.months[t.months.length - 2];
            String growth(int now, int before) => before == 0 ? (now == 0 ? '' : 'new this month') : '${now >= before ? '+' : ''}${((now - before) / before * 100).round()}% vs last month';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('As of ${Fmt.date(t.asOf)}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 10),
              StatGrid(children: [
                StatTile(label: 'Job seekers', value: Fmt.money(t.seekers), detail: '${last.seekers} new this month · ${growth(last.seekers, prev.seekers)}', icon: Icons.person_search_outlined),
                StatTile(label: 'Employers', value: Fmt.money(t.companies), detail: '${t.approvedCompanies} approved · ${last.companies} new this month', icon: Icons.business_outlined),
                StatTile(label: 'Jobs posted', value: Fmt.money(t.jobsPosted), detail: '${t.liveJobs} live now · ${t.jobDistricts} districts/towns', icon: Icons.work_outline_rounded),
                StatTile(label: 'Applications', value: Fmt.money(t.applications), detail: '${t.applicationsPerJob.toStringAsFixed(1)} per job · ${growth(last.applications, prev.applications)}', icon: Icons.inbox_outlined),
                StatTile(label: 'Interviews', value: Fmt.money(t.interviews), icon: Icons.event_available_outlined),
                StatTile(label: 'Hires recorded', value: Fmt.money(t.hires), detail: 'Marked "Hired" by employers', icon: Icons.verified_outlined),
                StatTile(label: 'Active in last 30 days', value: Fmt.money(t.activeUsers30d), detail: 'of ${Fmt.money(t.users)} accounts', icon: Icons.bolt_outlined),
                StatTile(label: 'Revenue received', value: 'SLE ${Fmt.money(t.revenuePaid.round())}', detail: 'Excl. GST · ${t.freePostings} free launch postings', icon: Icons.payments_outlined),
                StatTile(label: 'Referred employers', value: Fmt.money(t.referrals), detail: '${t.referralsQualified} with jobs live', icon: Icons.handshake_outlined),
              ]),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Reach and inclusion',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InfoRow(icon: Icons.map_outlined, label: 'Job seekers live in', value: '${t.seekerDistricts} districts/towns'),
                  InfoRow(icon: Icons.near_me_outlined, label: 'Job seekers outside the Western Area', value: '${Fmt.money(t.seekersOutsideWestern)} (of those who gave a location)'),
                  InfoRow(icon: Icons.description_outlined, label: 'Job seekers with a CV on file', value: Fmt.money(t.seekersWithCv)),
                ]),
              ),
              const SizedBox(height: 16),
              SectionCard(title: 'Month by month (last 12 months)', child: _MonthTable(months: t.months)),
              const SizedBox(height: 8),
              Text('Hires count only applications an employer marked "Hired". Revenue counts paid invoices, excluding GST and free launch postings.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]);
          },
        ),
      ],
    );
  }
}

class _MonthTable extends StatelessWidget {
  const _MonthTable({required this.months});
  final List<TractionMonth> months;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('MMM yy');
    final maxApps = months.fold<int>(1, (m, x) => x.applications > m ? x.applications : m);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 44,
        columnSpacing: 22,
        columns: const [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Job seekers'), numeric: true),
          DataColumn(label: Text('Companies'), numeric: true),
          DataColumn(label: Text('Jobs'), numeric: true),
          DataColumn(label: Text('Applications'), numeric: true),
          DataColumn(label: Text('')),
          DataColumn(label: Text('Hires'), numeric: true),
          DataColumn(label: Text('Referrals'), numeric: true),
          DataColumn(label: Text('Revenue (SLE)'), numeric: true),
        ],
        rows: [
          for (final m in months.reversed)
            DataRow(cells: [
              DataCell(Text(f.format(m.month))),
              DataCell(Text('${m.seekers}')),
              DataCell(Text('${m.companies}')),
              DataCell(Text('${m.jobs}')),
              DataCell(Text('${m.applications}')),
              DataCell(SizedBox(
                width: 90,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: m.applications / maxApps, minHeight: 8, color: AppColors.green, backgroundColor: context.palette.border),
                ),
              )),
              DataCell(Text('${m.hires}')),
              DataCell(Text('${m.referrals}')),
              DataCell(Text(Fmt.money(m.revenue.round()))),
            ]),
        ],
      ),
    );
  }
}
