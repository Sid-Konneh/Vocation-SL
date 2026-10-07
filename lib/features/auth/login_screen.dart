import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/demo/demo_seed.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/vocation_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.forEmployers = false});
  final bool forEmployers;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({bool demo = false}) async {
    if (demo) {
      _email.text = demoEmail;
      _password.text = demoPassword;
      _signUp = false;
    }
    await _run(() async {
      final session = ref.read(sessionProvider.notifier);
      if (_signUp) {
        await session.signUp(_name.text, _email.text, _password.text);
      } else {
        await session.signIn(_email.text, _password.text);
      }
      // The router redirects to /jobs when the session changes.
    });
  }

  Future<void> _google() => _run(() => ref.read(sessionProvider.notifier).signInWithGoogle());

  Future<void> _forgotPassword() => _run(() async {
        await ref.read(userRepositoryProvider).sendPasswordReset(_email.text);
        if (mounted) {
          setState(() => _info = 'If an account exists for ${_email.text.trim()}, we\'ve sent a link to reset the password.');
        }
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on EmailConfirmationRequired catch (e) {
      setState(() {
        _info = e.userMessage;
        _signUp = false;
        _password.clear();
      });
    } catch (e) {
      setState(() => _error = AppException.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = isDemoBackend(ref.watch(backendProvider));
    final supportsGoogle = ref.watch(userRepositoryProvider).supportsGoogleSignIn;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: VocationMark(size: 56)),
                  const SizedBox(height: 28),
                  Text(_signUp ? (widget.forEmployers ? 'Create an employer account' : 'Create your account') : (widget.forEmployers ? 'Employer sign in' : 'Welcome back'), style: context.text.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    widget.forEmployers
                        ? 'Post jobs and review candidates for your company.'
                        : _signUp
                            ? 'Find and apply for jobs across Sierra Leone.'
                            : 'Sign in to find jobs, track applications and get alerts.',
                    style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
                  ),
                  const SizedBox(height: 28),
                  if (isDemo) ...[
                    _DemoCard(onTap: _busy ? null : () => _submit(demo: true), busy: _busy),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or use email', style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 24),
                  ],
                  if (supportsGoogle) ...[
                    OutlinedButton(
                      onPressed: _busy ? null : _google,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const _GoogleMark(),
                        const SizedBox(width: 12),
                        Text(_signUp ? 'Sign up with Google' : 'Continue with Google'),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or use email', style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
                      ),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 24),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _signUp
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: TextField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (!_signUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  if (_info != null) ...[
                    const SizedBox(height: 14),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: context.palette.accentTint, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(Icons.mark_email_read_outlined, color: context.colors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_info!, style: context.text.bodyMedium)),
                        ]),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: context.text.bodyMedium)),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(label: _signUp ? 'Create account' : 'Sign in', loading: _busy, onPressed: () => _submit()),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                      _info = null;
                    }),
                    child: Text(_signUp ? 'Already have an account? Sign in' : 'New to Vocation SL? Create an account'),
                  ),
                  if (isDemo) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Demo mode: employers and jobs are fictional examples. No data leaves this device.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(color: context.palette.muted),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google's standard four-colour "G" for sign-in buttons (per Google's
/// sign-in branding guidelines).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_svg, width: 20, height: 20, semanticsLabel: 'Google');
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
        color: context.palette.accentTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: context.colors.primary.withValues(alpha: 0.3))),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.primary,
                child: Icon(Icons.bolt_rounded, color: context.colors.onPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Continue with demo account', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$demoEmail · $demoPassword', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                ]),
              ),
              Icon(Icons.arrow_forward_rounded, color: context.colors.primary),
            ]),
          ),
        ),
      );
}
