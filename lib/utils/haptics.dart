import 'package:flutter/services.dart';

void hapticLight() => HapticFeedback.lightImpact();
void hapticMedium() => HapticFeedback.mediumImpact();
void hapticHeavy() => HapticFeedback.heavyImpact();
void hapticSelection() => HapticFeedback.selectionClick();
