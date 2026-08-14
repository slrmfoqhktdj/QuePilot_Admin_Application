import 'package:flutter/services.dart';

/// 앞/뒤 공백(스페이스) 입력을 자동 제거하는 입력 포맷터.
/// 내부 공백(단어 구분)은 유지된다.
final List<TextInputFormatter> noOuterWhitespace = [
  FilteringTextInputFormatter.deny(RegExp(r'^\s+|\s+$')),
];
