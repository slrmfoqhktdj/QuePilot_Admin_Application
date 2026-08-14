import 'dart:async';

import 'package:flutter/material.dart';
import 'package:que_pilot_admin_01/dialog/question_dialog.dart';
import 'package:que_pilot_admin_01/dialog/user_delete_dialog.dart';
import '../dialog/user_add_dialog.dart';
import '../dialog/user_auth_dialog.dart';
import '../dialog/user_personal_communication_dialog.dart';
import '../dialog/user_update_dialog.dart';
import '../dialog/user_update_password_dialog.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/direct_web_rtc_service.dart';
import '../services/socket_service.dart';


class UserListScreen extends StatefulWidget {
  const UserListScreen({Key? key}) : super(key: key);

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final socketService = SocketService();
  final List<StreamSubscription> _subs = [];
  List<User> users = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  //단일 오버레이 관리
  OverlayEntry? _currentChatOverlay;
  String? _currentChatUserId;


  // ========================================
  // 🔧 개인 통화 상태
  // ========================================
  DirectWebRTCService? _directCallService;
  String? _activeCallId;         // 현재 활성 callId
  String? _activeCallPeerId;     // 통화 상대 userId
  String? _activeCallPeerName;   // 통화 상대 이름
  _DirectCallStatus _callStatus = _DirectCallStatus.idle;
  bool _isCallMuted = false;

  // 통화 UI 오버레이
  OverlayEntry? _callOverlay;


  @override
  void initState() {
    super.initState();
    // socketService.connectToMainServer();
    _loadUsers();
    _setupSocketListeners();
    _setupDirectCallListeners();
  }

  void _setupSocketListeners() {

    _subs.add(socketService.receivePersonalMessage.listen((data) {
      if (_currentChatUserId != data.fromUserId) {
        _showNewMessageSnackBar(data);
      }
    }));

  }

