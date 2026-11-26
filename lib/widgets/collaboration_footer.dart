// Hug - footer shown on the bottom of the screens

import 'package:flutter/material.dart';
import '../constants/colors.dart';

class CollaborationFooter extends StatelessWidget {
  const CollaborationFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PUP Logo
        Image.asset(
          'assets/images/pup_logo.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
        ),

        const SizedBox(width: 6),

        const Text(
          'Collaboration with the OCPS of\nPolytechnic University of the Philippines',
          style: TextStyle(
            fontSize: 9,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}