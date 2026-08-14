import 'dart:async';

import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../services/web_rtc_service.dart';

class RoomSlideCallWidget extends StatefulWidget {
  final String roomId;
  final String username;
  final List<Map<String, dynamic>> joinedMembers;

  const RoomSlideCallWidget({
    Key? key,
    required this.roomId,
    required this.username,
    required this.joinedMembers,
  }) : super(key: key);

  @override
  State<RoomSlideCallWidget> createState() => _RoomSlideCallWidgetState();
}

class _RoomSlideCallWidgetState extends State<RoomSlideCallWidget> {
  final socketService = SocketService();
  final List<StreamSubscription> _subs = [];
  late WebRTCService webrtcService;

  bool _isInCall = false;
  bool _isMuted = false;
  List<Map<String, dynamic>> _callParticipants = [];
  int _totalCallParticipants = 0;

  double _speakerVolume = 0.5;
  double _microphoneGain = 1.0;

  // ✅ 팝업용 GlobalKey
  final GlobalKey _audioSettingsKey = GlobalKey();
  final GlobalKey _peerVolumeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    webrtcService = WebRTCService(socketService);
    _setupEventListeners();
    _checkActiveCall();
  }

  void _setupEventListeners() {

    _subs.add(socketService.userJoined.listen((data) {
      if (mounted) {
        setState(() {
          if (!widget.joinedMembers.any((m) => m['userId'] == data.userId)) {
            widget.joinedMembers.add({'userId': data.userId, 'userName': data.userName});
          }
        });
      }
    }));

    _subs.add(socketService.userLeft.listen((data) {
      if (mounted) {
        setState(() {
          widget.joinedMembers.removeWhere((m) => m['userId'] == data.userId);
          _callParticipants.removeWhere((p) => p['userId'] == data.userId);
        });
      }
    }));


    _subs.add(socketService.callParticipantsUpdated.listen((data) {
      if (!mounted) return;
      setState(() {
        _callParticipants = data.participants;
        _totalCallParticipants = data.totalParticipants;
      });
    }));


    _subs.add(socketService.userJoinedCall.listen((data) async {
      if (!mounted) return;
      print('📞 $data.username 통화 참여 (신규 입장자가 Offer 생성)');
    }));


    _subs.add(socketService.userLeftCall.listen((data) {
      if (!mounted) return;
      webrtcService.removePeerConnection(data.userId);
      if (mounted) setState(() {});
    }));


    _subs.add(socketService.peerMuteChanged.listen((data) {
      if (!mounted) return;
      setState(() {});
    }));

  }

  void _checkActiveCall() {
    socketService.getActiveCall(widget.roomId, (success, data) {
      if (success && data != null && data['hasActiveCall'] == true) {
        if (mounted) {
          setState(() {
            _callParticipants = List<Map<String, dynamic>>.from(data['participants'] ?? []);
            _totalCallParticipants = data['totalParticipants'] ?? 0;
          });
        }
      }
    });
  }

  void _toggleCall() {
    _isInCall ? _leaveCall() : _joinCall();
  }

  void _joinCall() async {
    final localStream = await webrtcService.initLocalStream();
    if (localStream == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 마이크 권한이 필요합니다')),
      );
      return;
    }

    socketService.joinRoomCall(widget.roomId, _isMuted, (success, data) async {
      print('🔍 [Admin] joinRoomCall 응답: success=$success');
      print('🔍 [Admin] existingParticipants: ${data['existingParticipants']}');
      if (success) {
        setState(() {
          _isInCall = true;
          _callParticipants = List<Map<String, dynamic>>.from(data['participants'] ?? []);
          _totalCallParticipants = data['totalParticipants'] ?? 0;
        });

        final existingPeers = data['existingParticipants'] ?? [];
        print('🔍 [Admin] connectToExistingPeers 호출 전 (count=${existingPeers.length})');
        if (existingPeers.isNotEmpty) {
          await webrtcService.connectToExistingPeers(existingPeers);
        }
        print('🔍 [Admin] connectToExistingPeers 호출 후');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ 통화 참여 실패: ${data?['message'] ?? ''}')),
        );
      }
    });
  }

  void _leaveCall() async {
    socketService.leaveRoomCall(widget.roomId, (success, data) async {
      if (success) {
        if (mounted) {
          setState(() {
            _isInCall = false;
            _isMuted = false;
          });
        }
        await webrtcService.dispose();
        webrtcService = WebRTCService(socketService);
      }
    });
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    webrtcService.toggleAudio(!_isMuted);
    socketService.toggleMute(widget.roomId, _isMuted);
  }

  // ========================================
  // ✅ 오디오 설정 팝업
  // ========================================
  void _showAudioSettingsPopup() {
    final RenderBox renderBox =
    _audioSettingsKey.currentContext!.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    const double popupWidth = 320;
    const double popupHeight = 180; // 팝업 예상 높이

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                // 배경 터치 시 닫기
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // 팝업 위치
                Positioned(
                  left: position.dx - popupWidth + size.width,
                  top: position.dy - popupHeight - 8,
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[850],
                    child: Container(
                      width: popupWidth,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 헤더
                          Row(
                            children: [
                              const Icon(Icons.tune, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                '오디오 설정',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.close, color: Colors.grey, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 전체 볼륨
                          _buildPopupSlider(
                            icon: _speakerVolume == 0
                                ? Icons.volume_off
                                : _speakerVolume < 0.5
                                ? Icons.volume_down
                                : Icons.volume_up,
                            label: '전체 볼륨',
                            value: _speakerVolume,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (v) {
                              setDialogState(() => _speakerVolume = v);
                              setState(() => _speakerVolume = v);
                              webrtcService.setMasterVolume(v);
                            },
                          ),
                          const SizedBox(height: 12),

                          // 마이크 게인
                          _buildPopupSlider(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            iconColor: _isMuted ? Colors.red.shade300 : Colors.white,
                            label: '마이크',
                            value: _microphoneGain,
                            min: 0.0,
                            max: 2.0,
                            onChanged: _isMuted
                                ? null
                                : (v) {
                              setDialogState(() => _microphoneGain = v);
                              setState(() => _microphoneGain = v);
                              webrtcService.setMicrophoneGain(v);
                            },
                            activeColor: _isMuted ? Colors.grey : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========================================
  // ✅ 참여자별 볼륨 팝업
  // ========================================
  void _showPeerVolumePopup() {
    final ctx = _peerVolumeKey.currentContext;
    if (ctx == null) return;
    final RenderBox renderBox = ctx.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    const double popupWidth = 360;
    // 참여자 수에 따라 높이 동적 계산
    final participants = _callParticipants
        .where((p) => p['userId'] != socketService.userId)
        .toList();
    final double popupHeight = participants.isEmpty
        ? 140
        : (80 + participants.length * 80).clamp(120, 400).toDouble() + 20;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final participants = _callParticipants
                .where((p) => p['userId'] != socketService.userId)
                .toList();

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx - popupWidth + size.width,
                  top: position.dy - popupHeight - 8,
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[850],
                    child: Container(
                      width: popupWidth,
                      constraints: BoxConstraints(maxHeight: popupHeight),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 헤더
                          Row(
                            children: [
                              const Icon(Icons.group, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '참여자별 볼륨 (${participants.length}명)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.close, color: Colors.grey, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          if (participants.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  '다른 참여자가 없습니다',
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            )
                          else
                            Flexible(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: participants.map((participant) {
                                    final peerId = participant['userId'] as String;
                                    final peerName = participant['username'] ??
                                        participant['userName'] ??
                                        'Unknown';
                                    final peerVolume = webrtcService.getPeerVolume(peerId);
                                    final isPeerMuted = webrtcService.isPeerMuted(peerId);

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 참여자 이름 + 음소거 버튼
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                backgroundColor: isPeerMuted
                                                    ? Colors.red.shade700
                                                    : Colors.green.shade700,
                                                child: Text(
                                                  (peerName.isNotEmpty ? peerName[0] : '?')
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  peerName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              // 개별 음소거
                                              IconButton(
                                                icon: Icon(
                                                  isPeerMuted
                                                      ? Icons.volume_off
                                                      : Icons.volume_up,
                                                  color: isPeerMuted
                                                      ? Colors.red.shade300
                                                      : Colors.white,
                                                  size: 18,
                                                ),
                                                onPressed: () {
                                                  webrtcService.togglePeerMute(peerId);
                                                  setDialogState(() {});
                                                  setState(() {});
                                                },
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(
                                                  minWidth: 32,
                                                  minHeight: 32,
                                                ),
                                              ),
                                              // 볼륨 표시
                                              SizedBox(
                                                width: 40,
                                                child: Text(
                                                  isPeerMuted
                                                      ? '음소거'
                                                      : '${(peerVolume * 100).toInt()}%',
                                                  style: TextStyle(
                                                    color: isPeerMuted
                                                        ? Colors.red.shade300
                                                        : Colors.white70,
                                                    fontSize: 11,
                                                  ),
                                                  textAlign: TextAlign.right,
                                                ),
                                              ),
                                            ],
                                          ),
                                          // 볼륨 슬라이더
                                          SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 3,
                                              thumbShape: const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                              overlayShape: const RoundSliderOverlayShape(
                                                overlayRadius: 12,
                                              ),
                                              activeTrackColor:
                                              isPeerMuted ? Colors.grey : Colors.blue,
                                              inactiveTrackColor: Colors.grey[700],
                                              thumbColor:
                                              isPeerMuted ? Colors.grey : Colors.blue,
                                            ),
                                            child: Slider(
                                              value: peerVolume,
                                              min: 0.0,
                                              max: 1.0,
                                              divisions: 20,
                                              onChanged: isPeerMuted
                                                  ? null
                                                  : (value) {
                                                webrtcService.setPeerVolume(
                                                    peerId, value);
                                                setDialogState(() {});
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========================================
  // 팝업 내부 슬라이더 위젯
  // ========================================
  Widget _buildPopupSlider({
    required IconData icon,
    Color? iconColor,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double>? onChanged,
    Color? activeColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: activeColor ?? Colors.blue,
            inactiveTrackColor: Colors.grey[700],
            thumbColor: activeColor ?? Colors.blue,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: 20,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ========================================
  // Build
  // ========================================
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ✅ 통화 중일 때 헤더 + 멤버 칩 (컴팩트 스트립, 제한 높이)
        if (_isInCall)
          Column(
            children: [
              // 멤버 칩 (스크롤 가능, 최대 높이 제한)
              if (widget.joinedMembers.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: _buildMemberChips(),
                ),

              _buildCallHeader(),
            ],
          ),

        // ✅ 통화 시작/참여 버튼 (항상 표시)
        _buildCallButton(),
      ],
    );
  }

  // ========================================
  // 통화 버튼
  // ========================================
  Widget _buildCallButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _toggleCall,
          icon: Icon(
            _isInCall ? Icons.call_end : Icons.phone,
            size: 18,
          ),
          label: Text(
            _isInCall
                ? '통화 종료'
                : _totalCallParticipants > 0
                ? '통화 참여 ($_totalCallParticipants명 통화 중)'
                : '통화 시작',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isInCall
                ? Colors.red.shade700
                : _totalCallParticipants > 0
                ? Colors.blue.shade700
                : Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // 통화 상태 헤더
  // ========================================
  Widget _buildCallHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade800],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '통화 중 · $_totalCallParticipants명',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),

          // ✅ 참여자별 볼륨 (팝업)
          _buildHeaderIconButton(
            key: _peerVolumeKey,
            icon: Icons.group,
            tooltip: '참여자별 볼륨',
            onPressed: _showPeerVolumePopup,
          ),
          const SizedBox(width: 2),

          // ✅ 오디오 설정 (팝업)
          _buildHeaderIconButton(
            key: _audioSettingsKey,
            icon: Icons.tune,
            tooltip: '오디오 설정',
            onPressed: _showAudioSettingsPopup,
          ),
          const SizedBox(width: 2),

          // 음소거
          _buildHeaderIconButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            tooltip: _isMuted ? '음소거 해제' : '음소거',
            isActive: _isMuted,
            activeColor: Colors.red.shade700,
            onPressed: _toggleMute,
          ),
          const SizedBox(width: 2),

          // 통화 종료
          Container(
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: IconButton(
              icon: const Icon(Icons.call_end, color: Colors.white, size: 16),
              onPressed: _leaveCall,
              tooltip: '통화 종료',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
    Color? activeColor,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: isActive ? (activeColor ?? Colors.blue.shade700) : Colors.white24,
        borderRadius: BorderRadius.circular(6),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 16),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  // ========================================
  // 멤버 칩
  // ========================================
  Widget _buildMemberChips() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: widget.joinedMembers.map((member) {
          final isInCall = _callParticipants.any(
                (p) => p['userId'] == member['userId'],
          );
          return Chip(
            avatar: CircleAvatar(
              radius: 12,
              backgroundColor: isInCall ? Colors.green : Colors.grey,
              child: Icon(
                isInCall ? Icons.phone_in_talk : Icons.person,
                size: 12,
                color: Colors.white,
              ),
            ),
            label: Text(
              member['userName'] ?? 'Unknown',
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor:
            isInCall ? Colors.green.shade700 : Colors.grey.shade700,
            labelStyle: const TextStyle(color: Colors.white),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    if (_isInCall) _leaveCall();

    for(final sub in _subs){
      sub.cancel();
    }

    super.dispose();
  }
}