  // ========================================
  // 🔧 개인 통화 리스너
  // ========================================
  void _setupDirectCallListeners() {
    // 상대가 수락
    _subs.add(socketService.directCallAccepted.listen((data) async{
      if (data.callId != _activeCallId) return;

      print('✅ [DirectCall] 수락됨: ${data.receiverName}');
      setState(() {
        _callStatus = _DirectCallStatus.connecting;
        _activeCallPeerName = data.receiverName;
      });
      _updateCallOverlay();

      // WebRTC Offer 전송 시작
      await _directCallService?.startCall(data.callId, data.receiverId);
    }));

    // 상대가 거절
    _subs.add(socketService.directCallRejected.listen((data) {
      if (data.callId != _activeCallId) return;

      print('❌ [DirectCall] 거절됨: ${data.receiverName}');
      _endCallCleanup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${data.receiverName} 님이 통화를 거절했습니다.')),
        );
      }
    }));


    // 상대가 종료 / 연결 해제
    _subs.add(socketService.directCallEnded.listen((data) {
      if (data.callId != _activeCallId) return;

      print('🔴 [DirectCall] 종료됨: by ${data.endedByName} (reason: ${data.reason})');
      _endCallCleanup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data.reason == 'disconnected'
                ? '${data.endedByName} 님의 연결이 끊어졌습니다.'
                : '${data.endedByName} 님이 통화를 종료했습니다.'),
          ),
        );
      }
    }));


    // 타임아웃 (30초 응답 없음)
    _subs.add(socketService.directCallTimeout.listen((data) {
      if (data.callId != _activeCallId) return;

      print('⏰ [DirectCall] 타임아웃');
      _endCallCleanup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('상대방이 응답하지 않습니다.')),
        );
      }
    }));

    // WebRTC Answer 수신 (발신 측)
    _subs.add(socketService.directWebRTCAnswer.listen((data) async{
      if (data.callId != _activeCallId) return;
      await _directCallService?.handleAnswer(data.from, data.payload);
    }));

    // WebRTC ICE Candidate 수신
    _subs.add(socketService.directWebRTCIce.listen((data) async{
      if (data.callId != _activeCallId) return;
      await _directCallService?.handleIceCandidate(data.from, data.payload);
    }));

  }

  // ========================================
  // 통화 걸기
  // ========================================
  void _startDirectCall(User targetUser) async {
    // 이미 통화 중이면 차단
    if (_callStatus != _DirectCallStatus.idle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 통화 중입니다.')),
      );
      return;
    }

    // DirectCallService 생성 및 마이크 초기화
    _directCallService = DirectWebRTCService(socketService);

    _directCallService!.onCallConnected = () {
      if (mounted) {
        setState(() => _callStatus = _DirectCallStatus.connected);
        _updateCallOverlay();
        print('🔗 [DirectCall] WebRTC 연결 완료');
      }
    };

    _directCallService!.onCallDisconnected = () {
      print('🔌 [DirectCall] WebRTC 연결 해제');
      _endCallCleanup();
    };

    final micReady = await _directCallService!.initLocalStream();
    if (!micReady) {
      _directCallService = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 마이크 권한이 필요합니다.')),
        );
      }
      return;
    }

    setState(() {
      _callStatus = _DirectCallStatus.ringing;
      _activeCallPeerId = targetUser.id;
      _activeCallPeerName = targetUser.name;
    });

    // 서버에 통화 요청
    socketService.requestDirectCall(
      targetUser.id,
      socketService.adminName,
          (success, callId, message) {
        if (!mounted) return;

        if (success && callId != null) {
          setState(() {
            _activeCallId = callId;
          });
          _showCallOverlay();
          print('📞 [DirectCall] 요청 성공: callId=$callId');
        } else {
          _directCallService?.dispose();
          _directCallService = null;
          setState(() {
            _callStatus = _DirectCallStatus.idle;
            _activeCallPeerId = null;
            _activeCallPeerName = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('통화 요청 실패: ${message ?? "알 수 없는 오류"}')),
          );
        }
      },
    );
  }

  // ========================================
  // 통화 취소 (벨 울리는 중)
  // ========================================
  void _cancelDirectCall() {
    if (_activeCallId == null) return;

    socketService.cancelDirectCall(_activeCallId!, (success) {
      print('🚫 [DirectCall] 취소 ${success ? "성공" : "실패"}');
    });
    _endCallCleanup();
  }

  // ========================================
  // 통화 종료
  // ========================================
  void _endDirectCall() {
    if (_activeCallId == null) return;

    socketService.endDirectCall(_activeCallId!, (success) {
      print('🔴 [DirectCall] 종료 ${success ? "성공" : "실패"}');
    });
    _endCallCleanup();
  }

  // ========================================
  // 정리
  // ========================================
  void _endCallCleanup() async {
    await _directCallService?.dispose();
    _directCallService = null;

    if (mounted) {
      setState(() {
        _callStatus = _DirectCallStatus.idle;
        _activeCallId = null;
        _activeCallPeerId = null;
        _activeCallPeerName = null;
        _isCallMuted = false;
      });
    }

    _removeCallOverlay();
  }

  // ========================================
  // 음소거 토글
  // ========================================
  void _toggleCallMute() {
    _directCallService?.toggleMute();
    setState(() {
      _isCallMuted = !_isCallMuted;
    });
    _updateCallOverlay();
  }

  // ========================================
  // 통화 오버레이 UI
  // ========================================
  void _showCallOverlay() {
    _removeCallOverlay();

    _callOverlay = OverlayEntry(
      builder: (context) => _buildCallOverlayWidget(),
    );
    Overlay.of(context).insert(_callOverlay!);
  }

  void _updateCallOverlay() {
    _callOverlay?.markNeedsBuild();
  }

  void _removeCallOverlay() {
    _callOverlay?.remove();
    _callOverlay = null;
  }

  Widget _buildCallOverlayWidget() {
    return Positioned(
      top: 80,
      right: 20,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(16),
        color: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _callStatus == _DirectCallStatus.connected
                  ? [Colors.green.shade800, Colors.green.shade900]
                  : _callStatus == _DirectCallStatus.ringing
                  ? [Colors.blue.shade800, Colors.blue.shade900]
                  : [Colors.orange.shade800, Colors.orange.shade900],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      _callStatus == _DirectCallStatus.connected
                          ? Icons.phone_in_talk
                          : Icons.ring_volume,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _callStatus == _DirectCallStatus.connected
                            ? '통화 중'
                            : _callStatus == _DirectCallStatus.ringing
                            ? '전화 거는 중...'
                            : '연결 중...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 상대방 정보
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white24,
                      child: Text(
                        (_activeCallPeerName ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeCallPeerName ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _activeCallPeerId ?? '',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white24, height: 1),

              // 버튼들
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 음소거 (통화 연결 후만)
                    if (_callStatus == _DirectCallStatus.connected)
                      _buildCallActionButton(
                        icon: _isCallMuted ? Icons.mic_off : Icons.mic,
                        label: _isCallMuted ? '음소거 해제' : '음소거',
                        color: _isCallMuted ? Colors.red.shade700 : Colors.white24,
                        onTap: _toggleCallMute,
                      ),

                    // 종료 / 취소
                    _buildCallActionButton(
                      icon: Icons.call_end,
                      label: _callStatus == _DirectCallStatus.ringing ? '취소' : '종료',
                      color: Colors.red.shade700,
                      onTap: () {
                        if (_callStatus == _DirectCallStatus.ringing) {
                          _cancelDirectCall();
                        } else {
                          _endDirectCall();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }


  void _loadUsers() {
    socketService.getUserList((userList) {

      if (mounted) {
        setState(() {
          users = userList.map<User>((userInfo) {
            print(userInfo);
            return User.fromJson(userInfo);
          }).toList();
        });
      }

    });
  }

  Future<void> _roleUser(User user) async {
    showDialog(
      context: context,
      builder: (context) => UserAuthDialog(
        user: user,
        onPermissionUpdated: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('권한이 업데이트되었습니다')),
          );
        },
      ),
    );
  }

  Future<void> _addUser() async {
    showDialog(
      context: context,
      builder: (context) => AddUserDialog(
        onUserAdded: (user) {
          setState(() {
            users.add(user);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User가 추가되었습니다')),
          );
        },
      ),
    );
  }

  Future<void> _updateUser(User updateUser) async {
    showDialog(
      context: context,
      builder: (context) => UpdateUserDialog(
        user: updateUser,
        onUserUpdated: (updatedUser) {
          int index = users.indexWhere((user) => user.id == updatedUser.id);
          setState(() {
            users[index] = updatedUser;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User가 수정되었습니다')),
          );
        },
      ),
    );
  }

  Future<void> _updateUserPassword(User updateUser) async {
    showDialog(
      context: context,
      builder: (context) => UpdateUserPasswordDialog(
        user: updateUser,
      ),
    );
  }

  Future<void> _deleteUser(User deleteUser) async {
    showDialog(
      context: context,
      builder: (context) => DeleteUserDialog(
        user: deleteUser,
        onUserDeleted: () {
          setState(() {
            users.removeWhere((user) => user.id == deleteUser.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User가 삭제되었습니다')),
          );
        },
      ),
    );
  }

  void _openChatDialog(User user) {
    // 이미 같은 유저의 채팅이 열려 있으면 무시
    if (_currentChatUserId == user.id && _currentChatOverlay != null) {
      return;
    }

    // 기존 채팅 닫기
    _closeChatDialog();

    // 새 채팅 열기
    _currentChatUserId = user.id;
    _currentChatOverlay = OverlayEntry(
      builder: (context) => UserPersonalCommunicationDialog(
        targetUser: user,
        onClose: _closeChatDialog,
      ),
    );

    Overlay.of(context).insert(_currentChatOverlay!);
  }

  void _closeChatDialog() {
    _currentChatOverlay?.remove();
    _currentChatOverlay = null;
    _currentChatUserId = null;
  }

  void _showNewMessageSnackBar(MessageData message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${message.fromUsername}: ${message.message}'),
        action: SnackBarAction(
          label: '열기',
          onPressed: () {
            final sender = users.firstWhere(
                  (u) => u.id == message.fromUsername,
            );
            _openChatDialog(sender);
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: const Row(
            children: [
              Icon(Icons.people, color: Colors.white),
              SizedBox(width: 12),
              Text(
                '전체 유저 목록',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        actions: [
          IconButton(
            icon:  const Icon(Icons.add, color: Colors.white),
            onPressed: _addUser,
            tooltip: '사용자 등록',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white,),
            onPressed: () => {
              _loadUsers()
            },
            tooltip: '새로고침',
          ),
        ],

        backgroundColor: Colors.grey[900],
      ),
      body:
      Container(
        color: Colors.grey[900],
        child: Column(
          children: [
            if (users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 280,
                    height: 36,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: "유저 검색",
                        fillColor: Colors.white,
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 1.0,
                          ),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _buildUserList(),
            ),
          ],
        ),
      )



    );
  }


  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  // 유저 아이템 빌더
  Widget _buildUserItem(User user) {
    final isActive = user.isActive == 1;
    // final role = user['role'] ?? 0;
    final isInCall = _activeCallPeerId == user.id && _callStatus != _DirectCallStatus.idle;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        tileColor: Colors.grey[850],
        leading: CircleAvatar(
          backgroundColor: isInCall? Colors.orange :isActive ? Colors.green : Colors.grey,
          child: isInCall
              ? const Icon(Icons.phone_in_talk, color: Colors.white, size: 18)
              : Text(user.name.isNotEmpty ? user.name.substring(user.name.length - 1) : '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),

        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${user.id}',
              style: TextStyle(
                color: Colors.grey[500] ,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text('LoginID: ${user.login_id}',
              style: TextStyle(
                color: Colors.grey[500] ,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text('가입일: ${_formatDate(user.createdAt)}',
              style: TextStyle(
                color: Colors.grey[500] ,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isActive ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: isActive ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  isActive ? '활성' : '비활성',
                  style: TextStyle(
                    color: isActive ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
                // const SizedBox(width: 16),
                // Icon(
                //   role == 1 ? Icons.admin_panel_settings : Icons.person,
                //   size: 16,
                //   color: role == 1 ? Colors.orange : Colors.blue,
                // ),
                const SizedBox(width: 4),
                // Text(
                //   role == 1 ? '관리자' : '일반',
                //   style: TextStyle(
                //     color: role == 1 ? Colors.orange : Colors.blue,
                //     fontSize: 12,
                //   ),
                // ),

                if (isInCall) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.phone_in_talk, size: 14, color: Colors.orange.shade300),
                  const SizedBox(width: 4),
                  Text(
                    '통화 중',
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
                  ),
                ],

                const SizedBox(width: 16),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                tooltip: isInCall ? '통화 중...' : '전화 걸기',
                onPressed: isInCall
                    ? null
                    :(){
                  showDialog(
                      context: context,
                      builder: (dialogContext) => QuestionAlertDialog(
                          question: '${user.name}에게 전화를 거시겠습니까?',
                          confirmedText: '확인',
                          onConfirmed: () async {
                            Navigator.pop(context);
                            _startDirectCall(user);
                          }
                      ),
                  );
                },
                icon: Icon(Icons.call, color: isInCall ? Colors.orange : Colors.white,)
            ),
            IconButton(
                tooltip: '개인 메시지 보내기',
                onPressed: (){
                  _openChatDialog(user);
                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   const SnackBar(content: Text('개발중입니다.')),
                  // );
                },
                icon: Icon(Icons.messenger,color: Colors.white,)
            ),
            PopupMenuButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                color: Colors.grey[800],
                tooltip: '유저 설정',
                itemBuilder: (context) => <PopupMenuEntry> [
                  PopupMenuItem(
                    onTap: () => _updateUser(user),
                    child: const ListTile(
                      leading: const Icon(Icons.mode, color: Colors.white),
                      title: Text('사용자 정보 수정',style: TextStyle(color: Colors.white),),
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () => _roleUser(user),
                    child: const ListTile(
                      leading:const Icon(Icons.person, color: Colors.white),
                      title: Text('사용자 권한 변경',style: TextStyle(color: Colors.white),),
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () => _updateUserPassword(user),
                    child: const ListTile(
                      leading:const Icon(Icons.password, color: Colors.white),
                      title: Text('사용자 비밀번호 재발급',style: TextStyle(color: Colors.white),),
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () => _deleteUser(user),
                    child: const ListTile(
                      leading:const Icon(Icons.remove, color: Colors.white),
                      title: Text('사용자 삭제',style: TextStyle(color: Colors.white),),
                    ),
                  ),
                ]
            ),
          ],
        ),
      ),
    );
  }




  List<User> get _filteredUsers {
    if (_searchQuery.isEmpty) return users;
    final query = _searchQuery.toLowerCase();
    return users.where((user) =>
      user.name.toLowerCase().contains(query) ||
      user.id.toLowerCase().contains(query)
    ).toList();
  }

  Widget _buildUserList() {
    final filtered = _filteredUsers;
    if (users.isEmpty) {
      return const Center(
        child: Text(
          '유저가 없습니다.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
    if (filtered.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '검색 결과가 없습니다',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildUserItem(filtered[index]),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();

    for(final sub in _subs){
      sub.cancel();
    }

    _closeChatDialog();
    _removeCallOverlay();

    if (_activeCallId != null) {
      socketService.endDirectCall(_activeCallId!, null);
    }
    _directCallService?.dispose();


    super.dispose();
  }
}

// ========================================
// 통화 상태 enum
// ========================================
enum _DirectCallStatus {
  idle,        // 통화 없음
  ringing,     // 벨 울리는 중 (요청 전송됨, 응답 대기)
  connecting,  // 수락됨, WebRTC 연결 중
  connected,   // 통화 중
}