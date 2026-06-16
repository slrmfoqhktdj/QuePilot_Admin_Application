import 'package:flutter/material.dart';

class ColorUtils {
  /// Hex 문자열을 Color로 변환
  static Color parseColor(String hexColor, {Color defaultColor = Colors.blue}) {
    try {
      String hex = hexColor.replaceFirst('#', '');

      // 3자리 hex (#RGB) → 6자리로 확장
      if (hex.length == 3) {
        hex = hex.split('').map((c) => c + c).join();
      }

      // 6자리인 경우 FF(불투명) 추가
      if (hex.length == 6) {
        hex = 'FF$hex';
      }

      // 8자리가 아니면 기본값 반환
      if (hex.length != 8) {
        print('⚠ 잘못된 색상 형식: $hexColor');
        return defaultColor;
      }

      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      print('❌ 색상 파싱 실패: $hexColor, 에러: $e');
      return defaultColor;
    }
  }

  /// Color를 Hex 문자열로 변환
  static String parseHex(Color color, {bool includeAlpha = false}) {
    if (includeAlpha) {
      return '#${color.value.toRadixString(16).padLeft(8, '0')}';
    } else {
      return '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
    }
  }

  /// 밝기 확인 (텍스트 색상 결정용)
  static bool isColorDark(Color color) {
    final luminance = color.computeLuminance();
    return luminance < 0.5;
  }

  /// 대비되는 텍스트 색상 반환
  static Color getContrastTextColor(Color backgroundColor) {
    return isColorDark(backgroundColor) ? Colors.white : Colors.black;
  }
}