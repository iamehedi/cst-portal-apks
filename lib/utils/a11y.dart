import 'package:flutter/widgets.dart';

/// Returns true when the user has enabled "Remove animations" or similar
/// reduced-motion settings at the OS level.
bool reducedMotion(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;
