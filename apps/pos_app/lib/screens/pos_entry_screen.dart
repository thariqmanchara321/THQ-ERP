import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_installation_service.dart';
import 'device_activation_screen.dart';
import 'pos_bootstrap_screen.dart';
import 'pos_login_screen.dart';

class PosEntryScreen extends StatelessWidget {
  const PosEntryScreen({super.key});

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
            appKey: 'pos',
            nextScreen: () => const PosLoginScreen(),
          );
        }
        return Supabase.instance.client.auth.currentSession == null
            ? const PosLoginScreen()
            : const PosBootstrapScreen();
      },
    );
  }
}
