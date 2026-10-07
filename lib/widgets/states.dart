import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../providers/core_providers.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: context.palette.accentTint, shape: BoxShape.circle),
                child: Icon(icon, size: 40, color: context.colors.primary),
              ),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: context.text.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, style: FilledButton.styleFrom(minimumSize: const Size(160, 48)), child: Text(action!)),
              ],
            ]),
          ),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final offline = error is NetworkException;
    final title = offline ? 'You\'re offline' : 'Couldn\'t load this';
    final message = offline
        ? 'Connect to the internet to see the latest. Anything you\'ve already viewed is saved for offline use.'
        : AppException.describe(error);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, color: context.palette.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(offline ? 'You\'re offline.' : 'Couldn\'t load more jobs.', style: context.text.bodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
    }
    return EmptyState(
      icon: offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
      title: title,
      message: message,
      action: 'Try again',
      onAction: onRetry,
    );
  }
}

/// Thin banner shown app-wide while offline.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider);
    final pending = ref.watch(pendingSyncCountProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: online
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: AppColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SafeArea(
                  bottom: false,
                  child: Row(children: [
                    const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pending > 0
                            ? 'Offline · $pending change${pending == 1 ? '' : 's'} will sync when you reconnect'
                            : 'Offline · showing saved data',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
    );
  }
}

/// Notice shown above content that came from cache after a failed refresh.
class CacheNotice extends StatelessWidget {
  const CacheNotice({super.key, required this.syncedAt, this.onRetry});
  final DateTime? syncedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.history_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              syncedAt == null ? 'Showing saved data' : 'Showing saved data from ${Fmt.ago(syncedAt!).toLowerCase()}',
              style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

/// Footer for paginated lists: spinner, retry, or end-of-list.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, required this.loading, required this.hasMore, this.error, required this.onRetry, this.endLabel});
  final bool loading;
  final bool hasMore;
  final Object? error;
  final VoidCallback onRetry;
  final String? endLabel;

  @override
  Widget build(BuildContext context) {
    if (error != null) return ErrorState(error: error!, onRetry: onRetry, compact: true);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (!hasMore && endLabel != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(endLabel!, style: context.text.bodySmall?.copyWith(color: context.palette.muted))),
      );
    }
    return const SizedBox(height: 24);
  }
}
