import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'widgets.dart';

final _dayLabel = DateFormat('d MMM');

/// Applications per day: single-series bar chart with a recessive grid,
/// per-bar hover tooltips, and a table view for screen readers and exact values.
class DailyApplicationsChart extends StatefulWidget {
  const DailyApplicationsChart({super.key, required this.days, this.noun = 'application'});
  final List<({DateTime day, int count})> days;

  /// Singular name of what is counted, e.g. 'application' or 'signup'.
  final String noun;

  @override
  State<DailyApplicationsChart> createState() => _DailyApplicationsChartState();
}

class _DailyApplicationsChartState extends State<DailyApplicationsChart> {
  bool _table = false;

  /// A "nice" axis maximum (1, 2, 5 × 10ⁿ) at or above [v].
  static int niceMax(int v) {
    if (v <= 4) return math.max(v, 1) <= 2 ? 2 : 4;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toInt();
    for (final m in [1, 2, 5, 10]) {
      if (m * exp >= v) return m * exp;
    }
    return 10 * exp;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final total = days.fold(0, (s, d) => s + d.count);
    final peak = days.fold(0, (s, d) => math.max(s, d.count));
    final top = niceMax(peak);
    final color = chartColor(context);
    final muted = context.palette.muted;

    final toggle = TextButton.icon(
      onPressed: () => setState(() => _table = !_table),
      icon: Icon(_table ? Icons.bar_chart_rounded : Icons.table_rows_outlined, size: 18),
      label: Text(_table ? 'Show chart' : 'Show table'),
    );

    if (_table) {
      final rows = days.where((d) => d.count > 0).toList().reversed.toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(alignment: Alignment.centerRight, child: toggle),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text('No ${widget.noun}s in this period.', style: context.text.bodyMedium))
        else
          DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: [const DataColumn(label: Text('Day')), DataColumn(label: Text('${widget.noun[0].toUpperCase()}${widget.noun.substring(1)}s'), numeric: true)],
            rows: [for (final d in rows) DataRow(cells: [DataCell(Text(_dayLabel.format(d.day))), DataCell(Text('${d.count}'))])],
          ),
      ]);
    }

    return Semantics(
      label: '$total ${widget.noun}s in the last ${days.length} days, peak $peak in one day.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$total', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(child: Text('${widget.noun}s · last ${days.length} days', style: context.text.bodyMedium?.copyWith(color: muted))),
          toggle,
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LayoutBuilder(builder: (context, c) {
            const axisW = 28.0;
            const labelH = 20.0;
            final plotW = c.maxWidth - axisW;
            final plotH = c.maxHeight - labelH;
            final slot = plotW / days.length;
            final barW = math.max(2.0, slot - 2); // 2px surface gap between bars
            return Stack(children: [
              // Recessive grid + y-axis labels at 0, half, top.
              for (final v in [0, top ~/ 2, top])
                Positioned(
                  left: 0,
                  right: 0,
                  top: plotH - plotH * v / top - 8,
                  child: Row(children: [
                    SizedBox(
                      width: axisW - 6,
                      child: Text('$v', textAlign: TextAlign.right, style: context.text.labelSmall?.copyWith(color: muted)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Container(height: 1, color: context.palette.border)),
                  ]),
                ),
              for (var i = 0; i < days.length; i++)
                Positioned(
                  left: axisW + i * slot,
                  width: slot,
                  top: 0,
                  height: plotH,
                  child: Tooltip(
                    message: '${_dayLabel.format(days[i].day)}: ${days[i].count} ${widget.noun}${days[i].count == 1 ? '' : 's'}',
                    waitDuration: Duration.zero,
                    child: Container(
                      color: Colors.transparent, // full-height hit target
                      alignment: Alignment.bottomCenter,
                      child: days[i].count == 0
                          ? null
                          : Container(
                              width: barW,
                              height: math.max(3.0, plotH * days[i].count / top),
                              decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                            ),
                    ),
                  ),
                ),
              // X labels: first, middle, last day.
              for (final i in {0, days.length ~/ 2, days.length - 1})
                Positioned(
                  left: (axisW + i * slot + slot / 2 - 30).clamp(0.0, c.maxWidth - 60),
                  width: 60,
                  bottom: 0,
                  child: Text(_dayLabel.format(days[i].day), textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: muted)),
                ),
            ]);
          }),
        ),
      ]),
    );
  }
}

/// Hiring funnel: how many candidates reached each stage. Horizontal bars,
/// one hue, direct value labels (no legend needed for a single series).
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.funnel});
  final Map<ApplicationStatus, int> funnel;

  @override
  Widget build(BuildContext context) {
    final applied = funnel[ApplicationStatus.applied] ?? 0;
    final max = math.max(1, funnel.values.fold(0, math.max));
    final color = chartColor(context);
    return Column(children: [
      for (final e in funnel.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: applied == 0 ? '${e.key.label}: ${e.value}' : '${e.key.label}: ${e.value} (${(e.value * 100 / applied).round()}% of applicants)',
            child: Row(children: [
              SizedBox(width: 110, child: Text(e.key.label, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: e.value == 0 ? 2 : math.max(4.0, c.maxWidth * e.value / max),
                      decoration: BoxDecoration(
                        color: e.value == 0 ? context.palette.border : color,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  applied == 0 || e.key == ApplicationStatus.applied ? '${e.value}' : '${e.value} · ${(e.value * 100 / applied).round()}%',
                  textAlign: TextAlign.right,
                  style: context.text.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Ranked horizontal bars (e.g. top industries): one hue, direct value labels.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.items, this.empty = 'No data yet.'});
  final List<({String label, int count})> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(empty, style: context.text.bodyMedium);
    final max = math.max(1, items.fold(0, (m, e) => math.max(m, e.count)));
    final color = chartColor(context);
    return Column(children: [
      for (final e in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Tooltip(
            message: '${e.label}: ${e.count}',
            child: Row(children: [
              SizedBox(width: 130, child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      width: math.max(4.0, c.maxWidth * e.count / max),
                      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('${e.count}', textAlign: TextAlign.right, style: context.text.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ),
    ]);
  }
}
