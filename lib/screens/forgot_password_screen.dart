import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/password_recovery_service.dart';
import '../data/password_policy.dart';
import '../theme/app_theme.dart';

enum _RecoveryStep { email, verification, password, complete }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.recovery});
  final PasswordRecovery? recovery;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final PasswordRecovery _recovery;
  RecoveryRequest? _request;
  _RecoveryStep _step = _RecoveryStep.email;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _recovery = widget.recovery ?? PasswordRecoveryService.instance;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step == _RecoveryStep.verification) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  int get _resendSeconds {
    if (_request == null) return 0;
    final milliseconds = _request!.resendAt
        .difference(DateTime.now())
        .inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  bool get _expired =>
      _request != null && !DateTime.now().isBefore(_request!.expiresAt);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is RecoveryException
              ? error.message
              : 'Could not complete password recovery. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      final request = await _recovery.request(_email.text);
      if (!mounted) return;
      setState(() {
        _request = request;
        _step = _RecoveryStep.verification;
      });
    });
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0) return;
    await _run(() async {
      final request = await _recovery.resend(_request!);
      if (!mounted) return;
      setState(() {
        _request = request;
        _otp.clear();
      });
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _recovery.verifyOtp(_request!, _otp.text);
      if (mounted) setState(() => _step = _RecoveryStep.password);
    });
  }

  Future<void> _checkLink() async {
    await _run(() async {
      final verified = await _recovery.checkLink(_request!);
      if (!mounted) return;
      if (verified) {
        setState(() => _step = _RecoveryStep.password);
      } else {
        throw const RecoveryException(
          'Open the link in your email and confirm it first, or enter your OTP here.',
        );
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await _recovery.complete(_request!, _password.text);
      if (!mounted) return;
      setState(() {
        _step = _RecoveryStep.complete;
        _password.clear();
        _confirmation.clear();
        _otp.clear();
        _request = null;
      });
    });
  }

  void _startAgain() {
    if (_busy) return;
    setState(() {
      _step = _RecoveryStep.email;
      _request = null;
      _error = null;
      _otp.clear();
      _password.clear();
      _confirmation.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _RecoveryStep.email => 'Forgot Your Password?',
      _RecoveryStep.verification => 'Check Your Email',
      _RecoveryStep.password => 'Create a New Password',
      _RecoveryStep.complete => 'Password Updated',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color(0xFFE3F2FD),
                        child: Icon(
                          _step == _RecoveryStep.complete
                              ? Icons.check_circle_outline
                              : Icons.lock_reset,
                          color: AppTheme.primaryBlue,
                          size: 44,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...switch (_step) {
                        _RecoveryStep.email => _emailFields(),
                        _RecoveryStep.verification => _verificationFields(),
                        _RecoveryStep.password => _passwordFields(),
                        _RecoveryStep.complete => [
                          const Text(
                            'Your password was updated on this device. Sign in with your new password.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Return to Login'),
                          ),
                        ],
                      },
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: LinearProgressIndicator(),
                        ),
                      if (_step != _RecoveryStep.complete) ...[
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailFields() => [
    const Text(
      'Enter the email registered on this device. We will send a verification link and a six-digit OTP.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    TextFormField(
      key: const ValueKey('recovery-email'),
      controller: _email,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _send(),
      decoration: const InputDecoration(
        labelText: 'Email address',
        prefixIcon: Icon(Icons.email_outlined),
      ),
      validator: (value) =>
          value == null ||
              !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
          ? 'Please enter a valid email address.'
          : null,
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _send,
      child: const Text('Send Link and OTP'),
    ),
  ];

  List<Widget> _verificationFields() => [
    Text(
      'Enter the six-digit OTP sent to ${_request!.email}, or confirm the link in that email and return here.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 12),
    Text(
      _expired
          ? 'This request has expired. Request a new email.'
          : 'The code and link expire after 10 minutes.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    TextFormField(
      key: const ValueKey('recovery-otp'),
      controller: _otp,
      enabled: !_busy && !_expired,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: const InputDecoration(
        labelText: 'Six-digit OTP',
        prefixIcon: Icon(Icons.pin_outlined),
      ),
      validator: (value) => value == null || !RegExp(r'^\d{6}$').hasMatch(value)
          ? 'Enter the six-digit OTP.'
          : null,
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _busy || _expired ? null : _verify,
      child: const Text('Verify OTP'),
    ),
    const SizedBox(height: 8),
    OutlinedButton(
      onPressed: _busy || _expired ? null : _checkLink,
      child: const Text("I've Confirmed the Email Link"),
    ),
    TextButton(
      onPressed: _busy || _resendSeconds > 0 ? null : _resend,
      child: Text(
        _resendSeconds > 0
            ? 'Resend in ${_resendSeconds}s'
            : 'Resend Link and OTP',
      ),
    ),
    TextButton(
      onPressed: _busy ? null : _startAgain,
      child: const Text('Use Another Email'),
    ),
  ];

  List<Widget> _passwordFields() => [
    const Text(
      'Email verified. $passwordRequirements',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    TextFormField(
      key: const ValueKey('recovery-password'),
      controller: _password,
      enabled: !_busy,
      obscureText: _hidePassword,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: 'New password',
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _hidePassword ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _hidePassword = !_hidePassword),
          icon: Icon(
            _hidePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: validateNewPassword,
    ),
    const SizedBox(height: 16),
    TextFormField(
      key: const ValueKey('recovery-confirmation'),
      controller: _confirmation,
      enabled: !_busy,
      obscureText: _hidePassword,
      autofillHints: const [AutofillHints.newPassword],
      decoration: const InputDecoration(labelText: 'Confirm new password'),
      validator: (value) =>
          value != _password.text || value == null || value.isEmpty
          ? 'Passwords do not match.'
          : null,
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: _busy ? null : _save,
      child: const Text('Update Password'),
    ),
    TextButton(
      onPressed: _busy ? null : _startAgain,
      child: const Text('Start Again'),
    ),
  ];
}
