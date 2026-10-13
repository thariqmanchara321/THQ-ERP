import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_installation_service.dart';
import 'client_bootstrap_screen.dart';
import 'client_login_screen.dart';
import 'device_activation_screen.dart';

class ClientEntryScreen extends StatefulWidget {
  const ClientEntryScreen({super.key});

  @override
  State<ClientEntryScreen> createState() => _ClientEntryScreenState();
}

class _ClientEntryScreenState extends State<ClientEntryScreen> {
  late Future<DeviceActivation?> _activationFuture;

  @override
  void initState() {
    super.initState();
    _loadActivation();
  }

  void _loadActivation() {
    _activationFuture = DeviceInstallationService()
        .readAndVerifyActivation()
        .timeout(const Duration(seconds: 12));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceActivation?>(
      future: _activationFuture,
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
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 16),
                    const Text(
                      'Unable to verify activation',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _loadActivation();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => DeviceActivationScreen(
                                  appKey: 'client',
                                  nextScreen: () => const ClientLoginScreen(),
                                ),
                              ),
                            );
                          },
                          child: const Text('Activate PC'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.data == null) {
          return DeviceActivationScreen(
            appKey: 'client',
            nextScreen: () => const ClientLoginScreen(),
          );
        }

        return Supabase.instance.client.auth.currentSession == null
            ? const ClientLoginScreen()
            : const ClientBootstrapScreen();
      },
    );
  }
}
