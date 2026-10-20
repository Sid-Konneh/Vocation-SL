import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors.dart';
import '../../models/models.dart';
import 'supabase_backend.dart' show guardSupabase;

/// Job seekers refer employers. A referral is recorded when a new company
/// signs up with a code, and the database moves it along as the company is
/// approved and its first job goes live (see supabase/referrals.sql).
abstract interface class ReferralBackend {
  /// The signed-in user's referral code, created on first use.
  Future<String> myCode();

  /// Employers the signed-in user has referred, newest first.
  Future<List<Referral>> myReferrals();

  /// Links a newly registered company to the owner of [code].
  Future<void> claim(String code, String companyId);

  /// What referrers receive, as set by the Vocation SL team. Empty if not set.
  Future<String> rewardText();

  /// Where the signed-in user's rewards are sent (null until they add it).
  Future<PayoutDetails?> myPayout();
  Future<void> savePayout(MobileMoneyProvider provider, String number, String accountName);

  // Admin (referrals include each referrer's Mobile Money account)
  Future<List<Referral>> allReferrals();
  Future<void> setStatus(String referralId, ReferralStatus status, {String note = ''});
  Future<void> saveRewardText(String text);
}

class SupabaseReferralBackend implements ReferralBackend {
  SupabaseReferralBackend(this._client);
  final sb.SupabaseClient _client;

  String _uid() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<String> myCode() => guardSupabase(() async => (await _client.rpc('my_referral_code')) as String);

  @override
  Future<List<Referral>> myReferrals() => guardSupabase(() async {
        final rows = await _client.from('referrals').select().eq('referrer_id', _uid()).order('created_at', ascending: false);
        return rows.map(Referral.fromJson).toList();
      });

  @override
  Future<void> claim(String code, String companyId) =>
      guardSupabase(() => _client.rpc('claim_referral', params: {'p_code': ReferralCode.normalize(code), 'p_company': companyId}));

  @override
  Future<String> rewardText() async {
    try {
      final row = await _client.from('platform_settings').select('value').eq('key', 'referral_reward').maybeSingle();
      return (row?['value'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<PayoutDetails?> myPayout() => guardSupabase(() async {
        final row = await _client.from('referral_codes').select().eq('user_id', _uid()).maybeSingle();
        return PayoutDetails.fromJson(row);
      });

  @override
  Future<void> savePayout(MobileMoneyProvider provider, String number, String accountName) => guardSupabase(() => _client
      .rpc('save_referral_payout', params: {'p_provider': provider.name, 'p_number': number, 'p_name': accountName.trim()}));

  @override
  Future<List<Referral>> allReferrals() => guardSupabase(() async {
        final rows = await _client.from('referrals').select().order('created_at', ascending: false);
        final list = rows.map(Referral.fromJson).toList();
        final ids = {for (final r in list) r.referrerId}.toList();
        if (ids.isEmpty) return list;
        try {
          final codes = await _client.from('referral_codes').select().inFilter('user_id', ids);
          final payouts = {for (final c in codes) c['user_id'] as String: PayoutDetails.fromJson(c)};
          return [for (final r in list) r.withPayout(payouts[r.referrerId])];
        } catch (_) {
          return list; // payout columns not installed yet
        }
      });

  @override
  Future<void> setStatus(String referralId, ReferralStatus status, {String note = ''}) => guardSupabase(
      () => _client.rpc('admin_set_referral', params: {'p_id': referralId, 'p_status': status.name, 'p_note': note}));

  @override
  Future<void> saveRewardText(String text) =>
      guardSupabase(() => _client.from('platform_settings').upsert({'key': 'referral_reward', 'value': text.trim()}));
}

/// In-memory referrals for demo mode and tests.
class DemoReferralBackend implements ReferralBackend {
  DemoReferralBackend({this.userId = 'demo-user'});
  final String userId;

  final _codes = <String, String>{}; // user id -> code
  final referrals = <Referral>[];
  String _reward = '';
  final _payouts = <String, PayoutDetails>{};

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I/L

  @override
  Future<String> myCode() async => _codes.putIfAbsent(userId, () {
        final r = Random();
        return 'VSL${List.generate(5, (_) => _alphabet[r.nextInt(_alphabet.length)]).join()}';
      });

  @override
  Future<List<Referral>> myReferrals() async =>
      referrals.where((r) => r.referrerId == userId).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// [asUser] is the employer claiming; in the demo it defaults to someone else.
  @override
  Future<void> claim(String code, String companyId, {String asUser = 'demo-employer', String companyName = 'Demo company'}) async {
    final normalized = ReferralCode.normalize(code);
    final owner = _codes.entries.where((e) => e.value == normalized).firstOrNull?.key;
    if (owner == null) throw const ValidationException('That referral code wasn\'t found. Check it and try again.');
    if (owner == asUser) throw const ValidationException('You can\'t use your own referral code.');
    if (referrals.any((r) => r.companyId == companyId)) return;
    referrals.add(Referral(
      id: 'ref-${referrals.length + 1}',
      referrerId: owner,
      companyId: companyId,
      companyName: companyName,
      code: normalized,
      status: ReferralStatus.signedUp,
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<String> rewardText() async => _reward;

  @override
  Future<PayoutDetails?> myPayout() async => _payouts[userId];

  @override
  Future<void> savePayout(MobileMoneyProvider provider, String number, String accountName) async {
    final digits = PayoutDetails.localDigits(number);
    if (digits == null) throw const ValidationException('Enter a Sierra Leone mobile number, e.g. 076 123 456.');
    if (accountName.trim().length < 3) throw const ValidationException('Enter the name on the Mobile Money account.');
    _payouts[userId] = PayoutDetails(provider: provider, number: '+232$digits', accountName: accountName.trim(), updatedAt: DateTime.now());
  }

  @override
  Future<List<Referral>> allReferrals() async => [for (final r in referrals.reversed) r.withPayout(_payouts[r.referrerId])];

  @override
  Future<void> setStatus(String referralId, ReferralStatus status, {String note = ''}) async {
    final i = referrals.indexWhere((r) => r.id == referralId);
    if (i < 0) throw const NotFoundException('Referral not found');
    referrals[i] = referrals[i].copyWith(status: status, note: note, rewardedAt: status == ReferralStatus.rewarded ? DateTime.now() : null);
  }

  @override
  Future<void> saveRewardText(String text) async => _reward = text.trim();
}
