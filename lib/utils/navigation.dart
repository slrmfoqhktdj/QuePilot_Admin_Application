import 'package:flutter/material.dart';

/// 로그인/로그아웃 등 전체 화면 전환용 페이드 라우트.
/// Windows 데스크톱 기본 줌+페이드 전환 대신 부드러운 페이드 사용.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
