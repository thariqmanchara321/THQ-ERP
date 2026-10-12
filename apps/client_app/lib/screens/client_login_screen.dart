import 'dart:async';
import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/thq_brand_experience.dart';
import '../services/client_auth_service.dart';
import '../services/device_installation_service.dart';
import 'client_bootstrap_screen.dart';
import 'client_entry_screen.dart';

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _usernameController = TextEditingController();

  final _passwordController = TextEditingController();

  final ClientAuthService _authService = ClientAuthService();

  bool _loading = false;
  bool _hidePassword = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyActivationOnline());
  }

  Future<void> _verifyActivationOnline() async {
    final act = await DeviceInstallationService().readAndVerifyActivation();
    if (act == null && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();

    final password = _passwordController.text;

    if (username.length < 4 || password.length < 8) {
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
      await _authService.signIn(username: username, password: password);
      TextInput.finishAutofillContext();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ClientBootstrapScreen()),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      final isRevokedOrDeleted = error.message.toLowerCase().contains('business_deleted') ||
          error.message.toLowerCase().contains('device_revoked') ||
          error.message.toLowerCase().contains('inactive') ||
          error.message.toLowerCase().contains('revoked') ||
          error.message.toLowerCase().contains('device_invalid') ||
          error.message.toLowerCase().contains('not found');
      if (isRevokedOrDeleted) {
        await DeviceInstallationService().clearActivation();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
            (_) => false,
          );
        }
        return;
      }

      setState(() {
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final isRevokedOrDeleted = raw.toLowerCase().contains('business_deleted') ||
          raw.toLowerCase().contains('device_revoked') ||
          raw.toLowerCase().contains('inactive') ||
          raw.toLowerCase().contains('revoked') ||
          raw.toLowerCase().contains('device_invalid') ||
          raw.toLowerCase().contains('not found');
      if (isRevokedOrDeleted) {
        await DeviceInstallationService().clearActivation();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
            (_) => false,
          );
        }
        return;
      }

      setState(() {
        _error = raw.isNotEmpty ? raw : 'Login failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _changeBusiness() async {
    final adminUsername = TextEditingController(
      text: _usernameController.text.trim(),
    );
    final adminPassword = TextEditingController();
    var hidePassword = true;

    final credentials = await showThqDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Store / Business Binding'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Owner or administrator authorization is required to release this system binding and connect to a different store or business.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: adminUsername,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Owner / Admin username',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    border: OutlineInputBorder(),
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
                    border: const OutlineInputBorder(),
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
              child: const Text('Reset PC Directly'),
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
              label: const Text('Authorize & Reset Binding'),
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
      await _authService.authorizeBindingChange(
        username: username,
        password: password,
      );
      await DeviceInstallationService().clearActivation();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
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
          // If the server confirmed registration is already revoked/invalid, release local binding directly
          await DeviceInstallationService().clearActivation();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
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
        title: const Text('Reset PC Store Registration?'),
        content: const Text(
          'This will clear the current store and business registration from this PC so you can connect to a different store or enter a new activation code.',
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
            child: const Text('Reset & Re-activate PC'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DeviceInstallationService().clearActivation();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThqBrandedLoginShell(
      appName: 'THQ Business',
      footer: const Text('Accounting • Inventory • Business Management'),
      versionLabel: 'Windows client',
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _usernameController,
              enabled: !_loading,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: _passwordController,
              enabled: !_loading,
              obscureText: _hidePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,

              onSubmitted: (_) {
                if (!_loading) {
                  _login();
                }
              },

              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _loading
                      ? null
                      : () {
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
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onError,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onError,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error!.toLowerCase().contains('revoked') ||
                        _error!.toLowerCase().contains('invalid') ||
                        _error!.toLowerCase().contains('device') ||
                        _error!.toLowerCase().contains('activated')) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.onError,
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _loading ? null : _resetDeviceActivation,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(
                          'Reset & Re-activate This PC',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign In'),
              ),
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
                  label: const Text('Reset PC'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
