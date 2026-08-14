import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'db/hive_service.dart';
import 'screens/login_screen.dart';

import 'permissions/permission_service.dart';

void main() async {
  //FLutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  //Window Manager 초기화
  await windowManager.ensureInitialized();

  // ✅ 창 옵션 설정
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1880, 800),           // 기본 크기 (너비 x 높이)
    minimumSize: Size(800, 600),     // 최소 크기
    center: true,                    // 화면 중앙에 표시
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: '중앙 컨트롤러',      // 창 제목
  );

  // ✅ 창 설정 적용
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  //Hive 초기화
  final hiveService = HiveService();
  await hiveService.initHiveManager();

  //앱 시작시 권한 요청
  final permissionService = PermissionService();

  final microPerminssion = await permissionService.requestMicrophonePermission();

  if(!microPerminssion){
    if (kDebugMode) {
      print('통화권한 거부');
    }
  }


  //마이크 권한 요청
  //await Permission.microphone.request();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuePilot Central Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      // home: const ProjectListScreen(),
      home: const LoginScreen(),
    );
  }
}
