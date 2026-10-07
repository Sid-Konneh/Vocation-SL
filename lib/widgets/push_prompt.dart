import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/push_providers.dart';
import '../services/push_service.dart';
import 'common.dart';

/// "Get alerts when Vocation SL is closed": turns on push for this device,
/// or explains how to unblock it. Hidden when push is on or not available.
class PushPrompt extends ConsumerStatefulWidget {
  const PushPrompt({super.key});

  @override
  ConsumerState<PushPrompt> createState() => _PushPromptState();
}

class _PushPromptState extends ConsumerState<PushPrompt> {
  bool _busy = false;

  Future<void> _enable() async {
    final push = ref.read(pushServiceProvider);
    if (push == null) return;
    setState(() => _busy = true);
    try {
      final p = await push.enable();
      if (!mounted) return;
      ref.invalidate(pushPermissionProvider);
      showSnack(context, p == PushPermission.granted ? 'Alerts turned on for this device' : 'Alerts are blocked. You can allow them in your settings.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(pushPermissionProvider).value;
    if (p == null || p == PushPermission.unsupported || p == PushPermission.granted) return const SizedBox.shrink();
    final blocked = p == PushPermission.denied;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.palette.accentTint, borderRadius: BorderRadius.circular(AppSpacing.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(blocked ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(blocked ? 'Alerts are blocked on this device' : 'Get alerts even when Vocation SL is closed',
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                blocked
                    ? (kIsWeb
                        ? 'Click the icon next to the web address, allow Notifications, then reload the page.'
                        : 'Open your phone Settings → Apps → Vocation SL → Notifications and turn them on.')
                    : 'New messages, interview invitations and application updates will reach you right away.',
                style: context.text.bodySmall,
              ),
              if (!blocked) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _enable,
                  icon: const Icon(Icons.notifications_active_rounded, size: 18),
                  label: const Text('Turn on alerts'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}