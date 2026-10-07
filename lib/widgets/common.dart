import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/errors.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';

/// Centers content and caps its width on tablets and desktop.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = AppSpacing.maxContentWidth, this.padding});
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.subtitle});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                ],
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: context.colors.onSurface),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action!, style: const TextStyle(decoration: TextDecoration.underline)),
              ]),
            ),
        ],
      );
}

/// Small rounded label, e.g. "Full-time" or "Remote".
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.icon, this.color, this.background, this.dense = false});
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.onSurface;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: background ?? context.palette.surface,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (dense ? context.text.labelSmall : context.text.labelMedium)?.copyWith(color: fg)),
        ),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final ApplicationStatus status;
  final bool dense;

  static Color colorFor(ApplicationStatus s) => switch (s) {
        ApplicationStatus.applied => AppColors.info,
        ApplicationStatus.viewed => const Color(0xFF4F6BD8),
        ApplicationStatus.shortlisted => AppColors.purple,
        ApplicationStatus.assessment => AppColors.warning,
        ApplicationStatus.interview => const Color(0xFFD9570F),
        ApplicationStatus.offer => AppColors.success,
        ApplicationStatus.hired => AppColors.green,
        ApplicationStatus.rejected => AppColors.danger,
        ApplicationStatus.withdrawn => const Color(0xFF7A807A),
      };

  static IconData iconFor(ApplicationStatus s) => switch (s) {
        ApplicationStatus.applied => Icons.send_rounded,
        ApplicationStatus.viewed => Icons.visibility_rounded,
        ApplicationStatus.shortlisted => Icons.star_rounded,
        ApplicationStatus.assessment => Icons.assignment_rounded,
        ApplicationStatus.interview => Icons.event_rounded,
        ApplicationStatus.offer => Icons.handshake_rounded,
        ApplicationStatus.hired => Icons.verified_rounded,
        ApplicationStatus.rejected => Icons.close_rounded,
        ApplicationStatus.withdrawn => Icons.undo_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = colorFor(status);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Status: ${status.label}',
      child: TagChip(
        status.label,
        icon: iconFor(status),
        dense: dense,
        color: dark ? Color.lerp(c, Colors.white, 0.35) : c,
        background: c.withValues(alpha: dark ? 0.22 : 0.1),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.initials, this.photoBase64, this.size = 48});
  final String initials;
  final String? photoBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (photoBase64 != null) {
      try {
        image = MemoryImage(base64Decode(photoBase64!));
      } catch (_) {}
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: context.colors.primaryContainer,
      foregroundImage: image,
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: context.colors.onPrimaryContainer)),
    );
  }
}

/// Filled button that shows a spinner while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.loading = false, this.icon, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: context.colors.onPrimary),
          )
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    final button = FilledButton(onPressed: loading ? null : onPressed, child: child);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: context.colors.onSurface),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 2),
              Text(value, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      );
}

class BulletList extends StatelessWidget {
  const BulletList(this.items, {super.key, this.icon});
  final List<String> items;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: icon != null
                      ? Icon(icon, size: 18, color: context.colors.primary)
                      : Container(
                          margin: const EdgeInsets.only(top: 5, left: 4, right: 4),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item, style: context.text.bodyLarge)),
              ]),
            ),
        ],
      );
}

void showSnack(BuildContext context, String message, {String? action, VoidCallback? onAction, bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
      // Snack bars with an action persist by default; ours are transient hints.
      persist: false,
      action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ));
}

void showError(BuildContext context, Object error) => showSnack(context, AppException.describe(error), error: true);

/// A confirm dialog that resolves to true when confirmed.
Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, required String confirmLabel, bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)) : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
