/// Where a referred employer is on the way to counting as a successful referral.
enum ReferralStatus {
  signedUp('Signed up', 'Company created, awaiting our review'),
  approved('Company approved', 'Approved, waiting for their first job to go live'),
  qualified('Posting jobs', 'Their jobs are going live'),
  rewarded('Rewarded', 'Reward given'),
  rejected('Not eligible', 'This referral didn\'t qualify');

  const ReferralStatus(this.label, this.description);
  final String label;
  final String description;

  /// Steps shown as progress (rejected is shown separately).
  static const steps = [signedUp, approved, qualified, rewarded];

  static ReferralStatus parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => signedUp);
}

/// An employer that signed up with a job seeker's referral code.
class Referral {
  /// Reward per referred company, set by the owner (SLE, by Mobile Money).
  static const rewardAmount = 50;

  const Referral({
    required this.id,
    required this.referrerId,
    required this.companyId,
    required this.companyName,
    required this.code,
    required this.status,
    required this.createdAt,
    this.referrerName = '',
    this.referrerEmail = '',
    this.note = '',
    this.qualifiedAt,
    this.rewardedAt,
    this.jobs = const [],
    this.payout,
  });

  final String id;
  final String referrerId;
  final String referrerName;
  final String referrerEmail;
  final String companyId;
  final String companyName;
  final String code;
  final ReferralStatus status;
  final String note;
  final DateTime createdAt;
  final DateTime? qualifiedAt;
  final DateTime? rewardedAt;

  /// Jobs the referred company has posted that went live, oldest first.
  final List<ReferralJob> jobs;
  int get jobsPosted => jobs.length;

  /// The referrer's Mobile Money account (admins only; null if not given).
  final PayoutDetails? payout;

  Referral withPayout(PayoutDetails? p) => Referral(
        id: id,
        referrerId: referrerId,
        referrerName: referrerName,
        referrerEmail: referrerEmail,
        companyId: companyId,
        companyName: companyName,
        code: code,
        status: status,
        note: note,
        createdAt: createdAt,
        qualifiedAt: qualifiedAt,
        rewardedAt: rewardedAt,
        jobs: jobs,
        payout: p,
      );

  Referral copyWith({ReferralStatus? status, String? note, DateTime? rewardedAt}) => Referral(
        id: id,
        referrerId: referrerId,
        referrerName: referrerName,
        referrerEmail: referrerEmail,
        companyId: companyId,
        companyName: companyName,
        code: code,
        status: status ?? this.status,
        note: note ?? this.note,
        createdAt: createdAt,
        qualifiedAt: qualifiedAt,
        rewardedAt: rewardedAt ?? this.rewardedAt,
        jobs: jobs,
        payout: payout,
      );

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
        id: j['id'] as String,
        referrerId: j['referrer_id'] as String,
        referrerName: j['referrer_name'] as String? ?? '',
        referrerEmail: j['referrer_email'] as String? ?? '',
        companyId: j['company_id'] as String? ?? '',
        companyName: j['company_name'] as String? ?? '',
        code: j['code'] as String? ?? '',
        status: ReferralStatus.parse(j['status'] as String?),
        note: j['note'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        qualifiedAt: j['qualified_at'] == null ? null : DateTime.parse(j['qualified_at'] as String),
        rewardedAt: j['rewarded_at'] == null ? null : DateTime.parse(j['rewarded_at'] as String),
        jobs: [for (final x in (j['jobs'] as List? ?? const [])) ReferralJob.fromJson(Map<String, dynamic>.from(x as Map))],
      );
}

/// A job posted by a referred company that went live.
class ReferralJob {
  const ReferralJob({required this.jobId, required this.title, required this.publishedAt});
  final String jobId;
  final String title;
  final DateTime publishedAt;

  factory ReferralJob.fromJson(Map<String, dynamic> j) => ReferralJob(
        jobId: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        publishedAt: DateTime.tryParse(j['published_at'] as String? ?? '') ?? DateTime.now(),
      );
}

enum MobileMoneyProvider {
  orange('Orange Money'),
  africell('Africell Money');

  const MobileMoneyProvider(this.label);
  final String label;

  static MobileMoneyProvider? parse(String? s) => values.where((v) => v.name == s).firstOrNull;
}

/// Where a referrer's rewards are sent.
class PayoutDetails {
  const PayoutDetails({required this.provider, required this.number, required this.accountName, this.updatedAt});
  final MobileMoneyProvider provider;

  /// Stored as +232XXXXXXXX.
  final String number;
  final String accountName;
  final DateTime? updatedAt;

  /// 076 123 456 style, as people read it in Sierra Leone.
  String get displayNumber {
    final d = PayoutDetails.localDigits(number);
    return d == null ? number : '0${d.substring(0, 2)} ${d.substring(2, 5)} ${d.substring(5)}';
  }

  String get summary => '${provider.label} · $displayNumber · $accountName';

  /// The 8 digits after the country code / leading 0, or null if it isn't a
  /// Sierra Leone mobile number.
  static String? localDigits(String input) {
    var d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('232')) {
      d = d.substring(3);
    } else if (d.startsWith('0')) {
      d = d.substring(1);
    }
    return d.length == 8 ? d : null;
  }

  /// Reads the payout columns of a referral_codes row; null if not set.
  static PayoutDetails? fromJson(Map<String, dynamic>? j) {
    final provider = MobileMoneyProvider.parse(j?['payout_provider'] as String?);
    final number = j?['payout_number'] as String? ?? '';
    if (j == null || provider == null || number.isEmpty) return null;
    return PayoutDetails(
      provider: provider,
      number: number,
      accountName: j['payout_name'] as String? ?? '',
      updatedAt: j['payout_updated_at'] == null ? null : DateTime.parse(j['payout_updated_at'] as String),
    );
  }
}

/// Referral codes look like VSL-7KQ2M. People type them by hand, so they are
/// matched without spaces, dashes or case.
class ReferralCode {
  static String normalize(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// The code as people should read and type it, e.g. VSL-7KQ2M.
  static String display(String code) {
    final c = normalize(code);
    return c.length > 3 && c.startsWith('VSL') ? 'VSL-${c.substring(3)}' : c;
  }

  /// Link an employer opens to sign up with this code.
  static String link(String code, {String base = 'https://employers.vocationsl.com'}) => '$base/r/${normalize(code)}';
}

/// Totals for the referral screen.
class ReferralSummary {
  const ReferralSummary(this.referrals);
  final List<Referral> referrals;

  int get total => referrals.where((r) => r.status != ReferralStatus.rejected).length;
  int get qualified => referrals.where((r) => r.status == ReferralStatus.qualified || r.status == ReferralStatus.rewarded).length;
  int get rewarded => referrals.where((r) => r.status == ReferralStatus.rewarded).length;
  int get jobsPosted => referrals.where((r) => r.status != ReferralStatus.rejected).fold(0, (n, r) => n + r.jobsPosted);
  int get inProgress => referrals.where((r) => r.status == ReferralStatus.signedUp || r.status == ReferralStatus.approved).length;
}
