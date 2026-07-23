// signature_pad.dart - a white box you sign in with your finger, plus a
// "Clear Signature" button. Used on the consent step of sign-up.

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../../../core/theme/app_colors.dart';

// The signing box. The parent owns the drawing (controller) and the clear action.
class SignaturePad extends StatelessWidget {
  final SignatureController controller; // holds the drawn strokes
  final VoidCallback onClear; // wipe the box

  const SignaturePad({super.key, required this.controller, required this.onClear});

  // Draws the bordered signing area with the Clear button underneath.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Signature(
              controller: controller,
              height: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text("Clear Signature", style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: AppColors.placeholder),
        ),
      ],
    );
  }
}
