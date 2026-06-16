import 'package:flutter/material.dart';
import 'package:que_pilot_admin_01/screens/setting_screen.dart';
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

  final double _leftSideBarWidth = 200;

  int _selectedMenuIndex = 0;
  String? _currentProjectId;
  String? _currentRoomId;

  final List<MenuItem> _menuItems = [
    MenuItem(icon: Icons.dashboard, title: '대시보드', route: 'dashboard'),
    MenuItem(icon: Icons.folder, title: '프로젝트', route: 'projects'),
    MenuItem(icon: Icons.people, title: '사용자 관리', route: 'users'),
    MenuItem(icon: Icons.settings, title: '설정', route: 'settings'),
  ];

  @override
  void initState() {
    super.initState();
    _connectToServer();
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
    final lastUrl = socketService.hiveService.sessionRead('lastServerUrl', null);
    if (lastUrl != null) {
      setState(() { _statusMessage = '이전 서버에 연결 시도 중...'; });
      socketService.serverUrl = lastUrl;
      socketService.connectToMainServer();

      await Future.delayed(const Duration(seconds: 3));
      if (socketService.isMainConnected) {
        setState(() {
          _isSearching = false;
          _isConnected = true;
          _statusMessage = '연결됨: $lastUrl';
        });
        return;
      }

      // 실패 시 기존 소켓 정리
      socketService.disconnect();
    }

    // 2차: 브로드캐스트로 서버 자동 탐색
    setState(() { _statusMessage = '내부망에서 서버 탐색 중...'; });

    final found = await socketService.autoConnect();

    if (!mounted) return;

    setState(() {
      _isSearching = false;
      _isConnected = found;
      _statusMessage = found
          ? '서버 연결됨: ${socketService.serverUrl}'
          : '서버를 찾지 못했습니다';
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

  Widget _buildCurrentScreen() {
    switch (_menuItems[_selectedMenuIndex].route) {
      case 'dashboard':
        return _buildDashboard();
      case 'projects':
        return const TimelineListScreen();
      case 'users':
        return const UserListScreen();
      case 'settings':
        return const SettingScreen();
      default:
        return const Center(child: Text('Unknown Screen'));
    }
  }

  // ═══════════════════════════════════════════
  // 서버 탐색 화면 (연결 전)
  // ═══════════════════════════════════════════

  Widget _buildDiscoveryScreen() {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고
            Icon(
              Icons.control_camera,
              size: 80,
              color: Colors.blue[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'QuePilot',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),

            // 상태 표시
            if (_isSearching) ...[
              const SizedBox(
                width: 48,
                height: 48,
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
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),

            // 재시도 버튼 (탐색 실패 시)
            if (!_isSearching && !_isConnected) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _connectToServer,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 탐색'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 수동 입력 버튼
              // TextButton(
              //   onPressed: _showManualInputDialog,
              //   child: Text(
              //     '서버 주소 직접 입력',
              //     style: TextStyle(color: Colors.grey[400]),
              //   ),
              // ),
            ],
          ],
        ),
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
  // 대시보드
  // ═══════════════════════════════════════════

  Widget _buildDashboard() {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: const Row(
            children: [
              Icon(Icons.dashboard, color: Colors.white),
              SizedBox(width: 12),
              Text(
                '중앙 제어 대시보드',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.grey[900],
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildDashboardCard(
                    icon: Icons.folder,
                    title: '프로젝트',
                    subtitle: _currentProjectId ?? '선택 안됨',
                    color: Colors.blue,
                    onTap: () => _onMenuSelected(1),
                  ),
                  _buildDashboardCard(
                    icon: Icons.people,
                    title: '사용자',
                    subtitle: '관리',
                    color: Colors.purple,
                    onTap: () => _onMenuSelected(2),
                  ),
                  _buildDashboardCard(
                    icon: Icons.settings,
                    title: '설정',
                    subtitle: '시스템',
                    color: Colors.grey,
                    onTap: () => _onMenuSelected(3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      backgroundColor: Colors.grey[900],
    );
  }

  Widget _buildDashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.grey[850],
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 메인 빌드
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // ★ 연결 전이면 탐색 화면 표시
    if (!_isConnected) {
      return _buildDiscoveryScreen();
    }

    // ★ 연결 후 메인 화면
    return Scaffold(
      body: Row(
        children: [
          // 왼쪽 사이드바
          Container(
            width: _leftSideBarWidth,
            color: Colors.grey[900],
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(Icons.control_camera, size: 32, color: Colors.blue[400]),
                      const SizedBox(width: 12),
                      const Text(
                        '중앙 제어',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.grey, height: 1),

                Expanded(
                  child: ListView.builder(
                    itemCount: _menuItems.length,
                    itemBuilder: (context, index) {
                      final item = _menuItems[index];
                      final isSelected = _selectedMenuIndex == index;

                      return ListTile(
                        leading: Icon(
                          item.icon,
                          color: isSelected ? Colors.blue[400] : Colors.grey[400],
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[400],
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                        onTap: () => _onMenuSelected(index),
                      );
                    },
                  ),
                ),

                // 하단 서버 연결 상태
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: socketService.isMainConnected
                                  ? Colors.green
                                  : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              socketService.isMainConnected ? '연결됨' : '연결 끊김',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'v1.0.0',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(width: 1, color: Colors.grey[800]),

          Expanded(
            child: Container(
              color: Colors.grey[900],
              child: _buildCurrentScreen(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
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

