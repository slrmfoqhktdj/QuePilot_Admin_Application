// services/direct_call_service.dart

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

class DirectWebRTCService {
  final SocketService _socketService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _callId;
  String? _peerId;
  bool _isMuted = false;
  double _speakerVolume = 1.0;

  // 콜백
  Function(MediaStream)? onRemoteStream;
  Function()? onCallConnected;
  Function()? onCallDisconnected;

  DirectWebRTCService(this._socketService);

  String? get callId => _callId;
  String? get peerId => _peerId;
  bool get isMuted => _isMuted;
  bool get isActive => _peerConnection != null;

  // ========================================
  // 초기화
  // ========================================
  Future<bool> initLocalStream() async {
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      print('🎤 [DirectCall] 로컬 오디오 스트림 초기화 완료');
      return true;
    } catch (e) {
      print('❌ [DirectCall] 마이크 초기화 실패: $e');
      return false;
    }
  }

  // ========================================
  // Offer 생성 (발신 측)
  // ========================================
  Future<void> startCall(String callId, String peerId) async {
    _callId = callId;
    _peerId = peerId;

    await _createPeerConnection();

    // Offer 생성
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);

    _socketService.sendDirectWebRTCOffer(callId, peerId, offer.toMap());
    print('📤 [DirectCall] Offer 전송 → $peerId');
  }

  // ========================================
  // Offer 수신 → Answer 생성 (수신 측)
  // ========================================
  Future<void> handleOffer(String callId, String from, dynamic offer) async {
    _callId = callId;
    _peerId = from;

    await _createPeerConnection();

    final remoteDesc = RTCSessionDescription(offer['sdp'], offer['type']);
    await _peerConnection!.setRemoteDescription(remoteDesc);

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(answer);

    _socketService.sendDirectWebRTCAnswer(callId, from, answer.toMap());
    print('📤 [DirectCall] Answer 전송 → $from');
  }

  // ========================================
  // Answer 수신 (발신 측)
  // ========================================
  Future<void> handleAnswer(String from, dynamic answer) async {
    if (_peerConnection == null) return;

    final remoteDesc = RTCSessionDescription(answer['sdp'], answer['type']);
    await _peerConnection!.setRemoteDescription(remoteDesc);
    print('✅ [DirectCall] Answer 수신 ← $from');
  }

  // ========================================
  // ICE Candidate 수신
  // ========================================
  Future<void> handleIceCandidate(String from, dynamic candidate) async {
    if (_peerConnection == null || candidate == null) return;

    final iceCandidate = RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(iceCandidate);
    print('🧊 [DirectCall] ICE Candidate 추가 ← $from');
  }

  // ========================================
  // PeerConnection 생성
  // ========================================
  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(config);

    // 로컬 트랙 추가
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // 원격 트랙 수신
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
        print('🔊 [DirectCall] 원격 오디오 스트림 수신');
      }
    };

    // ICE Candidate 전송
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_callId != null && _peerId != null) {
        _socketService.sendDirectWebRTCIceCandidate(
          _callId!,
          _peerId!,
          candidate.toMap(),
        );
      }
    };

    // 연결 상태 변경
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print('🔗 [DirectCall] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        onCallConnected?.call();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        onCallDisconnected?.call();
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print('🧊 [DirectCall] ICE state: $state');
    };
  }

  // ========================================
  // 음소거 토글
  // ========================================
  void toggleMute() {
    _isMuted = !_isMuted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
    print('🔇 [DirectCall] 음소거: $_isMuted');
  }

  void setMuted(bool muted) {
    _isMuted = muted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  // ========================================
  // 볼륨 조절
  // ========================================
  void setSpeakerVolume(double volume) {
    _speakerVolume = volume;
    // flutter_webrtc에서는 원격 오디오 볼륨 직접 제어가 제한적
    // Helper 메서드가 있다면 여기서 사용
  }

  // ========================================
  // 정리
  // ========================================
  Future<void> dispose() async {
    try {
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        await _peerConnection!.dispose();
        _peerConnection = null;
      }

      _remoteStream = null;
      _callId = null;
      _peerId = null;
      _isMuted = false;

      print('🧹 [DirectCall] 리소스 정리 완료');
    } catch (e) {
      print('⚠️ [DirectCall] 정리 중 오류: $e');
    }
  }
}
