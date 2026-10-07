import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Single-series chart colour, validated for contrast/lightness in each theme.
Color chartColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6AA334) : const Color(0xFF3F7A1F);

/// Page frame for employer screens: title row, optional actions, padded scroll body.
class EmployerPage extends StatelessWidget {
  const EmployerPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children, this.onRefresh});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(wide ? 32 : AppSpacing.gutter, wide ? 28 : 12, wide ? 32 : AppSpacing.gutter, 48),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Semantics(header: true, child: Text(title, style: context.text.headlineMedium)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                ],
              ]),
            ),
            if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 24),
        ...children,
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
          ),
        ),
      ),
    );
  }
}

/// Headline number with a label and an optional supporting line.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.detail, this.icon, this.onTap, this.attention = false});
  final String label;
  final String value;
  final String? detail;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Draws a warning stripe when the number needs action.
  final bool attention;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: '$label: $value${detail != null ? ', $detail' : ''}',
        excludeSemantics: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: attention ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.warning, width: 4))) : null,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: context.palette.muted), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
                  ),
                ]),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                ],
              ]),
            ),
          ),
        ),
      );
}

/// Lays out stat tiles in a responsive grid (2 columns on phones, up to 5).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 5 : (c.maxWidth >= 700 ? 3 : 2);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in children) SizedBox(width: w, child: t)]);
      });
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleMedium))),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

/// A DataTable inside a card that scrolls sideways on narrow screens.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.columns, required this.rows, this.empty, this.sortColumnIndex, this.sortAscending = true});
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final Widget? empty;
  final int? sortColumnIndex;
  final bool sortAscending;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && empty != null) return Card(child: empty!);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: DataTable(
              columns: columns,
              rows: rows,
              sortColumnIndex: sortColumnIndex,
              sortAscending: sortAscending,
              showCheckboxColumn: false,
              headingRowHeight: 44,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              horizontalMargin: 16,
              columnSpacing: 24,
              headingRowColor: WidgetStatePropertyAll(context.palette.surface),
              headingTextStyle: context.text.labelMedium?.copyWith(color: context.palette.muted, fontWeight: FontWeight.w700),
              dividerThickness: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class JobStatusPill extends StatelessWidget {
  const JobStatusPill(this.status, {super.key});
  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      JobStatus.published => (AppColors.success, Icons.circle),
      JobStatus.pending => (AppColors.warning, Icons.hourglass_top_rounded),
      JobStatus.draft => (context.palette.muted, Icons.edit_outlined),
      JobStatus.closed => (context.palette.muted, Icons.lock_outline_rounded),
      JobStatus.declined => (AppColors.warning, Icons.edit_note_rounded),
      JobStatus.rejected => (AppColors.danger, Icons.block_outlined),
    };
    return TagChip(status.label, dense: true, icon: icon, color: color, background: color.withValues(alpha: 0.12));
  }
}
