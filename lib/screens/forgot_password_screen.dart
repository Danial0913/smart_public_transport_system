import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();

  bool _resetLinkSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address.';
    }

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!emailPattern.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }

    return null;
  }

  void _sendResetLink() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _resetLinkSent = true;
    });
  }

  void _resendLink() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Another reset link has been sent to '
          '${_emailController.text.trim()}.',
        ),
      ),
    );
  }

  void _changeEmail() {
    setState(() {
      _resetLinkSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reset Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _resetLinkSent ? _buildSuccessView() : _buildResetForm(),
        ),
      ),
    );
  }

  Widget _buildResetForm() {
    return SingleChildScrollView(
      key: const ValueKey('reset-form'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE3F2FD),
              ),
              child: const Icon(
                Icons.lock_reset,
                color: AppTheme.primaryBlue,
                size: 48,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Forgot Your Password?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.mainText,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Enter your registered email address to receive '
              'a password reset link.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.secondaryText),
            ),

            const SizedBox(height: 32),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Email Address',
                style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
              ),
            ),

            const SizedBox(height: 8),

            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _sendResetLink(),
              decoration: const InputDecoration(
                hintText: 'name@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: _validateEmail,
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _sendResetLink,
                child: const Text(
                  'Send Reset Link',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 16),

            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return SingleChildScrollView(
      key: const ValueKey('success-view'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE8F5E9),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFF2E7D32),
              size: 48,
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Reset Link Sent',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.mainText,
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'A password reset link has been sent to:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.secondaryText),
          ),

          const SizedBox(height: 8),

          Text(
            _emailController.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'Please check your inbox and follow the instructions '
            'to create a new password.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.secondaryText),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Return to Login',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 12),

          TextButton(onPressed: _resendLink, child: const Text('Resend Link')),

          TextButton(
            onPressed: _changeEmail,
            child: const Text('Use Another Email'),
          ),
        ],
      ),
    );
  }
}
