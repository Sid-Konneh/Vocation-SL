import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/session_providers.dart';
import '../../widgets/vocation_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.signedInPath = '/jobs', this.tagline = 'Find work that moves Salone forward'});
  final String signedInPath;
  final String tagline;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_continue);
  }

  void _continue() {
    if (!mounted) return;
    final signedIn = ref.read(sessionProvider) != null;
    context.go(signedIn ? (AppConfig.adminSite ? '/admin' : widget.signedInPath) : '/login');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = reduce ? 1.0 : _c.value;
            final textT = Curves.easeOut.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
            return Column(mainAxisSize: MainAxisSize.min, children: [
              VocationMark(size: 112, progress: Curves.easeInOutCubic.transform((t / 0.75).clamp(0.0, 1.0))),
              const SizedBox(height: 24),
              Opacity(
                opacity: textT,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - textT)),
                  child: Column(children: [
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Vocation'),
                        TextSpan(text: ' SL', style: TextStyle(color: context.colors.primary)),
                      ]),
                      style: context.text.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(widget.tagline,
                        style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
