import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_installation_service.dart';
import '../services/mobile_pos_auth_service.dart';
import '../services/mobile_pos_session_service.dart';
import 'mobile_pos_home_screen.dart';

class MobilePosEntryScreen extends StatefulWidget {
  const MobilePosEntryScreen({super.key});

  @override
  State<MobilePosEntryScreen> createState() => _State();
}

class _State extends State<MobilePosEntryScreen> {
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
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (s.data == null) {
          return _Activation(
            onDone: () => setState(
              () => _activation = DeviceInstallationService().readActivation(),
            ),
          );
        }
        if (Supabase.instance.client.auth.currentSession == null) {
          return _Login(onDone: () => setState(() {}));
        }
        return const _Session();
      },
    );
  }
}

class _Activation extends StatefulWidget {
  final VoidCallback onDone;
  const _Activation({required this.onDone});

  @override
  State<_Activation> createState() => _ActivationState();
}

class _ActivationState extends State<_Activation> {
  final b = TextEditingController();
  final c = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    b.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> go() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await DeviceInstallationService().activate(
        businessCode: b.text,
        activationCode: c.text,
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccessShell(
      icon: Icons.point_of_sale_rounded,
      title: 'THQ Mobile POS',
      subtitle:
          'Activate this phone with a POS terminal code issued from THQ Admin.',
      child: Column(
        children: [
          TextField(
            controller: b,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Business code',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => go(),
            decoration: const InputDecoration(
              labelText: 'Activation code',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          if (error != null) ...[const SizedBox(height: 10), _ErrorBox(error!)],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : go,
              icon: const Icon(Icons.phonelink_lock),
              label: Text(busy ? 'Activating...' : 'Activate Mobile POS'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Login extends StatefulWidget {
  final VoidCallback onDone;
  const _Login({required this.onDone});

  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final u = TextEditingController();
  final p = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    super.dispose();
  }

  Future<void> go() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await MobilePosAuthService().signIn(username: u.text, password: p.text);
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccessShell(
      icon: Icons.badge_outlined,
      title: 'POS sign in',
      subtitle: 'Fast counter access for this activated mobile terminal.',
      child: Column(
        children: [
          TextField(
            controller: u,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: p,
            obscureText: true,
            onSubmitted: (_) => go(),
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (error != null) ...[const SizedBox(height: 10), _ErrorBox(error!)],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : go,
              child: Text(busy ? 'Signing in...' : 'Sign in'),
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

class _Session extends StatelessWidget {
  const _Session();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: MobilePosSessionService().load(),
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (s.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(s.error.toString()),
              ),
            ),
          );
        }
        return MobilePosHomeScreen(session: s.data!);
      },
    );
  }
}
