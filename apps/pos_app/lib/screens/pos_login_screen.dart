import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/thq_brand_experience.dart';
import '../services/client_auth_service.dart';
import '../services/device_installation_service.dart';
import 'pos_bootstrap_screen.dart';
import 'pos_entry_screen.dart';

class PosLoginScreen extends StatefulWidget {
  const PosLoginScreen({super.key});

  @override
  State<PosLoginScreen> createState() => _PosLoginScreenState();
}

class _PosLoginScreenState extends State<PosLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _auth = ClientAuthService();

  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  Future<void> _login() async {
    if (_username.text.trim().length < 4 || _password.text.length < 8) {
      setState(() {
        _error =
            'Username must be at least 4 characters and password at least 8 characters.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _auth.signIn(username: _username.text, password: _password.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PosBootstrapScreen()),
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeBusiness() async {
    final adminUsername = TextEditingController(text: _username.text.trim());
    final adminPassword = TextEditingController();
    var hidePassword = true;

    final credentials = await showThqDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Store / Business'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Owner or administrator authorization is required before this POS can be changed.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: adminUsername,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Owner / Admin username',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adminPassword,
                  obscureText: hidePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => hidePassword = !hidePassword),
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _resetDeviceActivation();
              },
              child: const Text('Reset POS Directly'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, {
                'username': adminUsername.text.trim(),
                'password': adminPassword.text,
              }),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Authorize & Change'),
            ),
          ],
        ),
      ),
    );

    adminUsername.dispose();
    adminPassword.dispose();
    if (credentials == null || !mounted) return;

    final username = credentials['username'] ?? '';
    final password = credentials['password'] ?? '';
    if (username.length < 4 || password.length < 8) {
      setState(() {
        _error =
            'Enter a valid owner/admin username and password to change this installation.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.authorizeBindingChange(
        username: username,
        password: password,
      );
      await DeviceInstallationService().clearActivation();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PosEntryScreen()),
        (_) => false,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        final isRevoked = raw.toLowerCase().contains('revoked') ||
            raw.toLowerCase().contains('invalid') ||
            raw.toLowerCase().contains('device_invalid');
        if (isRevoked) {
          await DeviceInstallationService().clearActivation();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const PosEntryScreen()),
              (_) => false,
            );
          }
          return;
        }
        setState(
          () => _error = raw.isNotEmpty
              ? raw
              : 'Could not change this store/business. Owner/admin authorization failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetDeviceActivation() async {
    final confirmed = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset POS Terminal Registration?'),
        content: const Text(
          'This will clear the current store and business registration from this PC so you can re-activate or connect to a different store.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset & Re-activate POS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DeviceInstallationService().clearActivation();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PosEntryScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ThqBrandedLoginShell(
      appName: 'THQ POS',
      eyebrow: 'THQ POS',
      title: 'Ready to sell.',
      subtitle: 'Sign in to your activated POS terminal.',
      versionLabel: 'Windows client',
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _username,
              enabled: !_loading,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              enabled: !_loading,
              obscureText: _hidePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                    if (_error!.toLowerCase().contains('revoked') ||
                        _error!.toLowerCase().contains('invalid') ||
                        _error!.toLowerCase().contains('device') ||
                        _error!.toLowerCase().contains('activated')) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        onPressed: _loading ? null : _resetDeviceActivation,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Reset & Re-activate POS',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_loading ? 'Signing in…' : 'Open POS'),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _loading ? null : _changeBusiness,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Change Store / Business'),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _resetDeviceActivation,
                  icon: const Icon(Icons.link_off_outlined, size: 16),
                  label: const Text('Reset POS'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
