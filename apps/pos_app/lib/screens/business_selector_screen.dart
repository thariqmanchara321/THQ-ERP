import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/client_session_service.dart';
import 'client_home_screen.dart';

class BusinessSelectorScreen extends StatefulWidget {
  final List<ClientBusiness> businesses;

  const BusinessSelectorScreen({super.key, required this.businesses});

  @override
  State<BusinessSelectorScreen> createState() => _BusinessSelectorScreenState();
}

class _BusinessSelectorScreenState extends State<BusinessSelectorScreen> {
  final ClientSessionService _sessionService = ClientSessionService();

  String? _loadingBusinessId;
  String? _error;

  Future<void> _openBusiness(ClientBusiness business) async {
    setState(() {
      _loadingBusinessId = business.id;
      _error = null;
    });

    try {
      final session = await _sessionService.loadSession(business: business);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ClientHomeScreen(session: session)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingBusinessId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Choose Business')),
      body: Center(
        child: Container(
          width: 700,
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a Business',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                'Your account has access to multiple businesses.',
                style: TextStyle(color: Colors.grey.shade600),
              ),

              if (_error != null) ...[
                const SizedBox(height: 18),

                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 24),

              Expanded(
                child: ListView.separated(
                  itemCount: widget.businesses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final business = widget.businesses[index];

                    final loading = _loadingBusinessId == business.id;

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: loading ? null : () => _openBusiness(business),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const Icon(Icons.store_outlined, size: 34),

                              const SizedBox(width: 18),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      business.name,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      business.businessType ?? 'Business',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (loading)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
