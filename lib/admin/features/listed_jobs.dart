import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

/// The company the Vocation SL team lists public vacancies under.
const listingCompanyName = 'Vocation SL';

/// A job the team listed for another employer: "Role (Employer)".
({String role, String employer}) splitListedTitle(String title) {
  final m = RegExp(r'^(.*)\s\(([^()]+)\)$').firstMatch(title.trim());
  return m == null ? (role: title.trim(), employer: '') : (role: m.group(1)!.trim(), employer: m.group(2)!.trim());
}

/// One employer whose vacancies the team listed, with the numbers to show them.
class ListedEmployer {
  ListedEmployer(this.name, this.jobs);
  final String name;
  final List<Job> jobs;

  int get views => jobs.fold(0, (s, j) => s + j.views);
  int get taps => jobs.fold(0, (s, j) => s + (j.appliesExternally ? j.applyClicks : j.applicants));
  int get applied => jobs.fold(0, (s, j) => s + (j.appliesExternally ? j.externalApplied : j.applicants));

  /// The HR email from an apply-by-email job, if any.
  String? get email => jobs.map((j) => j.applyEmail).whereType<String>().firstOrNull;

  /// The employer's own apply website, if any (not an email).
  String? get website {
    for (final j in jobs) {
      if (j.appliesExternally && j.applyEmail == null) return Uri.tryParse(j.applyUrl)?.host.replaceFirst('www.', '');
    }
    return null;
  }

  static List<ListedEmployer> from(List<Job> all, {required bool includeClosed}) {
    final byEmployer = <String, List<Job>>{};
    for (final j in all) {
      if (j.companyName != listingCompanyName) continue;
      if (j.status != JobStatus.published && j.status != JobStatus.closed) continue;
      if (!includeClosed && (j.status == JobStatus.closed || j.isClosed)) continue;
      final employer = splitListedTitle(j.title).employer;
      if (employer.isEmpty) continue;
      byEmployer.putIfAbsent(employer, () => []).add(j);
    }
    final list = [for (final e in byEmployer.entries) ListedEmployer(e.key, e.value..sort((a, b) => a.deadline.compareTo(b.deadline)))];
    list.sort((a, b) => b.views.compareTo(a.views));
    return list;
  }

  /// A short, honest message with this employer's real numbers.
  String message({DateTime? freeUntil}) {
    final lines = [
      for (final j in jobs)
        j.appliesExternally
            ? '• ${splitListedTitle(j.title).role}: ${j.views} views, ${j.applyClicks} taps on Apply'
                '${j.externalApplied > 0 ? ', ${j.externalApplied} told us they applied' : ''}'
            : '• ${splitListedTitle(j.title).role}: ${j.views} views, ${j.applicants} applications',
    ];
    final free = freeUntil != null && !DateTime.now().isAfter(freeUntil) ? ' It is free until ${Fmt.date(freeUntil)}.' : '';
    return 'Hello $name team,\n\n'
        'We shared your ${jobs.length == 1 ? 'vacancy' : 'vacancies'} on Vocation SL, the job app for Sierra Leone (web, Android and iPhone). '
        'Here is how ${jobs.length == 1 ? 'it is' : 'they are'} doing so far:\n'
        '${lines.join('\n')}\n\n'
        'Next time, you can post your vacancies on Vocation SL yourself: applicants and their CVs come to you in one place, '
        'and you can message and shortlist them in the app.$free '
        'Busy? Just send us the advert and we will post it for you.\n\n'
        'Sign up: employers.vocationsl.com\n'
        'WhatsApp: +232 73 512 413 · Email: info@vocationsl.com\n\n'
        'Thank you,\nVocation SL team';
  }
}

/// Admin → Listed jobs: vacancies the team listed for other employers, their
/// numbers, and a ready message to invite each employer to post directly.
class AdminListedJobsScreen extends ConsumerStatefulWidget {
  const AdminListedJobsScreen({super.key});

  @override
  ConsumerState<AdminListedJobsScreen> createState() => _AdminListedJobsScreenState();
}

