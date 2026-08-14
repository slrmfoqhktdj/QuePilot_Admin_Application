import 'package:flutter/material.dart';
import 'package:que_pilot_admin_01/screens/setting_screen.dart';
import 'package:window_manager/window_manager.dart';
import '../db/model/hive_key_model.dart';
import '../utils/navigation.dart';
import 'login_screen.dart';
import 'timeline_list_screen.dart';
import 'user_list_screen.dart';
import '../services/socket_service.dart';

class CentralControlScreen extends StatefulWidget {
  const CentralControlScreen({Key? key}) : super(key: key);

  @override
  State<CentralControlScreen> createState() => _CentralControlScreenState();
}

class _CentralControlScreenState extends State<CentralControlScreen> {
  final socketService = SocketService();

  // ★ 서버 연결 상태
  bool _isSearching = true;
  bool _isConnected = false;
  String _statusMessage = '서버 탐색 중...';

  int _selectedMenuIndex = 0;
  int? _hoveredMenuIndex;

  // ★ 일반 사용자는 '사용자 관리' 메뉴 숨김
  List<MenuItem> get _menuItems => [
    MenuItem(icon: Icons.folder, title: '프로젝트', route: 'projects'),
    if (socketService.isAdminUser)
      MenuItem(icon: Icons.people, title: '사용자 관리', route: 'users'),
    MenuItem(icon: Icons.settings, title: '설정', route: 'settings'),
  ];

  List<Widget> get _screens => [
    const TimelineListScreen(),
    if (socketService.isAdminUser) const UserListScreen(),
    const SettingScreen(),
  ];

  @override
  void initState() {
    super.initState();
    socketService.onSessionExpired = _onSessionExpired;
    _connectToServer();
  }

