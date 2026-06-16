// setting_screen.dart

import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({Key? key}) : super(key: key);

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final socketService = SocketService();
  final _urlController = TextEditingController();
  bool _isConnecting = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = socketService.serverUrl;
  }

  void _saveAndReconnect() async {
    final newUrl = _urlController.text.trim();

    if (newUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서버 URL을 입력하세요')),
      );
      return;
    }

    // 간단한 URL 형식 검증
    if (!newUrl.startsWith('http://') && !newUrl.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL은 http:// 또는 https://로 시작해야 합니다')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _isEditing = false;
    });

    try {
      socketService.serverUrl = newUrl;
      socketService.disconnect();

      // 소켓 정리 대기
      await Future.delayed(const Duration(milliseconds: 500));

      socketService.connectToMainServer();

      // 연결 결과 확인 (최대 5초 대기)
      bool connected = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (socketService.isMainConnected) {
          connected = true;
          break;
        }
      }

      if (!mounted) return;

      if (connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('서버에 연결되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('서버 연결에 실패했습니다. URL을 확인하세요.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('연결 오류: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _reconnect() async {
    setState(() { _isConnecting = true; });

    try {
      socketService.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      socketService.connectToMainServer();

      bool connected = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (socketService.isMainConnected) {
          connected = true;
          break;
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(connected ? '서버에 재연결되었습니다' : '재연결에 실패했습니다'),
          backgroundColor: connected ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('재연결 오류: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() { _isConnecting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = socketService.isMainConnected;

    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: const Row(
            children: [
              Icon(Icons.settings, color: Colors.white),
              SizedBox(width: 12),
              Text(
                '설정',
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
        color: Colors.grey[900],
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── 연결 상태 표시 ──
            Card(
              color: Colors.grey[850],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnecting
                            ? Colors.orange
                            : isConnected
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isConnecting
                          ? '연결 중...'
                          : isConnected
                          ? '서버 연결됨'
                          : '서버 연결 안됨',
                      style: TextStyle(
                        color: _isConnecting
                            ? Colors.orange
                            : isConnected
                            ? Colors.green
                            : Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_isConnecting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 서버 URL ──
            Card(
              color: Colors.grey[850],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns, color: Colors.white),
                        const SizedBox(width: 12),
                        const Text(
                          '서버 URL',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),

                        // ★ 재연결 버튼
                        IconButton(
                          onPressed: _isConnecting ? null : _reconnect,
                          icon: _isConnecting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange,
                            ),
                          )
                              : Icon(
                            Icons.refresh,
                            color: isConnected ? Colors.green : Colors.orange,
                          ),
                          tooltip: '서버 재연결',
                        ),

                        // URL 편집 버튼
                        // if (!_isEditing)
                        //   IconButton(
                        //     icon: const Icon(Icons.edit, color: Colors.blue),
                        //     onPressed: () {
                        //       setState(() {
                        //         _isEditing = true;
                        //         _urlController.text = socketService.serverUrl;
                        //       });
                        //     },
                        //     tooltip: 'URL 변경',
                        //   ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // if (_isEditing) ...[
                    //   TextField(
                    //     controller: _urlController,
                    //     style: const TextStyle(color: Colors.white),
                    //     decoration: InputDecoration(
                    //       hintText: 'http://192.168.0.7:8888',
                    //       hintStyle: TextStyle(color: Colors.grey[600]),
                    //       filled: true,
                    //       fillColor: Colors.grey[800],
                    //       border: OutlineInputBorder(
                    //         borderRadius: BorderRadius.circular(8),
                    //         borderSide: BorderSide.none,
                    //       ),
                    //       prefixIcon: const Icon(Icons.link, color: Colors.grey),
                    //     ),
                    //     onSubmitted: (_) => _saveAndReconnect(),
                    //   ),
                    //   const SizedBox(height: 12),
                    //   Row(
                    //     mainAxisAlignment: MainAxisAlignment.end,
                    //     children: [
                    //       TextButton(
                    //         onPressed: () {
                    //           setState(() {
                    //             _isEditing = false;
                    //             _urlController.text = socketService.serverUrl;
                    //           });
                    //         },
                    //         child: const Text('취소', style: TextStyle(color: Colors.grey)),
                    //       ),
                    //       const SizedBox(width: 8),
                    //       ElevatedButton.icon(
                    //         onPressed: _isConnecting ? null : _saveAndReconnect,
                    //         icon: const Icon(Icons.save),
                    //         label: const Text('저장 및 연결'),
                    //         style: ElevatedButton.styleFrom(
                    //           backgroundColor: Colors.blue.shade700,
                    //           foregroundColor: Colors.white,
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // ] else ...[
                    //   Container(
                    //     width: double.infinity,
                    //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    //     decoration: BoxDecoration(
                    //       color: Colors.grey[800],
                    //       borderRadius: BorderRadius.circular(8),
                    //     ),
                    //     child: Text(
                    //       socketService.serverUrl,
                    //       style: TextStyle(
                    //         color: Colors.grey[300],
                    //         fontSize: 14,
                    //       ),
                    //     ),
                    //   ),
                    // ],

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        socketService.serverUrl,
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),


            const SizedBox(height: 16),

            // // ── 재연결 버튼 ──
            // SizedBox(
            //   width: double.infinity,
            //   child: ElevatedButton.icon(
            //     onPressed: _isConnecting ? null : _reconnect,
            //     icon: _isConnecting
            //         ? const SizedBox(
            //       width: 18,
            //       height: 18,
            //       child: CircularProgressIndicator(
            //         strokeWidth: 2,
            //         color: Colors.white,
            //       ),
            //     )
            //         : const Icon(Icons.refresh),
            //     label: Text(_isConnecting ? '연결 중...' : '서버 재연결'),
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: Colors.orange.shade700,
            //       foregroundColor: Colors.white,
            //       padding: const EdgeInsets.symmetric(vertical: 14),
            //       shape: RoundedRectangleBorder(
            //         borderRadius: BorderRadius.circular(8),
            //       ),
            //     ),
            //   ),
            // ),
            //
            // const SizedBox(height: 16),

            // ── 다크 모드 ──
            // Card(
            //   color: Colors.grey[850],
            //   child: SwitchListTile(
            //     secondary: const Icon(Icons.dark_mode, color: Colors.white),
            //     title: const Text(
            //       '다크 모드',
            //       style: TextStyle(color: Colors.white),
            //     ),
            //     value: true,
            //     onChanged: (value) {},
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}



// import 'package:flutter/material.dart';
// import '../services/socket_service.dart';
//
// class SettingScreen extends StatefulWidget {
//   const SettingScreen({Key? key}) : super(key: key);
//
//   @override
//   State<SettingScreen> createState() => _SettingScreenState();
// }
//
// class _SettingScreenState extends State<SettingScreen> {
//
//   final socketService = SocketService();
//
//   @override
//   void initState() {
//     super.initState();
//
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//         appBar: AppBar(
//           title:  Container(
//             padding: const EdgeInsets.symmetric(vertical: 16),
//             child: const Row(
//               children: [
//                 Icon(Icons.settings, color: Colors.white),
//                 SizedBox(width: 12),
//                 Text(
//                   '설정',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           backgroundColor: Colors.grey[900],
//         ),
//         body:
//         Container(
//           color: Colors.grey[900],
//           child: Column(
//             children: [
//               Card(
//                 color: Colors.grey[850],
//                 child: ListTile(
//                   leading: const Icon(Icons.label_outline, color: Colors.white),
//                   title: const Text(
//                     '서버 URL',
//                     style: TextStyle(color: Colors.white),
//                   ),
//                   subtitle: Text(
//                     socketService.serverUrl,
//                     style: TextStyle(color: Colors.grey[400]),
//                   ),
//                   trailing: IconButton(
//                     icon: const Icon(Icons.edit, color: Colors.blue),
//                     onPressed: () {
//                       // 서버 URL 변경 다이얼로그
//                     },
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 16),
//               Card(
//                 color: Colors.grey[850],
//                 child: SwitchListTile(
//                   secondary: const Icon(Icons.dark_mode, color: Colors.white),
//                   title: const Text(
//                     '다크 모드',
//                     style: TextStyle(color: Colors.white),
//                   ),
//                   value: true,
//                   onChanged: (value) {},
//                 ),
//               ),
//             ],
//           ),
//         )
//
//
//
//     );
//   }
//
//
//
//
//   @override
//   void dispose() {
//     // UserNameController.dispose();
//     super.dispose();
//   }
// }