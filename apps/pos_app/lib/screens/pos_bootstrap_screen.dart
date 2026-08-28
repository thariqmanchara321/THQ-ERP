import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../services/client_session_service.dart';
import 'pos_home_screen.dart';

class PosBootstrapScreen extends StatefulWidget {
  const PosBootstrapScreen({super.key});
  @override
  State<PosBootstrapScreen> createState() => _PosBootstrapScreenState();
}

class _PosBootstrapScreenState extends State<PosBootstrapScreen> {
  final ClientSessionService _service = ClientSessionService();
  late Future<List<ClientBusiness>> _future;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _future = _service.getAvailableBusinesses();
  }

  Future<void> _open(ClientBusiness business) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final session = await _service.loadSession(business: business);
      if (!mounted) return;
      if (!session.hasModule('pos')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('POS module is not enabled for this business.'),
          ),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PosHomeScreen(session: session)),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<ClientBusiness>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No business access.'));
          }
          if (rows.length == 1) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _open(rows.first),
            );
            return const Center(child: CircularProgressIndicator());
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
                        onTap: _opening ? null : () => _open(b),
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
