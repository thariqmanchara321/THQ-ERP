import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/backend_compatibility_service.dart';
import '../services/client_auth_service.dart';
import '../services/client_session_service.dart';
import 'business_selector_screen.dart';
import 'client_home_screen.dart';
import 'client_login_screen.dart';

class ClientBootstrapScreen extends StatefulWidget {
  const ClientBootstrapScreen({super.key});

  @override
  State<ClientBootstrapScreen> createState() => _ClientBootstrapScreenState();
}

class _ClientBootstrapScreenState extends State<ClientBootstrapScreen> {
  final ClientSessionService _sessionService = ClientSessionService();
  final BackendCompatibilityService _backendCompatibility = BackendCompatibilityService();

  final ClientAuthService _authService = ClientAuthService();

  late Future<List<ClientBusiness>> _businessesFuture;

  @override
  void initState() {
    super.initState();

    _businessesFuture = _loadBusinesses();
  }

  Future<List<ClientBusiness>> _loadBusinesses() async {
    await _backendCompatibility.verify();
    return _sessionService.getAvailableBusinesses();
  }

  Future<void> _logout() async {
    await _authService.signOut();

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
      backgroundColor: const Color(0xFFF5F7FA),
      body: FutureBuilder<List<ClientBusiness>>(
        future: _businessesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingView(message: 'Loading your business...');
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onLogout: _logout,
            );
          }

          final businesses = snapshot.data ?? [];

          if (businesses.isEmpty) {
            return _NoBusinessView(onLogout: _logout);
          }

          if (businesses.length == 1) {
            return _SingleBusinessLoader(business: businesses.first);
          }

          return BusinessSelectorScreen(businesses: businesses);
        },
      ),
    );
  }
}

class _SingleBusinessLoader extends StatefulWidget {
  final ClientBusiness business;

  const _SingleBusinessLoader({required this.business});

  @override
  State<_SingleBusinessLoader> createState() => _SingleBusinessLoaderState();
}

class _SingleBusinessLoaderState extends State<_SingleBusinessLoader> {
  final ClientSessionService _sessionService = ClientSessionService();

  late Future<ClientSession> _sessionFuture;

  @override
  void initState() {
    super.initState();

    _sessionFuture = _sessionService.loadSession(business: widget.business);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ClientSession>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingView(message: 'Preparing THQ Business...');
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 54),

                  const SizedBox(height: 16),

                  const Text(
                    'Could not load business',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  Text(snapshot.error.toString(), textAlign: TextAlign.center),
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

class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),

          const SizedBox(height: 20),

          Text(message, style: const TextStyle(fontSize: 16)),
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
              style: TextStyle(color: Colors.grey.shade600),
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
  final Future<void> Function() onLogout;

  const _ErrorView({required this.message, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 60),

            const SizedBox(height: 16),

            const Text(
              'Unable to start THQ Business',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Text(message, textAlign: TextAlign.center),

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
