import 'package:flutter/material.dart';
import '../data/account_settings.dart';
import '../data/password_policy.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    required this.account,
    this.changePassword = false,
  });
  final AccountSettings account;
  final bool changePassword;
  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _visible = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.account.currentUser.value;
    _name.text = user?.fullName ?? '';
    _email.text = user?.email ?? '';
    _phone.text = user?.phone ?? '';
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _phone,
      _current,
      _password,
      _confirmation,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.changePassword) {
        await widget.account.changePassword(
          currentPassword: _current.text,
          newPassword: _password.text,
        );
      } else {
        await widget.account.updateProfile(
          fullName: _name.text,
          email: _email.text,
          phone: _phone.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AccountSettingsException
              ? error.message
              : 'Could not save your changes. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _passwordField(
    String key,
    String label,
    TextEditingController controller,
    String? Function(String?) validator,
  ) {
    final visible = _visible.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_saving,
        obscureText: !visible,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [
          key == 'current-password'
              ? AutofillHints.password
              : AutofillHints.newPassword,
        ],
        decoration: InputDecoration(
          labelText: label,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: visible ? 'Hide password' : 'Show password',
            onPressed: () => setState(
              () => visible ? _visible.remove(key) : _visible.add(key),
            ),
            icon: Icon(
              visible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final changing = widget.changePassword;
    return Scaffold(
      appBar: AppBar(
        title: Text(changing ? 'Change Password' : 'Edit Profile'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                changing
                    ? passwordRequirements
                    : 'Update your account details. '
                          'If you change your email, use the new address to log in and recover your password.',
              ),
              const SizedBox(height: 24),
              if (!changing) ...[
                TextFormField(
                  key: const ValueKey('profile-name'),
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: validateProfileName,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('profile-email'),
                  controller: _email,
                  enabled: !_saving,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: validateProfileEmail,
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('profile-phone'),
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: validateProfilePhone,
                ),
                const SizedBox(height: 18),
              ],
              if (changing)
                _passwordField(
                  'current-password',
                  'Current password',
                  _current,
                  (value) => value == null || value.isEmpty
                      ? 'Enter your current password.'
                      : null,
                ),
              if (changing) ...[
                _passwordField(
                  'new-password',
                  'New password',
                  _password,
                  (value) =>
                      validateNewPassword(value) ??
                      (value == _current.text
                          ? 'Choose a password different from your current password.'
                          : null),
                ),
                _passwordField(
                  'confirm-password',
                  'Confirm new password',
                  _confirmation,
                  (value) =>
                      value == null || value.isEmpty || value != _password.text
                      ? 'Passwords do not match.'
                      : null,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Saving…'
                      : changing
                      ? 'Update Password'
                      : 'Save Changes',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
