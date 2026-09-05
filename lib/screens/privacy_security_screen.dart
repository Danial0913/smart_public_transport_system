import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/account_settings.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key, required this.account});
  final AccountSettings account;
  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool? _saveSearches;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final value = await widget.account.getSearchHistoryEnabled();
      if (mounted) setState(() => _saveSearches = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load privacy settings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() operation, String message) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not complete this action. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent searches?'),
        content: const Text(
          'This permanently removes recent searches stored on this device for all accounts. '
          'Saved journeys, favourites, and completed travel history will remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Searches'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(
        widget.account.clearRecentSearches,
        'Recent searches cleared.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy and Security')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('Your data on this device'),
            subtitle: Text(
              'Your account details and travel records are stored on this device. '
              'Recent searches are shared by accounts using this app on this device. '
              'Password recovery sends your email address to the recovery service.',
            ),
          ),
          const SizedBox(height: 16),
          if (_saveSearches != null)
            SwitchListTile(
              title: const Text('Save recent searches'),
              subtitle: const Text(
                'Remember future journey searches on this device. Turning this off keeps existing searches until you clear them.',
              ),
              value: _saveSearches!,
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                      await widget.account.setSearchHistoryEnabled(value);
                      if (mounted) setState(() => _saveSearches = value);
                    }, 'Privacy setting saved.'),
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Clear recent searches'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy || _saveSearches == null ? null : _clear,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Manage app permissions'),
            subtitle: const Text(
              'Control location and notification permissions in your phone settings.',
            ),
            trailing: const Icon(Icons.open_in_new),
            onTap: _busy
                ? null
                : () => _run(() async {
                    if (!await openAppSettings()) {
                      throw StateError('Device settings unavailable');
                    }
                  }, 'App permission settings opened.'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (_saveSearches == null)
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry'),
              ),
          ],
        ],
      ),
    ),
  );
}
