import 'package:flutter/material.dart';

class DemoUnavailableCard extends StatelessWidget {
  const DemoUnavailableCard({
    required this.title,
    required this.message,
    this.icon = Icons.lock_outline,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(message),
    ),
  );
}
