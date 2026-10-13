import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../services/client_session_service.dart';
import '../services/device_installation_service.dart';
import 'pos_entry_screen.dart';
import 'pos_home_screen.dart';
import 'pos_login_screen.dart';

class PosBootstrapScreen extends StatefulWidget {
  const PosBootstrapScreen({super.key});
  @override
  State<PosBootstrapScreen> createState() => _PosBootstrapScreenState();
}

class _PosBootstrapScreenState extends State<PosBootstrapScreen> {
  final ClientSessionService _service = ClientSessionService();
  late Future<List<ClientBusiness>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PosLoginScreen()),
      );
    }
  }

  Future<List<ClientBusiness>> _load() async {
    final act = await DeviceInstallationService().readAndVerifyActivation();
    if (act == null) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PosEntryScreen()),
        );
      }
      return const [];
    }
    final rows = await _service.getAvailableBusinesses().timeout(const Duration(seconds: 15));
    if (rows.isEmpty) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PosLoginScreen()),
        );
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<ClientBusiness>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _PosLoadingView(
              message: 'Loading POS businesses...',
              onLogout: _logout,
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 54, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to load businesses',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
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
                          onPressed: _logout,
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
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No business access.'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _logout,
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            );
          }
          if (rows.length == 1) {
            return _SinglePosBusinessLoader(
              business: rows.first,
              onLogout: _logout,
            );
          }
          return Center(
            child: SizedBox(
              width: 650,
              child: ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  const Text(
                    'Choose POS Business',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ...rows.map(
                    (b) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.storefront),
                        title: Text(b.name),
                        subtitle: Text(b.businessType ?? 'Business'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _SinglePosBusinessLoader(
                                business: b,
                                onLogout: _logout,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SinglePosBusinessLoader extends StatefulWidget {
  final ClientBusiness business;
  final Future<void> Function() onLogout;

  const _SinglePosBusinessLoader({
    required this.business,
    required this.onLogout,
  });

  @override
  State<_SinglePosBusinessLoader> createState() => _SinglePosBusinessLoaderState();
}

class _SinglePosBusinessLoaderState extends State<_SinglePosBusinessLoader> {
  final ClientSessionService _service = ClientSessionService();
  late Future<ClientSession> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = _loadSession();
  }

  Future<ClientSession> _loadSession() {
    return _service
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
    return Scaffold(
      body: FutureBuilder<ClientSession>(
        future: _sessionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _PosLoadingView(
              message: 'Starting POS...',
              onLogout: widget.onLogout,
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 54, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Could not start POS',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.error.toString(),
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

          final session = snapshot.data!;
          if (!session.hasModule('pos')) {
            return Center(
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.block_outlined, size: 54, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'POS Module Disabled',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'POS module is not enabled for this business.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => widget.onLogout(),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              ),
            );
          }

          return PosHomeScreen(session: session);
        },
      ),
    );
  }
}

class _PosLoadingView extends StatefulWidget {
  final String message;
  final Future<void> Function()? onLogout;

  const _PosLoadingView({required this.message, this.onLogout});

  @override
  State<_PosLoadingView> createState() => _PosLoadingViewState();
}

class _PosLoadingViewState extends State<_PosLoadingView> {
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
          const SizedBox(height: 16),
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

