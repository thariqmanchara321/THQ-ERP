import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import '../services/device_installation_service.dart';
import '../services/mobile_pos_auth_service.dart';
import '../services/mobile_pos_session_service.dart';
import 'mobile_pos_home_screen.dart';

class MobilePosEntryScreen extends StatefulWidget {
  const MobilePosEntryScreen({super.key});

  @override
  State<MobilePosEntryScreen> createState() => _MobilePosEntryScreenState();
}

class _MobilePosEntryScreenState extends State<MobilePosEntryScreen> {
  late Future<DeviceActivation?> _activation;

  @override
  void initState() {
    super.initState();
    _activation = DeviceInstallationService().readActivation();
  }

  void _reloadActivation() {
    setState(() {
      _activation = DeviceInstallationService().readActivation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceActivation?>(
      future: _activation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ThqMobileLoadingPage(label: 'Checking this terminal…');
        }
        if (snapshot.hasError) {
          return ThqMobileFailurePage(
            title: 'Terminal check failed',
            message: snapshot.error.toString(),
            onRetry: _reloadActivation,
          );
        }
        if (snapshot.data == null) {
          return _ActivationView(onDone: _reloadActivation);
        }
        if (Supabase.instance.client.auth.currentSession == null) {
          return _LoginView(onDone: () => setState(() {}));
        }
        return const _SessionLoader();
      },
    );
  }
}

class _ActivationView extends StatefulWidget {
  final VoidCallback onDone;

  const _ActivationView({required this.onDone});

  @override
  State<_ActivationView> createState() => _ActivationViewState();
}

class _ActivationViewState extends State<_ActivationView> {
  final _business = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _business.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    if (_business.text.trim().isEmpty || _code.text.trim().isEmpty) {
      setState(() => _error = 'Enter both the business code and activation code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DeviceInstallationService().activate(
        businessCode: _business.text,
        activationCode: _code.text,
      );
      widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThqMobileAccessScaffold(
      eyebrow: 'THQ POS • SECURE TERMINAL',
      title: 'Connect this counter',
      subtitle:
          'Activate once with the POS terminal code issued from THQ Admin. Sales remain bound to this authorized device and store.',
      icon: Icons.point_of_sale_rounded,
      versionLabel: ThqMobileReleaseContract.versionLabel,
      footer: const Text(
        'THQ ERP • Mobile POS',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      child: Column(
        children: [
          TextField(
            controller: _business,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Business code',
              hintText: 'Example: THQ001',
              prefixIcon: Icon(Icons.domain_outlined),
            ),
          ),
          const SizedBox(height: 11),
          TextField(
            controller: _code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _activate(),
            decoration: const InputDecoration(
              labelText: 'Activation code',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 11),
            ThqMobileInlineMessage(message: _error!, error: true),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _activate,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.phonelink_lock_rounded),
              label: Text(_busy ? 'Activating…' : 'Activate Mobile POS'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginView extends StatefulWidget {
  final VoidCallback onDone;

  const _LoginView({required this.onDone});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MobilePosAuthService().signIn(
        username: _username.text,
        password: _password.text,
      );
      widget.onDone();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThqMobileAccessScaffold(
      eyebrow: 'THQ POS • FAST COUNTER ACCESS',
      title: 'Ready to sell',
      subtitle:
          'Sign in to this activated terminal. Store, terminal and module permissions are enforced before the POS workspace opens.',
      icon: Icons.point_of_sale_rounded,
      versionLabel: ThqMobileReleaseContract.versionLabel,
      footer: const Text(
        'Offline-ready • GST-authoritative sync',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      child: AutofillGroup(
        child: Column(
          children: [
            TextField(
              controller: _username,
              enabled: !_busy,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 11),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 11),
              ThqMobileInlineMessage(message: _error!, error: true),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(_busy ? 'Signing in…' : 'Open POS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionLoader extends StatefulWidget {
  const _SessionLoader();

  @override
  State<_SessionLoader> createState() => _SessionLoaderState();
}

class _SessionLoaderState extends State<_SessionLoader> {
  late Future _future;

  @override
  void initState() {
    super.initState();
    _future = MobilePosSessionService().load();
  }

  void _retry() {
    setState(() => _future = MobilePosSessionService().load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ThqMobileLoadingPage(label: 'Preparing the POS…');
        }
        if (snapshot.hasError) {
          return ThqMobileFailurePage(
            title: 'Could not open Mobile POS',
            message: snapshot.error.toString(),
            onRetry: _retry,
            secondaryAction: TextButton(
              onPressed: () async {
                await MobilePosAuthService().signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MobilePosEntryScreen(),
                    ),
                    (_) => false,
                  );
                }
              },
              child: const Text('Sign out'),
            ),
          );
        }

        final session = snapshot.data!;
        if (session.release.updateRequired) {
          return _MandatoryUpdateView(
            latestVersion: session.release.latestVersion,
            notes: session.release.releaseNotes,
          );
        }
        return MobilePosHomeScreen(session: session);
      },
    );
  }
}

class _MandatoryUpdateView extends StatelessWidget {
  final String latestVersion;
  final String notes;

  const _MandatoryUpdateView({
    required this.latestVersion,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return ThqMobileFailurePage(
      title: 'THQ update required',
      message:
          'This terminal is running ${ThqMobileReleaseContract.versionLabel}. Required version: ${latestVersion.isEmpty ? 'latest release' : latestVersion}.${notes.isEmpty ? '' : '\n\n$notes'}',
      secondaryAction: TextButton(
        onPressed: () async {
          await MobilePosAuthService().signOut();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MobilePosEntryScreen()),
              (_) => false,
            );
          }
        },
        child: const Text('Sign out'),
      ),
    );
  }
}
