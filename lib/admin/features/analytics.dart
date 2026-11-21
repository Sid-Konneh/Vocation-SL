import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/charts.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

final _n = NumberFormat.decimalPattern('en');

int _i(Object? v) => (v as num?)?.round() ?? 0;
String _num(Object? v) => _n.format(_i(v));
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _l(Object? v) => v is List ? [for (final e in v) _m(e)] : const [];

/// "x of y (z%)" share, or a dash when there's nothing to divide by.
String _pct(num part, num whole) => whole <= 0 ? '—' : '${(100 * part / whole).toStringAsFixed(part / whole < 0.1 ? 1 : 0)}%';

String _industry(String raw) => Industry.values.where((i) => i.name == raw).map((i) => i.label).firstOrNull ?? raw;
String _status(String raw) => ApplicationStatus.values.where((s) => s.name == raw).map((s) => s.label).firstOrNull ?? raw;

String _ago(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return 'Never';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return '${math.max(1, diff.inMinutes)} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 14) return '${diff.inDays} days ago';
  return Fmt.dateShort(d);
}

Widget _heading(BuildContext context, String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(t, style: context.text.titleLarge)),
        if (sub != null) Text(sub, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
      ]),
    );

Widget _twoUp(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: w)]);
      }
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += 2) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 16),
              Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
            ]),
          ),
        ));
      }
      return Column(children: rows);
    });

