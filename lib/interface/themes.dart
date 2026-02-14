import 'package:flutter/material.dart';

const _primaryColor = Color.fromRGBO(150, 150, 250, 1);

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _primaryColor),
  useMaterial3: true,
  textTheme: const TextTheme(
    titleSmall: TextStyle(color: Colors.black54),
  ),
);

final darkTheme = ThemeData.dark(
  useMaterial3: true,
).copyWith(
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: _primaryColor,
  ),
  textTheme: TextTheme(
    titleSmall: TextStyle(
      color: Colors.white.withOpacity(0.87),
    ),
  ),
);
