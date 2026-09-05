import 'package:flutter/material.dart';

import '../../models/accessibility_models.dart';

extension AccessibilityFacilityUi on AccessibilityFacility {
  String get label => switch (this) {
    AccessibilityFacility.wheelchairAccess => 'Wheelchair access',
    AccessibilityFacility.stepFreeAccess => 'Step-free access',
    AccessibilityFacility.lift => 'Lift',
    AccessibilityFacility.accessibleToilet => 'Accessible toilet',
  };

  IconData get icon => switch (this) {
    AccessibilityFacility.wheelchairAccess => Icons.accessible,
    AccessibilityFacility.stepFreeAccess => Icons.escalator_warning,
    AccessibilityFacility.lift => Icons.elevator_outlined,
    AccessibilityFacility.accessibleToilet => Icons.wc,
  };
}

extension AccessibilityStatusUi on AccessibilityFacilityStatus {
  String get label => switch (this) {
    AccessibilityFacilityStatus.available => 'Available',
    AccessibilityFacilityStatus.unavailable => 'Unavailable',
    AccessibilityFacilityStatus.unknown => 'Unknown',
  };

  Color get colour => switch (this) {
    AccessibilityFacilityStatus.available => const Color(0xFF2E7D32),
    AccessibilityFacilityStatus.unavailable => const Color(0xFFD32F2F),
    AccessibilityFacilityStatus.unknown => const Color(0xFF757575),
  };

  IconData get icon => switch (this) {
    AccessibilityFacilityStatus.available => Icons.check_circle,
    AccessibilityFacilityStatus.unavailable => Icons.cancel,
    AccessibilityFacilityStatus.unknown => Icons.help_outline,
  };
}

String accessibilityTimeLabel(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes} min ago';
  if (difference.inDays < 1) return '${difference.inHours} hr ago';
  if (difference.inDays < 7) return '${difference.inDays} days ago';
  return '${value.day}/${value.month}/${value.year}';
}
