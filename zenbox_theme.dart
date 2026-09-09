import 'package:flutter/material.dart';
import 'theme.dart';

class ZenboxPalette {
  static const rawWood = Color(0xFF463939);
  static const rawKhaki = Color(0xFF918C69);
  static const rawForest = Color(0xFF42562E);
  static const rawSpruce = Color(0xFF1C321A);
  const ZenboxPalette();
  factory ZenboxPalette.light() => const ZenboxPalette();
  factory ZenboxPalette.dark() => const ZenboxPalette();
  Color get forest => rawForest;
  Color get spruce => rawSpruce;
}

const forest = ZenboxPalette.rawSpruce;
const moss = ZenboxPalette.rawForest;
const olive = ZenboxPalette.rawKhaki;
const bark = ZenboxPalette.rawWood;
const canvas = Color(0xFFF5F5EE);
const surface = Color(0xFFFFFEF8);
const edge = Color(0xFFDDDFD2);
const secondaryInk = Color(0xFF6B705F);

ThemeData buildZenboxTheme() => studioTheme().copyWith(
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: moss,
    primary: moss,
    secondary: olive,
    surface: surface,
    onSurface: forest,
  ),
  cardTheme: CardThemeData(
    color: surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: edge),
    ),
  ),
);

Widget zenPanel(
  Widget child, {
  EdgeInsets padding = const EdgeInsets.all(18),
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: edge),
  ),
  child: child,
);
Widget zenHeading(String title, String subtitle, {Widget? action}) => Padding(
  padding: const EdgeInsets.only(bottom: 22),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 28,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: secondaryInk, height: 1.5),
            ),
          ],
        ),
      ),
      if (action != null) action,
    ],
  ),
);
