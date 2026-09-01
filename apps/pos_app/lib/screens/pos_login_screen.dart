import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    final credentials = await showDialog<Map<String, String>>(
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
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not change this store/business. Owner/admin authorization failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              Colors.white,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(34),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [scheme.primary, scheme.tertiary],
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.point_of_sale,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'THQ POS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Fast counter billing',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
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
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
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
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.onErrorContainer),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(_loading ? 'Signing in…' : 'Open POS'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loading ? null : _changeBusiness,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Change Store / Business'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