/// Admin → Analytics: in-depth, live figures from admin_analytics().
class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAnalyticsProvider);
    return EmployerPage(
      title: 'Analytics',
      subtitle: 'Live figures from the database: who signs up, who comes back, where the jobs and job seekers are, and how jobs perform.',
      onRefresh: () async => ref.invalidate(adminAnalyticsProvider),
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(adminAnalyticsProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
      ],
      children: [
        AdminAsync<Map<String, dynamic>>(
          value: async,
          onRetry: () => ref.invalidate(adminAnalyticsProvider),
          builder: (a) => _Body(a: a),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final seekers = _m(a['seekers']);
    final funnel = _m(a['funnel']);
    final profile = _m(a['profile']);
    final jt = _m(a['job_totals']);
    final apps = _m(a['applications']);
    final emp = _m(a['employers']);
    final notif = _m(a['notifications']);
    final emails = _m(a['emails']);
    final rev = _m(a['revenue']);
    final total = _i(seekers['total']);
    final generated = DateTime.tryParse('${a['generated_at'] ?? ''}')?.toLocal();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (generated != null)
        Text('Updated ${Fmt.dateTime(generated)}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),

      // ---- Job seekers ----------------------------------------------------
      _heading(context, 'Job seekers', '"Came back" compares the last time someone opened the app with when they signed up.'),
      StatGrid(children: [
        StatTile(label: 'Job seekers', value: _num(total), detail: '${_num(seekers['new_7d'])} new this week', icon: Icons.people_outline_rounded),
        StatTile(label: 'New in 30 days', value: _num(seekers['new_30d']), icon: Icons.person_add_alt_rounded),
        StatTile(label: 'Active in 7 days', value: _num(seekers['active_7d']), detail: '${_num(seekers['active_30d'])} in 30 days', icon: Icons.bolt_rounded),
        StatTile(
          label: 'Came back after day 1',
          value: _pct(_i(seekers['returned_after_1d']), total),
          detail: '${_num(seekers['returned_after_1d'])} people',
          icon: Icons.replay_rounded,
          attention: total > 0 && _i(seekers['returned_after_1d']) / total < 0.2,
        ),
        StatTile(label: 'Came back after a week', value: _pct(_i(seekers['returned_after_7d']), total), detail: '${_num(seekers['returned_after_7d'])} people', icon: Icons.event_repeat_rounded),
      ]),
      const SizedBox(height: 16),
      _twoUp([
        SectionCard(
          title: 'Journey from sign-up to hire',
          child: _Funnel(steps: [
            ('Signed up', _i(funnel['signed_up'])),
            ('District and headline added', _i(funnel['basics'])),
            ('CV uploaded', _i(funnel['cv'])),
            ('Applied for a job', _i(funnel['applied'])),
            ('Shortlisted or further', _i(funnel['shortlisted'])),
            ('Interviewed', _i(funnel['interviewed'])),
            ('Hired', _i(funnel['hired'])),
          ]),
        ),
        SectionCard(
          title: 'Profile completeness',
          child: _ShareBars(total: total, items: [
            ('District', _i(profile['location'])),
            ('Phone', _i(profile['phone'])),
            ('Headline', _i(profile['headline'])),
            ('CV', _i(profile['cv'])),
            ('Education', _i(profile['education'])),
            ('Work experience', _i(profile['experience'])),
            ('Skills', _i(profile['skills'])),
            ('Photo', _i(profile['photo'])),
            ('Let employers find me', _i(profile['discoverable'])),
            ('Job alert set', _i(profile['job_alert'])),
            ('Push notifications', _i(profile['push'])),
            ('Job emails on', _i(profile['job_emails'])),
          ]),
        ),
      ]),

      // ---- Weekly trend ---------------------------------------------------
      _heading(context, 'Week by week', 'The last 12 weeks, Monday to Sunday.'),
      _WeeklyTable(rows: _l(a['weekly'])),

      // ---- Where ----------------------------------------------------------
      _heading(context, 'Job seekers and jobs by district', 'Districts with many job seekers and no live jobs are where to find employers next.'),
      _DistrictTable(rows: _l(a['districts'])),
      const SizedBox(height: 16),
      SectionCard(title: 'Jobs by industry', child: _IndustryTable(rows: _l(a['industries']))),

      // ---- Jobs -----------------------------------------------------------
      _heading(context, 'Live jobs', '"Strong fit" counts job seekers whose profile closely matches the job (AI matching). It is a guide only.'),
      StatGrid(children: [
        StatTile(label: 'Live jobs', value: _num(jt['live']), detail: '${_num(jt['pending_review'])} awaiting review', icon: Icons.work_outline_rounded),
        StatTile(
          label: 'Deadline passed, still live',
          value: _num(jt['expired_still_live']),
          detail: 'Close them or ask to extend',
          icon: Icons.event_busy_rounded,
          attention: _i(jt['expired_still_live']) > 0,
        ),
        StatTile(label: 'Closing in 7 days', value: _num(jt['closing_7d']), detail: 'Offer an extension', icon: Icons.schedule_rounded),
        StatTile(label: 'No salary shown', value: _num(jt['no_salary']), detail: 'of ${_num(jt['live'])} live jobs', icon: Icons.payments_outlined),
        StatTile(
          label: 'View → apply (in app)',
          value: _pct(_i(jt['in_app_applications']), _i(jt['in_app_views'])),
          detail: '${_num(jt['in_app_applications'])} applications',
          icon: Icons.ads_click_rounded,
        ),
        StatTile(
          label: 'View → apply tap (own link)',
          value: _pct(_i(jt['external_clicks']), _i(jt['external_views'])),
          detail: '${_num(jt['external_applied'])} said they applied',
          icon: Icons.open_in_new_rounded,
        ),
      ]),
      const SizedBox(height: 16),
      _JobsTable(rows: _l(a['jobs'])),

      // ---- Applications ---------------------------------------------------
      _heading(context, 'Applications'),
      StatGrid(children: [
        StatTile(label: 'Applications', value: _num(apps['total']), icon: Icons.assignment_outlined),
        StatTile(
          label: 'Unopened for 7+ days',
          value: _num(apps['untouched_7d']),
          detail: 'Remind the employer',
          icon: Icons.mark_email_unread_outlined,
          attention: _i(apps['untouched_7d']) > 0,
        ),
        StatTile(
          label: 'Employer first reply',
          value: apps['median_first_reply_hours'] == null ? '—' : '${(apps['median_first_reply_hours'] as num).toStringAsFixed(1)} h',
          detail: 'median, ${_num(apps['replied'])} replied',
          icon: Icons.quickreply_outlined,
        ),
        StatTile(label: 'Saved, not applied', value: _num(apps['saved_not_applied']), detail: 'Jobs saved by job seekers', icon: Icons.bookmark_border_rounded),
        StatTile(label: 'Messages in 30 days', value: _num(apps['messages_30d']), icon: Icons.chat_bubble_outline_rounded),
      ]),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Applications by stage',
        child: RankedBars(items: [
          for (final e in (_m(apps['by_status']).entries.toList()..sort((x, y) => _i(y.value).compareTo(_i(x.value)))))
            (label: _status(e.key), count: _i(e.value)),
        ]),
      ),

      // ---- Employers ------------------------------------------------------
      _heading(context, 'Employers'),
      StatGrid(children: [
        StatTile(label: 'Employer accounts', value: _num(emp['accounts']), icon: Icons.badge_outlined),
        StatTile(
          label: 'Signed up, no company',
          value: _num(emp['no_company']),
          detail: 'Call them to finish set-up',
          icon: Icons.domain_disabled_outlined,
          attention: _i(emp['no_company']) > 0,
        ),
        StatTile(label: 'Companies', value: _num(emp['companies']), detail: '${_num(emp['with_jobs'])} have posted', icon: Icons.business_outlined),
        StatTile(label: 'With live jobs', value: _num(emp['with_live_jobs']), icon: Icons.storefront_outlined),
        StatTile(label: 'Employers active in 7 days', value: _num(emp['active_7d']), icon: Icons.bolt_rounded),
      ]),
      const SizedBox(height: 16),
      _CompanyTable(rows: _l(emp['list'])),

      // ---- Reach and revenue ---------------------------------------------
      _heading(context, 'Reach and revenue'),
      _twoUp([
        SectionCard(
          title: 'Notifications and emails',
          child: Column(children: [
            _Row('Notifications sent (30 days)', _num(notif['sent_30d'])),
            _Row('Not opened', '${_num(notif['unread_30d'])} (${_pct(_i(notif['unread_30d']), _i(notif['sent_30d']))})'),
            _Row('Push devices', _m(notif['push_devices']).entries.map((e) => '${e.key} ${_num(e.value)}').join(' · ')),
            _Row('Job emails sent (7 / 30 days)', '${_num(emails['sent_7d'])} / ${_num(emails['sent_30d'])}'),
            _Row('Job emails failed (7 / 30 days)', '${_num(emails['failed_7d'])} / ${_num(emails['failed_30d'])}'),
            _Row('Last job email sent', _ago(emails['last_sent'])),
            _Row('Job emails waiting', _num(emails['waiting'])),
            _Row('Turned off job emails', _num(emails['unsubscribed'])),
            _Row('Last employer weekly report', _ago(emails['employer_reports_last'])),
          ]),
        ),
        SectionCard(
          title: 'Invoices and referrals',
          child: Column(children: [
            _Row('Received (paid, incl. GST)', 'SLE ${_num(rev['paid_total'])}'),
            _Row('Issued, not yet paid', 'SLE ${_num(rev['unpaid_total'])}'),
            _Row('Drafts to issue', 'SLE ${_num(rev['draft_total'])}'),
            _Row('Free postings (launch offer and free employers)', _num(rev['free_postings'])),
            for (final e in _m(rev['by_status']).entries) _Row('Invoices: ${e.key}', '${_num(_m(e.value)['count'])} · SLE ${_num(_m(e.value)['total'])}'),
            for (final e in _m(a['referrals']).entries) _Row('Referrals: ${e.key}', _num(e.value)),
          ]),
        ),
      ]),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
          const SizedBox(width: 12),
          Text(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}

/// Steps of a funnel: a bar per step, with the count and the share of the first step.
class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});
  final List<(String, int)> steps;

  @override
  Widget build(BuildContext context) {
    final first = steps.isEmpty ? 0 : steps.first.$2;
    final color = chartColor(context);
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(steps[i].$1, style: context.text.bodyMedium)),
              Text('${_num(steps[i].$2)}  ', style: context.text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              SizedBox(
                width: 52,
                child: Text(_pct(steps[i].$2, first), textAlign: TextAlign.right, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ),
            ]),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 10,
                  width: math.max(3.0, first <= 0 ? 3.0 : c.maxWidth * steps[i].$2 / first),
                  decoration: BoxDecoration(color: color.withValues(alpha: 1 - 0.1 * i), borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
            if (i > 0 && steps[i - 1].$2 > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${_pct(steps[i].$2, steps[i - 1].$2)} of the step before',
                    style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
              ),
          ]),
        ),
    ]);
  }
}

