import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/core_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/states.dart';
import 'employer_router.dart';
import 'providers.dart';

class EmployerApp extends ConsumerWidget {
  const EmployerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Vocation SL for Employers',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: ref.watch(employerRouterProvider),
        builder: (context, child) => _Frame(child: child ?? const SizedBox()),
      );
}

/// Offline banner, refresh on reconnect/resume, password-reset redirect.
class _Frame extends ConsumerStatefulWidget {
  const _Frame({required this.child});
  final Widget child;

  @override
  ConsumerState<_Frame> createState() => _FrameState();
}

class _FrameState extends ConsumerState<_Frame> with WidgetsBindingObserver {
  StreamSubscription<void>? _recovery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recovery = ref.read(userRepositoryProvider).passwordRecovery.listen((_) {
      ref.read(employerRouterProvider).go('/settings/password?reset=1');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recovery?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!ref.read(onlineProvider) || ref.read(sessionProvider) == null) return;
    unawaited(ref.read(companyProvider.notifier).refresh());
    unawaited(ref.read(candidatesProvider.notifier).refresh());
    unawaited(ref.read(employerJobsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(onlineProvider, (prev, online) {
      if (prev == false && online) _refresh();
    });
    final online = ref.watch(onlineProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        const OfflineBanner(),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: !online, child: widget.child)),
      ]),
    );
  }
}