class _AdminListedJobsScreenState extends ConsumerState<AdminListedJobsScreen> {
  bool _includeClosed = true;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminJobsProvider);
    final freeUntil = ref.watch(platformSettingsProvider).value?.launchUntil;
    return EmployerPage(
      title: 'Listed jobs',
      subtitle: 'Vacancies our team listed for other employers. Each one is a lead: send them their numbers and invite them to post directly.',
      onRefresh: () async => ref.invalidate(adminJobsProvider),
      children: [
        AdminAsync<List<Job>>(
          value: async,
          onRetry: () => ref.invalidate(adminJobsProvider),
          builder: (all) {
            final employers = ListedEmployer.from(all, includeClosed: _includeClosed);
            final jobs = employers.expand((e) => e.jobs).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatGrid(children: [
                StatTile(label: 'Employers (leads)', value: '${employers.length}', icon: Icons.business_outlined),
                StatTile(label: 'Listed jobs', value: '${jobs.length}', detail: '${jobs.where((j) => j.status == JobStatus.published && !j.isClosed).length} open', icon: Icons.work_outline_rounded),
                StatTile(label: 'Views', value: Fmt.money(jobs.fold(0, (s, j) => s + j.views)), icon: Icons.visibility_outlined),
                StatTile(label: 'Taps on Apply', value: Fmt.money(employers.fold(0, (s, e) => s + e.taps)), icon: Icons.ads_click_rounded),
                StatTile(label: 'Said they applied', value: Fmt.money(employers.fold(0, (s, e) => s + e.applied)), detail: 'Self-reported in the app', icon: Icons.task_alt_rounded),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                FilterChip(
                  label: const Text('Include closed jobs'),
                  selected: _includeClosed,
                  onSelected: (v) => setState(() => _includeClosed = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Best time to write: about a week after the deadline, when the numbers are final.',
                      style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                ),
              ]),
              const SizedBox(height: 16),
              if (employers.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No listed jobs yet. Jobs posted under the Vocation SL company with the employer in brackets appear here.'))),
              for (final e in employers) ...[
                _EmployerCard(e: e, freeUntil: freeUntil),
                const SizedBox(height: 16),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _EmployerCard extends StatelessWidget {
  const _EmployerCard({required this.e, this.freeUntil});
  final ListedEmployer e;
  final DateTime? freeUntil;

  @override
  Widget build(BuildContext context) {
    final msg = e.message(freeUntil: freeUntil);
    final email = e.email;
    return SectionCard(
      title: e.name,
      trailing: Text('${e.views} views · ${e.taps} taps · ${e.applied} applied',
          style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final j in e.jobs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(splitListedTitle(j.title).role, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(
                j.status == JobStatus.closed || j.isClosed ? 'Closed' : 'Open until ${Fmt.dateShort(j.deadline)}',
                style: context.text.bodySmall?.copyWith(color: j.status == JobStatus.closed || j.isClosed ? context.palette.muted : AppColors.success),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 230,
                child: Text(
                  j.appliesExternally
                      ? '${j.views} views · ${j.applyClicks} taps · ${j.externalApplied} applied'
                      : '${j.views} views · ${j.applicants} applications',
                  textAlign: TextAlign.right,
                  style: context.text.bodySmall,
                ),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Text(
          [if (email != null) 'HR email: $email', if (e.website != null) 'Apply website: ${e.website}'].join(' · ').ifEmpty('No contact on the advert: find their HR phone or email.'),
          style: context.text.bodySmall?.copyWith(color: context.palette.muted),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(msg, style: context.text.bodySmall),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: msg));
              if (context.mounted) showSnack(context, 'Message copied. Paste it into WhatsApp or email.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy message'),
          ),
          if (email != null)
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri(scheme: 'mailto', path: email, query: 'subject=${Uri.encodeComponent('Your vacancy on Vocation SL')}&body=${Uri.encodeComponent(msg)}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email HR'),
            ),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp'),
          ),
        ]),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
