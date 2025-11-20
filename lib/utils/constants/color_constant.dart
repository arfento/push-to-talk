import 'package:flutter/material.dart';

List<Color> progressStrokeColor = const [
  Color(0xffFF7A01),
  Color(0xffFF0069),
  Color(0xff7639FB),
  Color(0xffFF7A01),
];

List<Color> progressBackgroundColor = [
  const Color(0xffFF7A01).withValues(alpha: 0.6),
  const Color(0xffFF0069).withValues(alpha: 0.6),
  const Color(0xff7639FB).withValues(alpha: 0.6),
  const Color(0xffFF7A01).withValues(alpha: 0.6),
];

abstract class AppColors {
  //Grey theme
  // static final mainColor = Colors.grey[900]!;
  // static final highlightColor = Colors.grey[850]!;
  // static final shadowColor = Colors.black45;
  // static final accentColor = Colors.grey[700]!;

  //Blue theme
  // static final mainColor = Color(0xff1A1A2E);
  // static final highlightColor = Colors.white10;
  // static final shadowColor = Colors.black45;
  // static final accentColor = Colors.grey;

  //Red theme
  static final mainColor = Color(0xffFD5D5D);
  static final highlightColor = Color(0xffFF8080);
  static final shadowColor = Colors.black45;
  static final accentColor = Colors.white;
}
