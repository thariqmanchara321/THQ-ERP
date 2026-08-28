import 'package:flutter/material.dart';

class AdminHomeButton extends StatelessWidget {
  const AdminHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Platform Home',
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      icon: const Icon(Icons.home_outlined),
    );
  }
}
