import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../services/device_installation_service.dart';

class DeviceActivationScreen extends StatefulWidget {
  final String appKey;
  final Widget Function() nextScreen;

  const DeviceActivationScreen({
    super.key,
    required this.appKey,
    required this.nextScreen,
  });

  @override
  State<DeviceActivationScreen> createState() => _DeviceActivationScreenState();
}

class _DeviceActivationScreenState extends State<DeviceActivationScreen> {
  final _business = TextEditingController();
  final _code = TextEditingController();
  final _service = DeviceInstallationService();
  bool _loading = false;
  String? _error;

  Future<void> _activate() async {
    if (_business.text.trim().isEmpty || _code.text.trim().isEmpty) {
      setState(
        () => _error = 'Enter the business code and one-time activation code.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activation = await _service.activate(
        businessCode: _business.text,
        activationCode: _code.text,
        appKey: widget.appKey,
      );
      if (!mounted) return;
      ThqNotify.success(
        context,
        '${activation.deviceCode} activated for ${activation.locationName}.',
      );
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.nextScreen()));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _business.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(34),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  widget.appKey == 'pos' ? Icons.point_of_sale : Icons.computer,
                  size: 62,
                ),
                const SizedBox(height: 14),
                Text(
                  'Activate ${widget.appKey == 'pos' ? 'THQ POS' : 'THQ Business'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This is required only once for this installed system. Get the activation code from THQ Admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _business,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Business code',
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _activate(),
                  decoration: const InputDecoration(
                    labelText: 'One-time activation code',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _activate,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(_loading ? 'Activating...' : 'Activate System'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
