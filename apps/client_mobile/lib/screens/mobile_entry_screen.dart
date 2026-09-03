import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_installation_service.dart';
import '../services/mobile_auth_service.dart';
import '../services/mobile_session_service.dart';
import 'mobile_home_screen.dart';

class MobileEntryScreen extends StatefulWidget {
  const MobileEntryScreen({super.key});

  @override
  State<MobileEntryScreen> createState() => _MobileEntryScreenState();
}

class _MobileEntryScreenState extends State<MobileEntryScreen> {
  late Future<DeviceActivation?> _activation;

  @override
  void initState() {
    super.initState();
    _activation = DeviceInstallationService().readActivation();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceActivation?>(
      future: _activation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return _ActivationView(
            onDone: () {
              setState(() {
                _activation = DeviceInstallationService().readActivation();
              });
            },
          );
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
    setState(() => _busy = true);
    try {
      await DeviceInstallationService().activate(
        businessCode: _business.text,
        activationCode: _code.text,
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccessShell(
      icon: Icons.phone_android_rounded,
      title: 'THQ Client Mobile',
      subtitle:
          'Activate this phone with the Client system code issued from THQ Admin.',
      child: Column(
        children: [
          TextField(
            controller: _business,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Business code',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _activate(),
            decoration: const InputDecoration(
              labelText: 'Activation code',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _activate,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(_busy ? 'Activating...' : 'Activate Client Mobile'),
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
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MobileAuthService().signIn(
        username: _username.text,
        password: _password.text,
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccessShell(
      icon: Icons.business_center_outlined,
      title: 'Welcome back',
      subtitle: 'Sign in to your activated THQ Business mobile system.',
      child: Column(
        children: [
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => _login(),
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _ErrorBox(_error!),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? 'Signing in...' : 'Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _AccessShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, size: 30, color: scheme.primary),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 11, color: scheme.onErrorContainer),
      ),
    );
  }
}

class _SessionLoader extends StatelessWidget {
  const _SessionLoader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: MobileSessionService().load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snapshot.error.toString()),
              ),
            ),
          );
        }
        return MobileHomeScreen(session: snapshot.data!);
      },
    );
  }
}
