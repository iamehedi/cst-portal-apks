import 'package:flutter/material.dart';

class Responsive {
  static bool isSmall(BuildContext context) =>
      MediaQuery.of(context).size.width < 360;

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= 360 && w < 600;
  }

  static bool isLarge(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600;

  static int gridColumns(BuildContext context,
      {int small = 2, int medium = 2, int large = 3}) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 600) return large;
    if (w >= 360) return medium;
    return small;
  }

  static double screenPadding(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 16;
    if (w < 600) return 20;
    return 24;
  }

  static double contentMaxWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 600) return 500;
    return double.infinity;
  }
}
