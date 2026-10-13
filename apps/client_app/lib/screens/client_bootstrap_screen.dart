import 'dart:async';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/backend_compatibility_service.dart';
import '../services/client_auth_service.dart';
import '../services/client_session_service.dart';
import '../services/device_installation_service.dart';
import 'business_selector_screen.dart';
import 'client_entry_screen.dart';
import 'client_home_screen.dart';
import 'client_login_screen.dart';

class ClientBootstrapScreen extends StatefulWidget {
  const ClientBootstrapScreen({super.key});

  @override
  State<ClientBootstrapScreen> createState() => _ClientBootstrapScreenState();
}

class _ClientBootstrapScreenState extends State<ClientBootstrapScreen> {
  final ClientSessionService _sessionService = ClientSessionService();
  final BackendCompatibilityService _backendCompatibility =
      BackendCompatibilityService();

  final ClientAuthService _authService = ClientAuthService();

  late Future<List<ClientBusiness>> _businessesFuture;

  @override
  void initState() {
    super.initState();
    _businessesFuture = _loadBusinesses();
  }

  void _retry() {
    setState(() {
      _businessesFuture = _loadBusinesses();
    });
  }

  Future<List<ClientBusiness>> _loadBusinesses() async {
    final act = await DeviceInstallationService().readAndVerifyActivation();
    if (act == null) {
      try {
        await _authService.signOut();
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ClientEntryScreen()),
          (_) => false,
        );
      }
      return const [];
    }

    try {
      await _backendCompatibility.verify().timeout(const Duration(seconds: 12));
    } catch (e) {
      // Re-throw so user gets clear error view with retry button
      throw Exception('Backend compatibility check failed: $e');
    }

    final businesses = await _sessionService
        .getAvailableBusinesses()
        .timeout(const Duration(seconds: 15));

    if (businesses.isEmpty) {
      try {
        await _authService.signOut();
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ClientLoginScreen()),
          (_) => false,
        );
      }
    }
    return businesses;
  }

  Future<void> _logout() async {
    try {
      await _authService.signOut();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder<List<ClientBusiness>>(
        future: _businessesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _LoadingView(
              message: 'Loading your business...',
              onLogout: _logout,
            );
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _retry,
              onLogout: _logout,
            );
          }

          final businesses = snapshot.data ?? [];

          if (businesses.isEmpty) {
            return _NoBusinessView(onLogout: _logout);
          }

          if (businesses.length == 1) {
            return _SingleBusinessLoader(
              business: businesses.first,
              onLogout: _logout,
            );
          }

          return BusinessSelectorScreen(businesses: businesses);
        },
      ),
    );
  }
}

class _SingleBusinessLoader extends StatefulWidget {
  final ClientBusiness business;
  final Future<void> Function() onLogout;

  const _SingleBusinessLoader({
    required this.business,
    required this.onLogout,
  });

  @override
  State<_SingleBusinessLoader> createState() => _SingleBusinessLoaderState();
}

class _SingleBusinessLoaderState extends State<_SingleBusinessLoader> {
  final ClientSessionService _sessionService = ClientSessionService();

  late Future<ClientSession> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<ClientSession> _loadSession() {
    return _sessionService
        .loadSession(business: widget.business)
        .timeout(const Duration(seconds: 20));
  }

  void _retry() {
    setState(() {
      _sessionFuture = _loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ClientSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LoadingView(
            message: 'Preparing THQ Business...',
            onLogout: widget.onLogout,
          );
        }

        if (snapshot.hasError) {
          final err = snapshot.error
              .toString()
              .replaceFirst(RegExp(r'^Exception:\s*'), '');
          return Center(
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 54, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Could not load business',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    err,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => widget.onLogout(),
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return ClientHomeScreen(session: snapshot.data!);
      },
    );
  }
}

class _LoadingView extends StatefulWidget {
  final String message;
  final Future<void> Function()? onLogout;

  const _LoadingView({required this.message, this.onLogout});

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView> {
  bool _showCancel = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showCancel = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(widget.message, style: const TextStyle(fontSize: 16)),
          if (_showCancel && widget.onLogout != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Taking longer than expected?',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onLogout!(),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Back to Login'),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoBusinessView extends StatelessWidget {
  final Future<void> Function() onLogout;

  const _NoBusinessView({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined, size: 64),
            const SizedBox(height: 18),
            const Text(
              'No Business Access',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Your account is not connected to an active THQ Business business.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => onLogout(),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onLogout;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final cleanMessage =
        message.replaceFirst(RegExp(r'^Exception:\s*'), '');
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              'Unable to start THQ Business',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(cleanMessage, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => onLogout(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Sign Out'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
