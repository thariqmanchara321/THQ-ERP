import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_installation_service.dart';
import 'client_bootstrap_screen.dart';
import 'client_login_screen.dart';
import 'device_activation_screen.dart';

class ClientEntryScreen extends StatelessWidget {
  const ClientEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeviceActivation?>(
      future: DeviceInstallationService().readActivation(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
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
