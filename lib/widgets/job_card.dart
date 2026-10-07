import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/models.dart';
import '../providers/user_data_providers.dart';
import 'common.dart';
import 'company_logo.dart';

/// Bookmark toggle with optimistic update and a small bounce.
class SaveJobButton extends ConsumerStatefulWidget {
  const SaveJobButton({super.key, required this.job, this.size = 24, this.filled = false});
  final Job job;
  final double size;
  final bool filled;

  @override
  ConsumerState<SaveJobButton> createState() => _SaveJobButtonState();
}

class _SaveJobButtonState extends ConsumerState<SaveJobButton> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    HapticFeedback.lightImpact();
    _anim.forward(from: 0);
    try {
      final saved = await ref.read(savedJobsProvider.notifier).toggle(widget.job);
      if (!mounted) return;
      showSnack(
        context,
        saved ? 'Saved ${widget.job.title}' : 'Removed from saved jobs',
        action: saved ? 'View' : 'Undo',
        onAction: saved ? () => context.go('/saved') : () => ref.read(savedJobsProvider.notifier).toggle(widget.job),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(isJobSavedProvider(widget.job.id));
    final scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    final icon = ScaleTransition(
      scale: scale,
      child: Icon(
        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        size: widget.size,
        color: saved ? context.colors.primary : context.colors.onSurface,
      ),
    );
    return Tooltip(
      message: saved ? 'Remove from saved' : 'Save job',
      child: Semantics(
        button: true,
        toggled: saved,
        label: saved ? 'Saved. Remove ${widget.job.title} from saved jobs' : 'Save ${widget.job.title}',
        excludeSemantics: true,
        child: widget.filled
            ? IconButton.outlined(onPressed: _toggle, icon: icon, style: IconButton.styleFrom(minimumSize: const Size(52, 52)))
            : IconButton(onPressed: _toggle, icon: icon),
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, this.onTap, this.showDescription = false});
  final Job job;
  final VoidCallback? onTap;
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    final soon = Fmt.deadlineSoon(job.deadline);
    return Semantics(
      container: true,
      label: '${job.title} at ${job.companyName}, ${job.location}. ${Fmt.salary(job)}. ${job.employmentType.label}. ${Fmt.deadline(job.deadline)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => context.push('/job/${job.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 6, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(tag: 'logo-${job.id}', child: CompanyLogo(company: job.company, size: 48)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                              child: Text(job.companyName,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: muted)),
                            ),
                            if (job.company?.verified ?? false) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.verified_rounded, size: 14, color: context.colors.primary, semanticLabel: 'Verified employer'),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    SaveJobButton(job: job),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TagChip(job.location, icon: Icons.place_outlined),
                      TagChip(job.employmentType.label, icon: Icons.work_outline_rounded),
                      if (job.workMode != WorkMode.onsite)
                        TagChip(job.workMode.label,
                            icon: Icons.wifi_rounded, color: context.colors.primary, background: context.palette.accentTint),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(Fmt.salary(job), style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (showDescription) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(job.about, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: muted)),
                  ),
                ],
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${Fmt.posted(job.postedAt)}  ·  '),
                          TextSpan(
                            text: Fmt.deadline(job.deadline),
                            style: TextStyle(
                              color: job.isClosed ? AppColors.danger : (soon ? AppColors.warning : muted),
                              fontWeight: soon ? FontWeight.w700 : null,
                            ),
                          ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium?.copyWith(color: muted),
                      ),
                    ),
                    if (job.featured) ...[
                      const SizedBox(width: 8),
                      TagChip('Featured', dense: true, color: context.colors.onPrimaryContainer, background: context.colors.primaryContainer),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide card for horizontal "featured" carousels.
class FeaturedJobCard extends StatelessWidget {
  const FeaturedJobCard({super.key, required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final color = Color(job.company?.brandColor ?? 0xFF3F7A1F);
    return Semantics(
      container: true,
      label: 'Featured: ${job.title} at ${job.companyName}, ${Fmt.salary(job)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/job/${job.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 72,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0.9), Color.lerp(color, Colors.black, 0.35)!]),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: CompanyLogo(company: job.company, size: 44),
                  ),
                  const Spacer(),
                  Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: context.colors.copyWith(onSurface: Colors.white, primary: Colors.white),
                    ),
                    child: SaveJobButton(job: job),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                  const SizedBox(height: 2),
                  Text('${job.companyName} · ${job.location}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(Fmt.salary(job, short: true), style: context.text.titleSmall)),
                    TagChip(job.workMode == WorkMode.onsite ? job.employmentType.label : job.workMode.label, dense: true),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
