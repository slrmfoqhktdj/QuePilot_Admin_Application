import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();

  factory PermissionService() {
    return _instance;
  }

  PermissionService._internal();

  // 모든 필수 권한 요청
  Future<bool> requestAllPermissions() async {
    final permissions = <Permission>[
      Permission.microphone,      // 음성 통화
      // Permission.camera,          // 비디오 (향후)
      Permission.storage,         // 파일 저장
      Permission.notification,    // 알림
    ];

    if (defaultTargetPlatform == TargetPlatform.android) {
      permissions.add(Permission.bluetoothConnect);  // 블루투스
    }

    final statuses = await permissions.request();

    // 권한 요청 결과 확인
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (kDebugMode) {
        print('$permission: $status');
      }
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    return allGranted;
  }

  // 마이크 권한만 요청
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // 카메라 권한만 요청
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  // 저장소 권한만 요청
  Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  // 알림 권한만 요청
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  // 위치 권한만 요청
  Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  // 블루투스 권한 (Android 12+)
  Future<bool> requestBluetoothPermission() async {
    final status = await Permission.bluetoothConnect.request();
    return status.isGranted;
  }

  // 권한 상태 확인
  Future<bool> isMicrophonePermissionGranted() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> isStoragePermissionGranted() async {
    final status = await Permission.storage.status;
    return status.isGranted;
  }

  // 권한 거부 시 설정 화면으로 이동
  Future<void> openAppSettings() async {
    openAppSettings();
  }

  // 상세 권한 상태 확인 및 안내
  Future<PermissionStatus> checkAndRequestMicrophoneWithDialog(
      BuildContext context) async {
    final status = await Permission.microphone.status;

    if (status.isDenied) {
      // 처음 요청
      return await Permission.microphone.request();
    } else if (status.isPermanentlyDenied) {
      // 영구 거부됨 - 설정 화면으로 안내
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('마이크 권한 필요'),
            content: const Text(
              '음성 통화를 사용하려면 마이크 권한이 필요합니다. '
                  '앱 설정에서 권한을 허용해주세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
                child: const Text('설정으로 이동'),
              ),
            ],
          ),
        );
      }
      return status;
    }

    return status;
  }
}