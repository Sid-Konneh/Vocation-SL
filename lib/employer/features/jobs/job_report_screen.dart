import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../providers/hiring_providers.dart';
import '../../../services/export_service.dart';
import '../../../services/job_report_pdf.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';

/// Views, applications, pipeline, sources and speed for one job.
class JobReportScreen extends ConsumerWidget {
  const JobReportScreen({super.key, required this.jobId});
  final String jobId;

  Future<void> _export(BuildContext context, WidgetRef ref, JobReport r) async {
    try {
      final company = ref.read(companyProvider).value?.data?.name ?? '';
      final bytes = await JobReportPdf.build(r, company);
      await ExportService.savePdf(JobReportPdf.fileName(r), bytes);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobReportProvider(jobId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hiring report'),
        actions: [
          if (async.hasValue)
            TextButton.icon(
              onPressed: () => _export(context, ref, async.value!),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Save PDF'),
            ),
        ],
      ),
      body: async.when(
        loading: () => const SingleChildScrollView(child: Skeleton(child: Column(children: [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()]))),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(jobReportProvider(jobId))),
        data: (r) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(jobReportProvider(jobId)),
          child: ResponsiveCenter(
            maxWidth: 1000,
            child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
              Text(r.title, style: context.text.headlineSmall),
              Text(
                [
                  if (r.location.isNotEmpty) r.location,
                  if (r.postedAt != null) 'Posted ${Fmt.date(r.postedAt!)}',
                  if (r.deadline != null) 'Deadline ${Fmt.date(r.deadline!)}',
                ].join(' · '),
                style: context.text.bodyMedium?.copyWith(color: context.palette.muted),
              ),
              const SizedBox(height: 16),
              StatGrid(children: [
                StatTile(label: 'Views', value: '${r.views}', icon: Icons.visibility_outlined),
                if (r.appliesExternally)
                  StatTile(label: 'Website taps', value: '${r.applyClicks}', icon: Icons.open_in_new_rounded, detail: 'Applications go to your website')
                else
                  StatTile(
                    label: 'Applications',
                    value: '${r.applications}',
                    icon: Icons.people_outline_rounded,
                    detail: r.conversion == null ? null : '${r.conversion!.toStringAsFixed(1)} per 100 views',
                  ),
                StatTile(label: 'Typical reply time', value: replyTimeText(r.medianReplyHours), icon: Icons.schedule_rounded, detail: '${r.replied} replied to'),
                StatTile(
                  label: 'Hired',
                  value: '${r.hired}',
                  icon: Icons.verified_rounded,
                  detail: r.firstHireDays == null ? null : 'First hire after ${r.firstHireDays!.round()} days',
                ),
              ]),
              if (!r.appliesExternally) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Pipeline',
                  child: Column(children: [
                    _Bars(rows: [
                      ('Applied', r.applications),
                      ('Shortlisted', r.reached['shortlisted'] ?? 0),
                      ('Interviewed', r.reached['interview'] ?? 0),
                      ('Offered', r.reached['offer'] ?? 0),
                      ('Hired', r.hired),
                    ]),
                    if (r.withdrawn > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${r.withdrawn} withdrew their application.', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Where applicants found the job',
                  child: r.sources.isEmpty
                      ? Text('No applications yet.', style: context.text.bodyMedium)
                      : _Bars(rows: [for (final e in (r.sources.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) (e.key.label, e.value)]),
                ),
                if (r.byDay.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionCard(title: 'Applications by day', child: _DayChart(days: r.byDay)),
                ],
                if (r.invitesSent > 0) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Talent search',
                    child: Text('${r.invitesSent} people invited to apply; ${r.invitedApplied} of them applied.', style: context.text.bodyLarge),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Text(
                'Where applicants found the job is recorded from app version 1.2; earlier applications show as "Not recorded". '
                'Reply time is from applying to the first stage change or message from your team.',
                style: context.text.bodySmall?.copyWith(color: context.palette.muted),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Labelled horizontal bars, one colour, value at the end.
class _Bars extends StatelessWidget {
  const _Bars({required this.rows});
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final color = chartColor(context);
    return Column(children: [
      for (final (label, n) in rows)
        Semantics(
          label: '$label: $n',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 150, child: Text(label, style: context.text.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: max == 0 ? 0 : n / max,
                    child: Container(height: 14, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)))),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('$n', textAlign: TextAlign.right, style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _DayChart extends StatelessWidget {
  const _DayChart({required this.days});
  final List<({DateTime day, int count})> days;

  @override
  Widget build(BuildContext context) {
    // The server lists only days with applications; fill the gaps with zeros.
    final counts = {for (final d in days) DateUtils.dateOnly(d.day): d.count};
    final first = DateUtils.dateOnly(days.first.day);
    final last = DateUtils.dateOnly(days.last.day);
    final all = [
      for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) (day: d, count: counts[d] ?? 0),
    ];
    final shown = all.length > 30 ? all.sublist(all.length - 30) : all;
    final max = shown.fold<int>(1, (m, d) => d.count > m ? d.count : m);
    final color = chartColor(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 120,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in shown)
            Expanded(
              child: Tooltip(
                message: '${Fmt.dateShort(d.day)}: ${d.count}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: d.count == 0 ? 2 : 120 * d.count / max,
                    decoration: BoxDecoration(color: d.count == 0 ? context.palette.border : color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text(Fmt.dateShort(shown.first.day), style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
        const Spacer(),
        Text(Fmt.dateShort(shown.last.day), style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
      ]),
    ]);
  }
}