/// Share of all job seekers with each profile part, as bars out of 100%.
class _ShareBars extends StatelessWidget {
  const _ShareBars({required this.total, required this.items});
  final int total;
  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    final color = chartColor(context);
    return Column(children: [
      for (final (label, count) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: '$label: ${_num(count)} of ${_num(total)}',
            child: Row(children: [
              SizedBox(width: 150, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
              Expanded(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(4)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: total <= 0 ? 0 : (count / total).clamp(0.0, 1.0),
                    child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(_pct(count, total), textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _WeeklyTable extends StatelessWidget {
  const _WeeklyTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => TableCard(
        columns: const [
          DataColumn(label: Text('Week of')),
          DataColumn(label: Text('New job seekers'), numeric: true),
          DataColumn(label: Text('Came back next day'), numeric: true),
          DataColumn(label: Text('New employer accounts'), numeric: true),
          DataColumn(label: Text('Jobs posted'), numeric: true),
          DataColumn(label: Text('Applications'), numeric: true),
        ],
        rows: [
          for (final r in rows.reversed)
            DataRow(cells: [
              DataCell(Text(DateTime.tryParse('${r['week']}') == null ? '${r['week']}' : Fmt.dateShort(DateTime.parse('${r['week']}')))),
              DataCell(Text(_num(r['seekers']))),
              DataCell(Text('${_num(r['returned_1d'])} (${_pct(_i(r['returned_1d']), _i(r['seekers']))})')),
              DataCell(Text(_num(r['employers']))),
              DataCell(Text(_num(r['jobs']))),
              DataCell(Text(_num(r['applications']))),
            ]),
        ],
      );
}

class _DistrictTable extends StatelessWidget {
  const _DistrictTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => TableCard(
        columns: const [
          DataColumn(label: Text('District / town')),
          DataColumn(label: Text('Job seekers'), numeric: true),
          DataColumn(label: Text('Live jobs'), numeric: true),
          DataColumn(label: Text('Applications to jobs here'), numeric: true),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final r in rows.where((r) => _i(r['seekers']) > 0 || _i(r['live_jobs']) > 0))
            DataRow(cells: [
              DataCell(Text('${r['district']}')),
              DataCell(Text(_num(r['seekers']))),
              DataCell(Text(_num(r['live_jobs']))),
              DataCell(Text(_num(r['applications']))),
              DataCell(
                _i(r['seekers']) >= 10 && _i(r['live_jobs']) == 0 && '${r['district']}' != '(not set)'
                    ? Text('No jobs here yet', style: context.text.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700))
                    : const SizedBox(),
              ),
            ]),
        ],
      );
}

class _IndustryTable extends StatelessWidget {
  const _IndustryTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text('No jobs yet.', style: context.text.bodyMedium);
    return Column(children: [
      for (final r in rows)
        _Row(
          _industry('${r['industry']}'),
          '${_num(r['jobs'])} jobs (${_num(r['live_jobs'])} live) · ${_num(r['views'])} views · ${_num(r['applications'])} applications'
              '${_i(r['jobs']) > 0 ? ' · ${(_i(r['applications']) / _i(r['jobs'])).toStringAsFixed(1)} per job' : ''}',
        ),
    ]);
  }
}

class _JobsTable extends StatelessWidget {
  const _JobsTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => TableCard(
        empty: const Padding(padding: EdgeInsets.all(24), child: Text('No live jobs.')),
        columns: const [
          DataColumn(label: Text('Job')),
          DataColumn(label: Text('Days left'), numeric: true),
          DataColumn(label: Text('Views'), numeric: true),
          DataColumn(label: Text('Applied / taps'), numeric: true),
          DataColumn(label: Text('Rate'), numeric: true),
          DataColumn(label: Text('Waiting'), numeric: true),
          DataColumn(label: Text('Strong fit'), numeric: true),
          DataColumn(label: Text('Salary')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${r['company']} · ${r['location']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                ]),
              )),
              DataCell(Text(
                _i(r['days_left']) < 0 ? 'Passed' : _num(r['days_left']),
                style: TextStyle(
                  color: _i(r['days_left']) < 0 ? AppColors.danger : (_i(r['days_left']) <= 3 ? AppColors.warning : null),
                  fontWeight: _i(r['days_left']) <= 3 ? FontWeight.w700 : null,
                ),
              )),
              DataCell(Text(_num(r['views']))),
              DataCell(Text(r['external'] == true ? '${_num(r['external_applied'])} / ${_num(r['apply_clicks'])} taps' : _num(r['applicants']))),
              DataCell(Text(_pct(r['external'] == true ? _i(r['apply_clicks']) : _i(r['applicants']), _i(r['views'])))),
              DataCell(Text(
                _num(r['unanswered']),
                style: _i(r['unanswered']) > 0 ? const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700) : null,
              )),
              DataCell(Text(_num(r['matching']))),
              DataCell(r['salary'] == true ? const Icon(Icons.check_rounded, size: 18, color: AppColors.success) : const Text('—')),
            ]),
        ],
      );
}

class _CompanyTable extends StatelessWidget {
  const _CompanyTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => TableCard(
        empty: const Padding(padding: EdgeInsets.all(24), child: Text('No companies yet.')),
        columns: const [
          DataColumn(label: Text('Company')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Jobs'), numeric: true),
          DataColumn(label: Text('Live'), numeric: true),
          DataColumn(label: Text('Applicants'), numeric: true),
          DataColumn(label: Text('Waiting'), numeric: true),
          DataColumn(label: Text('Team last active')),
          DataColumn(label: Text('Joined')),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
              DataCell(Text(CompanyStatus.values.where((s) => s.name == r['status']).map((s) => s.label).firstOrNull ?? '${r['status']}')),
              DataCell(Text(_num(r['jobs']))),
              DataCell(Text(_num(r['live_jobs']))),
              DataCell(Text(_num(r['applicants']))),
              DataCell(Text(
                _num(r['unanswered']),
                style: _i(r['unanswered']) > 0 ? const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700) : null,
              )),
              DataCell(Text(_ago(r['last_seen']))),
              DataCell(Text(DateTime.tryParse('${r['created_at']}') == null ? '—' : Fmt.dateShort(DateTime.parse('${r['created_at']}').toLocal()))),
            ]),
        ],
      );
}
