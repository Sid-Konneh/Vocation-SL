import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/ios_install.dart';
import '../core/theme/app_theme.dart';
import '../providers/core_providers.dart';

/// On an iPhone or iPad browser: how to put Vocation SL on the home screen.
/// Hidden everywhere else, once installed, or after the user dismisses it.
class IosInstallBanner extends ConsumerStatefulWidget {
  const IosInstallBanner({super.key});

  @override
  ConsumerState<IosInstallBanner> createState() => _IosInstallBannerState();
}

class _IosInstallBannerState extends ConsumerState<IosInstallBanner> {
  static const _key = 'ios_install_dismissed';
  late bool _show = canSuggestIosInstall && ref.read(localStoreProvider).setting<bool>(_key) != true;

  void _dismiss() {
    ref.read(localStoreProvider).setSetting(_key, true);
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final step = context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(color: context.palette.accentTint, borderRadius: BorderRadius.circular(AppSpacing.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.add_to_home_screen_rounded, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Add Vocation SL to your Home Screen', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text.rich(TextSpan(style: step, children: const [
                TextSpan(text: '1. In Safari, tap the '),
                TextSpan(text: 'Share', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' button  '),
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.ios_share_rounded, size: 18)),
                TextSpan(text: '\n2. Choose '),
                TextSpan(text: 'Add to Home Screen', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ', then '),
                TextSpan(text: 'Add', style: TextStyle(fontWeight: FontWeight.w700)),
              ])),
              const SizedBox(height: 4),
              Text('It opens like an app, full screen, and can send you alerts.', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]),
          ),
          IconButton(tooltip: 'Dismiss', onPressed: _dismiss, icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      ),
    );
  }
}
