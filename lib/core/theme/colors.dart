import 'package:flutter/material.dart';

class AppColors {
  static const Color bg = Color(0xFF100F1F);
  static const Color surface = Color(0xFF18162B);
  static const Color surface2 = Color(0xFF211E38);
  static const Color surface3 = Color(0xFF2C2848);

  static const Color border = Color(0xFF3B365C);
  static const Color borderBright = Color(0xFF5A5182);

  static const Color indigo = Color(0xFF6C58E8);
  static const Color indigoGlow = Color(0x334930B6);

  static const Color amber = Color(0xFFF5A623);
  static const Color green = Color(0xFF3DD68C);
  static const Color red = Color(0xFFEF4444);

  static const Color text = Color(0xFFE8EAF0);
  static const Color textMuted = Color(0xFF918BAC);
  static const Color textDim = Color(0xFFB8B3D6);

  // Colors for specific subjects matching HTML config
  static const Map<String, Color> subjectColors = {
    'Paediatric': Color(0xFF2563EB),
    'Surgery': Color(0xFF0D9488),
    'Medicine': Color(0xFF6366F1),
    'internal medicine': Color(0xFF6366F1),
    'OBGYN': Color(0xFFEC4899),
    'Obstetric': Color(0xFFEC4899),
    'Gynecology': Color(0xFFDB2777),
    'Anesthesia': Color(0xFF8B5CF6),
    'Radiology': Color(0xFF475569),
    'Psychiatry': Color(0xFFF59E0B),
    'ENT': Color(0xFF10B981),
    'Ophthalmology': Color(0xFFEF4444),
  };

  static const Color defaultSubjectColor = Color(0xFF334155);
}
