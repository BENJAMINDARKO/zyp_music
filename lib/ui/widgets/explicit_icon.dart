import 'package:flutter/material.dart';

class ExplicitIcon extends StatelessWidget {
  const ExplicitIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'E',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
      ),
    );
  }
}
