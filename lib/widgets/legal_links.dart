import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

/// "By continuing, you agree to our Terms of Use…" with tappable links.
class LegalNotice extends StatefulWidget {
  const LegalNotice({super.key, this.action = 'continuing'});

  /// e.g. "creating an account" or "signing in".
  final String action;

  @override
  State<LegalNotice> createState() => _LegalNoticeState();
}

class _LegalNoticeState extends State<LegalNotice> {
  late final _terms = TapGestureRecognizer()..onTap = () => context.push('/pages/terms');
  late final _privacy = TapGestureRecognizer()..onTap = () => context.push('/pages/privacy');

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.text.bodySmall?.copyWith(color: context.palette.muted);
    final link = base?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: 'By ${widget.action}, you agree to our '),
        TextSpan(text: 'Terms of Use', style: link, recognizer: _terms, semanticsLabel: 'Terms of Use, link'),
        const TextSpan(text: ' and confirm you have read our '),
        TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy, semanticsLabel: 'Privacy Policy, link'),
        const TextSpan(text: '.'),
      ]),
      textAlign: TextAlign.center,
    );
  }
}

/// List rows for Settings: Help, Terms of Use, Privacy Policy.
class LegalTiles extends StatelessWidget {
  const LegalTiles({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (slug, title, icon) in const [
          ('help', 'Help & FAQs', Icons.help_outline_rounded),
          ('terms', 'Terms of Use', Icons.gavel_rounded),
          ('privacy', 'Privacy Policy', Icons.privacy_tip_outlined),
        ])
          ListTile(
            leading: Icon(icon),
            title: Text(title),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/pages/$slug'),
          ),
      ]);
}
