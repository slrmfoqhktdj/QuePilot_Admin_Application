// setting_screen.dart

import 'package:flutter/material.dart';
import '../db/hive_service.dart';
import '../services/socket_service.dart';
import '../utils/text_formatters.dart';
import '../utils/navigation.dart';
import 'login_screen.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({Key? key}) : super(key: key);

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final socketService = SocketService();
  final _hiveService = HiveService();
  final _urlController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isConnecting = false;
  double _commentOffset = 2.0;

  @override
  void initState() {
    super.initState();
    _urlController.text = socketService.serverUrl;
    _commentOffset = _hiveService.readCommentOffset();
    _displayNameController.text = _hiveService.readDisplayName();
  }

  void _saveDisplayName() {
    final name = _displayNameController.text.trim();
    _hiveService.saveDisplayName(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('표시 이름이 저장되었습니다'),
        backgroundColor: Colors.green,
      ),
    );
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

  // ★ 로그아웃 → 로그인 화면 복귀
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('로그아웃', style: TextStyle(color: Colors.white)),
        content: const Text('로그아웃하시겠습니까?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final success = await socketService.logout();
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 처리 중 오류가 발생했습니다'), backgroundColor: Colors.red),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      fadeRoute(const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = socketService.isMainConnected;

    return Scaffold(
      backgroundColor: Colors.grey[900],
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
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            const Text('연결', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold,),),
            
            const SizedBox(height: 16),

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

            const Text('프로젝트', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold,),),

            const SizedBox(height: 16),

            // ── 코멘트 표시 시점 ──
            Card(
              color: Colors.grey[850],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.white),
                        const SizedBox(width: 12),
                        const Text(
                          '코멘트 표시 시점',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_commentOffset.toStringAsFixed(1)}초',
                          style: TextStyle(
                            color: Colors.blue[300],
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '재생시 큐 시작 전 해당 코멘트를 미리 표시하는 시간',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _commentOffset,
                      min: 0.0,
                      max: 10.0,
                      divisions: 20,
                      activeColor: Colors.blue,
                      inactiveColor: Colors.grey[700],
                      onChanged: (value) {
                        setState(() {
                          _commentOffset = value;
                        });
                        _hiveService.saveCommentOffset(value);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0초', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        Text('5초', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        Text('10초', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Text('계정', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold,),),

            const SizedBox(height: 16),

            // ── 표시 이름 ──
            Card(
              color: Colors.grey[850],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge, color: Colors.white),
                        const SizedBox(width: 12),
                        const Text(
                          '표시 이름',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '방/채팅에서 다른 사용자에게 보여지는 이름 (비우면 "관리자")',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _displayNameController,
                      style: const TextStyle(color: Colors.white),
                      maxLength: 20,
                      inputFormatters: noOuterWhitespace,
                      decoration: InputDecoration(
                        hintText: '관리자',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: Colors.grey[800],
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.person, color: Colors.grey),
                      ),
                      onSubmitted: (_) => _saveDisplayName(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saveDisplayName,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('저장'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 로그아웃 ──
            Card(
              color: Colors.grey[850],
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  '로그아웃',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '로그인 화면으로 돌아갑니다',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _logout,
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
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }
}

