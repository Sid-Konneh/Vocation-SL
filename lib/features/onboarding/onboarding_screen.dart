import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_providers.dart';

/// Accounts created after this see the guide on their own; older accounts
/// can open it from Settings or the employer menu.
final onboardingLaunch = DateTime.utc(2026, 10, 24);

String _seenKey(String uid, UserRole role) => 'onboarding_seen:$uid:${role.name}';

bool _opening = false;

/// Opens the "how Vocation SL works" guide once for a new account on [role]'s
/// side. Call from the side's home screen; it does nothing after the first time.
void maybeShowOnboarding(BuildContext context, WidgetRef ref, UserRole role) {
  final uid = ref.read(sessionProvider);
  if (uid == null || _opening) return;
  final store = ref.read(localStoreProvider);
  if (store.setting<bool>(_seenKey(uid, role)) == true) return;
  final created = ref.read(backendProvider).accountCreatedAt;
  if (created == null || created.isBefore(onboardingLaunch)) return;
  _opening = true;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await store.setSetting(_seenKey(uid, role), true);
    _opening = false;
    if (context.mounted) context.push('/welcome/${role.name}');
  });
}

class _Page {
  const _Page(this.icon, this.step, this.title, this.body);
  final IconData icon;
  final String? step;
  final String title;
  final String body;
}

const _seekerPages = [
  _Page(Icons.waving_hand_outlined, null, 'Welcome to Vocation SL',
      'Find jobs across all 16 districts of Sierra Leone. Here\'s how it works, in three steps.'),
  _Page(Icons.person_outline_rounded, 'Step 1 of 3', 'Complete your profile',
      'Add your experience, skills and CV once. Every application uses them, so applying only takes a few minutes.'),
  _Page(Icons.search_rounded, 'Step 2 of 3', 'Search and save jobs',
      'Search by job title, district or field. Tap the bookmark to save a job, and create a job alert to hear about new ones.'),
  _Page(Icons.work_outline_rounded, 'Step 3 of 3', 'Apply and track',
      'Apply with your CV and a cover letter, both as PDFs. Follow each application under Applied, and choose your interview time when an employer offers some.'),
  _Page(Icons.shield_outlined, null, 'Stay safe',
      'Never pay a fee to apply for a job or get an interview. If a job asks for money, report it from the job page and we\'ll look into it.'),
];

const _employerPages = [
  _Page(Icons.handshake_outlined, null, 'Welcome to Vocation SL',
      'Your company is set up. Here\'s how hiring works, in four steps.'),
  _Page(Icons.verified_outlined, 'Step 1 of 4', 'Get verified',
      'Our team checks new companies. Until yours is approved, the jobs you post wait for a quick review before they go live.'),
  _Page(Icons.post_add_rounded, 'Step 2 of 4', 'Post a job',
      'Add the role, location, salary and closing date. You can ask screening questions and say which documents to attach.'),
  _Page(Icons.people_outline_rounded, 'Step 3 of 4', 'Review candidates',
      'Open each applicant to see their CV, move them through the stages, message them and offer interview times.'),
  _Page(Icons.person_search_outlined, 'Step 4 of 4', 'Find talent',
      'Once you\'re approved, search job seekers who are open to work and invite them to apply to your jobs.'),
];

/// A short swipeable guide to using Vocation SL as a job seeker or employer.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.role});
  final UserRole role;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _index = 0;

  bool get _employer => widget.role == UserRole.employer;
  List<_Page> get _pages => _employer ? _employerPages : _seekerPages;
  bool get _last => _index == _pages.length - 1;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() => _pager.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  void _finish([String? then]) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(_employer ? '/employer/dashboard' : '/jobs');
    }
    if (then != null) router.push(then);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.muted;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: TextButton(onPressed: _last ? null : () => _finish(), child: Text(_last ? '' : 'Skip')),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final p = _pages[i];
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(color: AppColors.greenTint, shape: BoxShape.circle),
                          child: Icon(p.icon, size: 56, color: AppColors.green),
                        ),
                        const SizedBox(height: 32),
                        if (p.step != null) ...[
                          Text(p.step!.toUpperCase(),
                              style: context.text.labelLarge?.copyWith(color: AppColors.green, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                          const SizedBox(height: 8),
                        ],
                        Text(p.title, textAlign: TextAlign.center, style: context.text.headlineMedium),
                        const SizedBox(height: 14),
                        Text(p.body, textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: muted, height: 1.45)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          Semantics(
            label: 'Page ${_index + 1} of ${_pages.length}',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < _pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index ? AppColors.green : muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _last
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      FilledButton(
                        onPressed: () => _finish(_employer ? '/employer/jobs/new' : '/profile/edit'),
                        child: Text(_employer ? 'Post my first job' : 'Complete my profile'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => _finish(), child: Text(_employer ? 'Go to dashboard' : 'Browse jobs')),
                    ])
                  : SizedBox(width: double.infinity, child: FilledButton(onPressed: _next, child: const Text('Next'))),
            ),
          ),
        ]),
      ),
    );
  }
}
