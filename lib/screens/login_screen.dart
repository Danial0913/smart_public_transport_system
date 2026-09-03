import 'package:flutter/material.dart';

import '../data/local_storage_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() {
    return _LoginScreenState();
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final LocalStorageService _storage =
      LocalStorageService.instance;

  bool _hidePassword = true;
  bool _loggingIn = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address.';
    }

    final emailPattern = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    );

    if (!emailPattern.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password.';
    }

    return null;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_loggingIn) {
      return;
    }

    setState(() {
      _loggingIn = true;
    });

    try {
      final user = await _storage.loginUser(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );

      if (!mounted) {
        return;
      }

      if (user == null) {
        setState(() {
          _loggingIn = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Incorrect email address or password.',
            ),
          ),
        );

        return;
      }

      setState(() {
        _loggingIn = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) {
            return const DashboardScreen();
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loggingIn = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to log in: $error'),
        ),
      );
    }
  }

  Future<void> _openRegisterScreen() async {
    final registeredEmail =
    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const RegisterScreen();
        },
      ),
    );

    if (!mounted || registeredEmail == null) {
      return;
    }

    _emailCtrl.text = registeredEmail;
    _passwordCtrl.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Account created. Enter your password to log in.',
        ),
      ),
    );
  }

  void _openForgotPasswordScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return const ForgotPasswordScreen();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                Center(
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      borderRadius:
                      BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.directions_transit,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),

                const SizedBox(height: 42),

                const Text(
                  'Welcome Back',
                  style: TextStyle(
                    color: AppTheme.mainText,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Log in to continue your journey.',
                  style: TextStyle(
                    color: AppTheme.secondaryText,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 28),

                TextFormField(
                  controller: _emailCtrl,
                  enabled: !_loggingIn,
                  keyboardType:
                  TextInputType.emailAddress,
                  textInputAction:
                  TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.email,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'name@example.com',
                    prefixIcon:
                    Icon(Icons.email_outlined),
                  ),
                  validator: _validateEmail,
                ),

                const SizedBox(height: 18),

                TextFormField(
                  controller: _passwordCtrl,
                  enabled: !_loggingIn,
                  obscureText: _hidePassword,
                  textInputAction:
                  TextInputAction.done,
                  autofillHints: const [
                    AutofillHints.password,
                  ],
                  onFieldSubmitted: (_) {
                    _login();
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon:
                    const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () {
                        setState(() {
                          _hidePassword =
                          !_hidePassword;
                        });
                      },
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons
                            .visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: _validatePassword,
                ),

                const SizedBox(height: 6),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loggingIn
                        ? null
                        : _openForgotPasswordScreen,
                    child: const Text(
                      'Forgot Password?',
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed:
                    _loggingIn ? null : _login,
                    child: _loggingIn
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Log In',
                      style: TextStyle(
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Do not have an account?',
                      style: TextStyle(
                        color:
                        AppTheme.secondaryText,
                      ),
                    ),
                    TextButton(
                      onPressed: _loggingIn
                          ? null
                          : _openRegisterScreen,
                      child: const Text(
                        'Register',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}