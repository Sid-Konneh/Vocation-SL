import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/core_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';

/// Asks for confirmation (warning about unsynced offline changes), then signs out.
/// The router sends the user to the login screen when the session ends.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final pending = ref.read(pendingSyncCountProvider);
  final ok = await confirmDialog(
    context,
    title: 'Sign out?',
    message: pending > 0
        ? 'You have $pending unsynced change${pending == 1 ? '' : 's'}. They will be lost if you sign out now.'
        : 'You can sign back in at any time.',
    confirmLabel: 'Sign out',
    destructive: pending > 0,
  );
  if (!ok) return;
  try {
    await ref.read(sessionProvider.notifier).signOut();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
