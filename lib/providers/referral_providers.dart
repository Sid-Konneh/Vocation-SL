import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../data/backend/referral_backend.dart';
import '../models/models.dart';
import 'session_providers.dart';

/// Overridden in main.dart with the Supabase version when live.
final referralBackendProvider = Provider<ReferralBackend>((ref) => DemoReferralBackend());

/// The signed-in user's referral code.
final myReferralCodeProvider = FutureProvider.autoDispose<String>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(referralBackendProvider).myCode();
});

/// Employers the signed-in user has referred.
final myReferralsProvider = FutureProvider.autoDispose<List<Referral>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(referralBackendProvider).myReferrals();
});

/// The signed-in user's Mobile Money account for rewards.
final myPayoutProvider = FutureProvider.autoDispose<PayoutDetails?>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(referralBackendProvider).myPayout();
});

/// What referrers receive, as set by admins ('' if not announced).
final referralRewardProvider = FutureProvider.autoDispose<String>((ref) => ref.watch(referralBackendProvider).rewardText());

/// All referrals, for the admin dashboard.
final adminReferralsProvider = FutureProvider.autoDispose<List<Referral>>((ref) => ref.watch(referralBackendProvider).allReferrals());

/// A referral code from a link (vocationsl.com/r/CODE), kept on the device
/// until the employer has created their company.
class PendingReferral {
  static const key = 'pending_referral';

  static String? read(LocalStore store) => store.setting<String>(key);
  static Future<void> save(LocalStore store, String code) => store.setSetting(key, ReferralCode.normalize(code));
  static Future<void> clear(LocalStore store) => store.removeSetting(key);
}
