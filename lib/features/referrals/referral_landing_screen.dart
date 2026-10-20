import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/referral_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/vocation_logo.dart';

/// Opened from a referral link (employers.vocationsl.com/r/CODE). Keeps the
/// code on the device and sends the visitor to employer sign-up, where the
/// code is prefilled on the company form.
class ReferralLandingScreen extends ConsumerStatefulWidget {
  const ReferralLandingScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<ReferralLandingScreen> createState() => _ReferralLandingScreenState();
}

class _ReferralLandingScreenState extends ConsumerState<ReferralLandingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _continue());
  }

  Future<void> _continue() async {
    final store = ref.read(localStoreProvider);
    if (ReferralCode.normalize(widget.code).isNotEmpty) await PendingReferral.save(store, widget.code);
    // Pre-select "Hire talent" on the login screen.
    await store.setSetting('last_role', UserRole.employer.name);
    final signedIn = ref.read(sessionProvider) != null;
    if (signedIn) {
      await ref.read(roleProvider.notifier).choose(UserRole.employer);
    } else {
      await ref.read(roleProvider.notifier).setIntent(UserRole.employer);
    }
    if (mounted) context.go(signedIn ? '/employer/dashboard' : '/login');
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            VocationLogo(size: 36),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ]),
        ),
      );
}
