import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'employer/providers.dart';
import 'models/models.dart';
import 'providers/core_providers.dart';
import 'providers/job_providers.dart';
import 'providers/push_providers.dart';
import 'providers/session_providers.dart';
import 'providers/user_data_providers.dart';
import 'repositories/sync_service.dart';
import 'services/push_service.dart';
import 'widgets/states.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class VocationApp extends ConsumerWidget {
  const VocationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      scaffoldMessengerKey: scaffoldMessengerKey,
      builder: (context, child) => _AppFrame(child: child ?? const SizedBox()),
    );
  }
}

/// Wraps every screen: offline banner, sync on reconnect, sync reports.
class _AppFrame extends ConsumerStatefulWidget {
  const _AppFrame({required this.child});
  final Widget child;

  @override
  ConsumerState<_AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<_AppFrame> with WidgetsBindingObserver {
  StreamSubscription<SyncReport>? _reports;
  StreamSubscription<void>? _recovery;
  StreamSubscription<String>? _pushTaps;
  StreamSubscription<Object>? _pushForeground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final sync = ref.read(syncServiceProvider);
    _reports = sync.reports.listen(_onSyncReport);
    // A password-reset link signs the user in; send them to choose a new password.
    _recovery = ref.read(userRepositoryProvider).passwordRecovery.listen((_) {
      ref.read(routerProvider).go('/settings/password?reset=1');
    });
    // Tapping a push alert opens the right screen.
    final push = ref.read(pushServiceProvider);
    _pushTaps = push?.taps.listen((route) => ref.read(routerProvider).go(route));
    _pushForeground = push?.foreground.listen((m) {
      _refreshAll();
      final title = m.notification?.title;
      if (title == null) return;
      final route = m.data['route'] is String ? m.data['route'] as String : '/alerts';
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(title),
        persist: false,
        action: SnackBarAction(label: 'View', onPressed: () => ref.read(routerProvider).go(route)),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPush());
    // Replay anything queued in a previous session.
    WidgetsBinding.instance.addPostFrameCallback((_) => sync.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reports?.cancel();
    _recovery?.cancel();
    _pushTaps?.cancel();
    _pushForeground?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  void _onSyncReport(SyncReport r) {
    ref.invalidate(pendingSyncCountProvider);
    _refreshAll();
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    if (r.failed.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Some offline changes couldn\'t be saved. ${r.failed.first}')));
    } else if (r.synced > 0) {
      messenger.showSnackBar(SnackBar(content: Text('Back online · synced ${r.synced} change${r.synced == 1 ? '' : 's'}')));
    }
  }

  /// Registers this device for push alerts after sign-in. On Android the
  /// permission prompt appears once; on the web the user turns alerts on
  /// from the Alerts screen (browsers only allow asking after a tap).
  Future<void> _syncPush() async {
    final push = ref.read(pushServiceProvider);
    if (push == null || ref.read(sessionProvider) == null) return;
    if (!kIsWeb && await push.permission() == PushPermission.notAsked) {
      await push.enable();
      ref.invalidate(pushPermissionProvider);
    } else {
      await push.sync();
    }
  }

  /// Background refresh of everything the user has open.
  void _refreshAll() {
    if (!ref.read(onlineProvider) || ref.read(sessionProvider) == null) return;
    final role = ref.read(roleProvider);
    if (role == UserRole.employer) {
      unawaited(ref.read(companyProvider.notifier).refresh());
      unawaited(ref.read(candidatesProvider.notifier).refresh());
      unawaited(ref.read(employerJobsProvider.notifier).refresh());
      return;
    }
    if (role == null) return;
    unawaited(ref.read(notificationsProvider.notifier).refresh());
    unawaited(ref.read(applicationsProvider.notifier).refresh());
    unawaited(ref.read(savedJobsProvider.notifier).refresh());
    unawaited(ref.read(homeFeedProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(sessionProvider, (prev, uid) {
      if (uid != null && uid != prev) _syncPush();
    });
    ref.listen<bool>(onlineProvider, (prev, online) {
      if (prev == false && online) {
        ref.read(syncServiceProvider).flush();
        _refreshAll();
      }
    });
    final online = ref.watch(onlineProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: !online, child: widget.child),
        ),
      ]),
    );
  }
}
