import 'package:flutter/material.dart';
import 'supabase_config.dart';

class ThqEnvironmentFrame extends StatelessWidget {
  const ThqEnvironmentFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isTest) return child;
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Material(
            color: const Color(0xFFFFC107),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'THQ ERP TEST • Separate test database • Test transactions only',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
