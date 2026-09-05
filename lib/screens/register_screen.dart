import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_storage_service.dart';
import '../data/password_policy.dart';
import '../theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() {
    return _RegisterScreenState();
  }
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  final LocalStorageService _storage = LocalStorageService.instance;

  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _showTermsError = false;
  bool _registering = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your full name.';
    }

    if (value.trim().length < 2) {
      return 'Name must contain at least 2 characters.';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address.';
    }

    final emailPattern = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.(com|my|com\.my|edu\.my|gov\.my)$',
    );

    if (!emailPattern.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }

    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number.';
    }

    final phone = value.replaceAll(RegExp(r'[\s-]'), '');

    final phonePattern = RegExp(r'^(?:\+?60|0)(?:11[0-9]{8}|1[0-9]{7,8})$');

    if (!phonePattern.hasMatch(phone)) {
      return 'Please enter a valid Malaysian phone number.';
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password.';
    }

    if (value != _passwordCtrl.text) {
      return 'Passwords do not match.';
    }

    return null;
  }

  Future<void> _register() async {
    final formIsValid = _formKey.currentState!.validate();

    setState(() {
      _showTermsError = !_acceptedTerms;
    });

    if (!formIsValid || !_acceptedTerms) {
      return;
    }

    if (_registering) {
      return;
    }

    setState(() {
      _registering = true;
    });

    try {
      final email = _emailCtrl.text.trim().toLowerCase();

      final alreadyRegistered = await _storage.emailExists(email);

      if (!mounted) {
        return;
      }

      if (alreadyRegistered) {
        setState(() {
          _registering = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An account already exists with this email.'),
          ),
        );

        return;
      }

      await _storage.registerUser(
        fullName: _nameCtrl.text,
        email: email,
        phone: _phoneCtrl.text,
        password: _passwordCtrl.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _registering = false;
      });

      final returnToLogin = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle,
              color: AppTheme.primaryBlue,
              size: 48,
            ),
            title: const Text('Account Created'),
            content: const Text(
              'Your account has been created successfully. '
              'You can now log in using your email and password.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Return to Login'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      if (returnToLogin == true) {
        Navigator.pop(context, email);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _registering = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to create account: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Register',
                  style: TextStyle(
                    color: AppTheme.mainText,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Create an account to save your transport preferences and journeys.',
                  style: TextStyle(color: AppTheme.secondaryText),
                ),

                const SizedBox(height: 28),

                TextFormField(
                  controller: _nameCtrl,
                  enabled: !_registering,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: _validateName,
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _emailCtrl,
                  enabled: !_registering,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _validateEmail,
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _phoneCtrl,
                  enabled: !_registering,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+60 12-345 6789',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: _validatePhone,
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _passwordCtrl,
                  enabled: !_registering,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: passwordRequirements,
                    helperMaxLines: 5,
                    errorMaxLines: 3,
                    hintText: 'At least 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: validateNewPassword,
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _confirmPasswordCtrl,
                  enabled: !_registering,
                  obscureText: _hideConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    _register();
                  },
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Enter your password again',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hideConfirmPassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () {
                        setState(() {
                          _hideConfirmPassword = !_hideConfirmPassword;
                        });
                      },
                      icon: Icon(
                        _hideConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: _validateConfirmPassword,
                ),

                const SizedBox(height: 14),

                CheckboxListTile(
                  value: _acceptedTerms,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I agree to the Terms of Service '
                    'and Privacy Policy.',
                    style: TextStyle(fontSize: 14),
                  ),
                  onChanged: _registering
                      ? null
                      : (value) {
                          setState(() {
                            _acceptedTerms = value ?? false;
                            _showTermsError = false;
                          });
                        },
                ),

                if (_showTermsError)
                  const Padding(
                    padding: EdgeInsets.only(left: 12, bottom: 8),
                    child: Text(
                      'Please accept the Terms of Service '
                      'and Privacy Policy.',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _registering ? null : _register,
                    child: _registering
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Create Account',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account?',
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                    TextButton(
                      onPressed: _registering
                          ? null
                          : () {
                              Navigator.pop(context);
                            },
                      child: const Text(
                        'Log In',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