  // ★ 인증 만료 시 로그인 화면 복귀
  void _onSessionExpired() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginScreen()),
      (route) => false,
    );
  }

  // ═══════════════════════════════════════════
  // 서버 자동 탐색 및 연결
  // ═══════════════════════════════════════════

  void _connectToServer() async {
    setState(() {
      _isSearching = true;
      _isConnected = false;
      _statusMessage = '서버 탐색 중...';
    });

    // 1차: 마지막 접속했던 서버로 빠른 연결 시도
    final lastUrl = socketService.hiveService.sessionRead(HiveKeyModel().lastURL, null);
    if (lastUrl != null) {
      setState(() { _statusMessage = '이전 서버에 연결 시도 중...'; });
      socketService.serverUrl = lastUrl;
      socketService.connectToMainServer();

      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        if (socketService.isMainConnected) {
          _onConnected('연결됨: $lastUrl');
          return;
        }
      }

      // 실패 시 기존 소켓 정리 (새 연결 루프를 위해)
      socketService.disconnect();
    }

    // 2차: 브로드캐스트 자동 탐색
    // 서버 부팅 중이면 재탐색, 라이선스 인증 전이면 연결 대기까지 자동 처리
    int discoveryRetries = 0;
    while (mounted) {
      setState(() { _statusMessage = '내부망에서 서버 탐색 중...'; });

      final found = await socketService.autoConnect();
      if (!mounted) return;

      if (found) {
        // 서버는 찾았지만 아직 연결 전 → 소켓이 무한 재연결 중이므로 대기
        setState(() {
          _isSearching = true;
          _statusMessage = '서버 연결 대기 중...\n(라이선스 인증이 완료되면 자동 연결됩니다)';
        });

        while (mounted) {
          for (int i = 0; i < 5; i++) {
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            if (socketService.isMainConnected) {
              _onConnected('서버 연결됨: ${socketService.serverUrl}');
              return;
            }
          }
        }
        return;
      }

      discoveryRetries++;
      if (discoveryRetries >= 6) {
        setState(() {
          _isSearching = false;
          _isConnected = false;
          _statusMessage = '서버를 찾지 못했습니다';
        });
        return;
      }

      setState(() { _statusMessage = '서버를 찾지 못했습니다. 재탐색 중... ($discoveryRetries/6)'; });
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  void _onConnected(String message) {
    setState(() {
      _isSearching = false;
      _isConnected = true;
      _statusMessage = message;
    });
  }

  // ═══════════════════════════════════════════
  // 메뉴
  // ═══════════════════════════════════════════

  void _onMenuSelected(int index) {
    setState(() {
      _selectedMenuIndex = index;
    });
  }

  // ═══════════════════════════════════════════
  // 서버 탐색 화면 (연결 전)
  // ═══════════════════════════════════════════

  Widget _buildDiscoveryScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Column(
        children: [
          // 커스텀 타이틀바 (연결 전)
          _buildTitleBar(),
          Container(height: 1, color: Colors.grey[800]),
          // 탐색 콘텐츠
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.control_camera, size: 80, color: Colors.blue[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'QuePilot',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 48),
                  if (_isSearching) ...[
                    const SizedBox(
                      width: 48, height: 48,
                      child: CircularProgressIndicator(color: Colors.blue),
                    ),
                  ] else ...[
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.error_outline,
                      size: 48,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.grey[300], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (!_isSearching && !_isConnected) ...[
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _connectToServer,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 탐색'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 수동 서버 주소 입력 다이얼로그
  // ═══════════════════════════════════════════

  // void _showManualInputDialog() {
  //   final controller = TextEditingController();
  //
  //   showDialog(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       backgroundColor: Colors.grey[850],
  //       title: const Text('서버 주소 입력', style: TextStyle(color: Colors.white)),
  //       content: TextField(
  //         controller: controller,
  //         style: const TextStyle(color: Colors.white),
  //         decoration: InputDecoration(
  //           hintText: 'http://192.168.0.7:8888',
  //           hintStyle: TextStyle(color: Colors.grey[600]),
  //           filled: true,
  //           fillColor: Colors.grey[800],
  //           border: OutlineInputBorder(
  //             borderRadius: BorderRadius.circular(8),
  //             borderSide: BorderSide.none,
  //           ),
  //         ),
  //         onSubmitted: (_) => _manualConnect(controller.text, context),
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('취소', style: TextStyle(color: Colors.grey)),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => _manualConnect(controller.text, context),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.blue.shade700,
  //           ),
  //           child: const Text('연결', style: TextStyle(color: Colors.white)),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // void _manualConnect(String url, BuildContext dialogContext) async {
  //   final trimmed = url.trim();
  //   if (trimmed.isEmpty) return;
  //
  //   Navigator.pop(dialogContext);
  //
  //   setState(() {
  //     _isSearching = true;
  //     _statusMessage = '연결 시도 중: $trimmed';
  //   });
  //
  //   socketService.serverUrl = trimmed;
  //   socketService.connectToMainServer();
  //
  //   // 연결 대기 (최대 5초)
  //   bool connected = false;
  //   for (int i = 0; i < 10; i++) {
  //     await Future.delayed(const Duration(milliseconds: 500));
  //     if (socketService.isMainConnected) {
  //       connected = true;
  //       break;
  //     }
  //   }
  //
  //   if (!mounted) return;
  //
  //   if (connected) {
  //     socketService.hiveService.sessionSave('lastServerUrl', trimmed);
  //   }
  //
  //   setState(() {
  //     _isSearching = false;
  //     _isConnected = connected;
  //     _statusMessage = connected
  //         ? '서버 연결됨: $trimmed'
  //         : '연결 실패: $trimmed';
  //   });
  // }

  // ═══════════════════════════════════════════
  // 메인 빌드
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // ★ 연결 전이면 탐색 화면 표시
    if (!_isConnected) {
      return _buildDiscoveryScreen();
    }

    // ★ 연결 후 메인 화면 (커스텀 타이틀바 + 콘텐츠)
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Column(
        children: [
          // 커스텀 타이틀바
          _buildTitleBar(),
          // 구분선
          Container(height: 1, color: Colors.grey[800]),
          // 콘텐츠
          Expanded(
            child: IndexedStack(
              index: _selectedMenuIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 커스텀 타이틀바
  // ═══════════════════════════════════════════

  Widget _buildTitleBar() {
    return Container(
      height: 40,
      color: Colors.grey[900],
      child: Row(
        children: [
          // 드래그 가능 영역
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  // 메뉴 탭
                  ...List.generate(_menuItems.length, (index) {
                    final item = _menuItems[index];
                    final isSelected = _selectedMenuIndex == index;
                    final isHovered = _hoveredMenuIndex == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hoveredMenuIndex = index),
                        onExit: (_) => setState(() => _hoveredMenuIndex = null),
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _onMenuSelected(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.3)
                                  : isHovered
                                      ? Colors.blue.withValues(alpha: 0.15)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.icon, size: 14, color: isSelected ? Colors.white : Colors.grey[400]),
                                const SizedBox(width: 4),
                                Text(item.title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey[400], fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  // 연결 상태
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: socketService.isMainConnected ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    socketService.isMainConnected ? '연결됨' : '연결 끊김',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  Text('v1.0.0', style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          // 창 컨트롤 버튼 (DragToMoveArea 바깥)
          _buildWindowButton(Icons.minimize, () => windowManager.minimize(), tooltip: '최소화'),
          _buildWindowButton(Icons.crop_square, () async {
            final isMaximized = await windowManager.isMaximized();
            if (isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          }, tooltip: '최대화'),
          _buildWindowButton(Icons.close, () => windowManager.close(), tooltip: '닫기', isClose: true),
        ],
      ),
    );
  }

  Widget _buildWindowButton(IconData icon, VoidCallback onTap, {String? tooltip, bool isClose = false}) {
    return StatefulBuilder(
      builder: (context, setHoverState) {
        bool isHovered = false;
        return Tooltip(
          message: tooltip ?? '',
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            onEnter: (_) => setHoverState(() => isHovered = true),
            onExit: (_) => setHoverState(() => isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 46,
                height: 40,
                alignment: Alignment.center,
                color: isHovered
                    ? (isClose ? Colors.red.withValues(alpha: 0.3) : Colors.grey[700]!.withValues(alpha: 0.5))
                    : Colors.transparent,
                child: Icon(icon, size: 16, color: Colors.grey[400]),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    socketService.onSessionExpired = null;
    socketService.disposeAll();
    super.dispose();
  }
}

class MenuItem {
  final IconData icon;
  final String title;
  final String route;

  MenuItem({required this.icon, required this.title, required this.route});
}

