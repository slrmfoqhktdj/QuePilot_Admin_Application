import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:que_pilot_admin_01/db/hive_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

import '../db/model/hive_key_model.dart';
import '../models/message_model.dart';
import '../models/timeline_cue_model.dart';
import '../models/service_model.dart';
import 'discovery_service.dart'; // ★ 이벤트 클래스 모음

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  final _hiveService = HiveService();
  SocketService._internal();

  IO.Socket? _mainSocket;
  IO.Socket? _projectSocket;

  String? _projectSocketConnectedProjectId;

  // String serverUrl = 'http://quepilot.local';
  String serverUrl = 'http://192.168.0.7:8888';
  String socketIoPath = '/api';
  // String? currentProjectId;
  // String? currentRoomId;
  // String? currentUsername;
  String type = 'admin';
  String name = 'admin';

  // ★ 현재 세션 역할: 관리자(라이선스 계정) 여부
  bool get isAdminUser => type == 'admin';

  // ★ 자동 로그인(세션 재사용) 시 인증 거부 감지용
  bool _autoLoginExpired = false;
  bool get autoLoginExpired => _autoLoginExpired;
  void resetAutoLoginState() => _autoLoginExpired = false;
  int _reconnectionDelay = 2000; // 소켓 재연결 딜레이 ms
  int _reconnectionDelayMax = 10000; // 소켓 재연결 딜레이 맥스 ms
  double _reconnectionAttempts = double.infinity; // 무한 재연결 (라이선스 인증 대기/서버 재시작 대응)
  String? _adminId;
  String? _sessionCookie;
  String? _userId;

  bool _isMainConnecting = false; // 연결시도중 여부

  bool _isDiscovering = false;  // 서버 주소 찾기 여부
  StreamSubscription? _discoverySub;

  // ★ 세션 만료 시 로그인 화면 복귀용 콜백
  Function()? onSessionExpired;


  IO.Socket? get mainSocket => _mainSocket!;
  IO.Socket? get projectSocket => _projectSocket!;

  // ★ 연결 상태 확인용 프로퍼티
  bool get isMainConnected => _mainSocket?.connected ?? false;
  bool get isMainConnecting => _isMainConnecting;

  String get adminId => _adminId ?? '';
  String get adminName => displayName;
  String? get userId => _userId;

  // ★ 관리자 표시 이름: 설정에 저장된 표시 이름 우선, 없으면 '관리자'
  String get displayName {
    final saved = _hiveService.readDisplayName();
    return saved.isNotEmpty ? saved : '관리자';
  }

  HiveService get hiveService => _hiveService;

  // ═══════════════════════════════════════════
  // StreamControllers
  // ═══════════════════════════════════════════

  // -- 메인: 개인 메시지 --
  final _receivePersonalMessage = StreamController<MessageData>.broadcast();
  Stream<MessageData> get receivePersonalMessage => _receivePersonalMessage.stream;

  // -- 메인: 유저 상태 --
  final _userStatusChanged = StreamController<UserStatusChangedEvent>.broadcast();
  Stream<UserStatusChangedEvent> get userStatusChanged => _userStatusChanged.stream;

  // -- 메인: 1:1 통화 --
  final _directCallAccepted = StreamController<DirectCallAcceptedEvent>.broadcast();
  final _directCallRejected = StreamController<DirectCallRejectedEvent>.broadcast();
  final _directCallEnded = StreamController<DirectCallEndedEvent>.broadcast();
  final _directCallTimeout = StreamController<DirectCallTimeoutEvent>.broadcast();

  Stream<DirectCallAcceptedEvent> get directCallAccepted => _directCallAccepted.stream;
  Stream<DirectCallRejectedEvent> get directCallRejected => _directCallRejected.stream;
  Stream<DirectCallEndedEvent> get directCallEnded => _directCallEnded.stream;
  Stream<DirectCallTimeoutEvent> get directCallTimeout => _directCallTimeout.stream;

  // -- 메인: Direct WebRTC --
  final _directWebRTCOffer = StreamController<DirectWebRTCEvent>.broadcast();
  final _directWebRTCAnswer = StreamController<DirectWebRTCEvent>.broadcast();
  final _directWebRTCIce = StreamController<DirectWebRTCEvent>.broadcast();

  Stream<DirectWebRTCEvent> get directWebRTCOffer => _directWebRTCOffer.stream;
  Stream<DirectWebRTCEvent> get directWebRTCAnswer => _directWebRTCAnswer.stream;
  Stream<DirectWebRTCEvent> get directWebRTCIce => _directWebRTCIce.stream;

  // -- 메인: 트랙 --
  final _trackAdded = StreamController<TrackEvent>.broadcast();
  final _trackUpdated = StreamController<TrackEvent>.broadcast();
  final _trackDeleted = StreamController<TrackDeletedEvent>.broadcast();

  Stream<TrackEvent> get trackAdded => _trackAdded.stream;
  Stream<TrackEvent> get trackUpdated => _trackUpdated.stream;
  Stream<TrackDeletedEvent> get trackDeleted => _trackDeleted.stream;

  // -- 메인: 내 방 권한 갱신 (permissions-updated) --
  final _roomAuthUpdated = StreamController<void>.broadcast();
  Stream<void> get roomAuthUpdated => _roomAuthUpdated.stream;

  // -- 프로젝트: 유저 입퇴장 --
  final _userJoined = StreamController<RoomUserEvent>.broadcast();
  final _userLeft = StreamController<RoomUserEvent>.broadcast();

  Stream<RoomUserEvent> get userJoined => _userJoined.stream;
  Stream<RoomUserEvent> get userLeft => _userLeft.stream;

  // -- 프로젝트: 메시지 --
  final _receiveMessage = StreamController<MessageData>.broadcast();
  final _receiveMessageProjectWhole = StreamController<MessageData>.broadcast();

  Stream<MessageData> get receiveMessage => _receiveMessage.stream;
  Stream<MessageData> get receiveMessageProjectWhole => _receiveMessageProjectWhole.stream;

  // -- 프로젝트: 상태 업데이트 --
  final _stateUpdated = StreamController<StateUpdatedEvent>.broadcast();
  Stream<StateUpdatedEvent> get stateUpdated => _stateUpdated.stream;

  // -- 프로젝트: 방 CRUD --
  final _roomCreated = StreamController<RoomCreatedEvent>.broadcast();
  final _roomUpdated = StreamController<RoomUpdatedEvent>.broadcast();
  final _roomDeleted = StreamController<RoomDeletedEvent>.broadcast();

  Stream<RoomCreatedEvent> get roomCreated => _roomCreated.stream;
  Stream<RoomUpdatedEvent> get roomUpdated => _roomUpdated.stream;
  Stream<RoomDeletedEvent> get roomDeleted => _roomDeleted.stream;

  // -- 프로젝트: 방 통화 --
  final _callParticipantsUpdated = StreamController<CallParticipantsEvent>.broadcast();
  final _userJoinedCall = StreamController<CallUserEvent>.broadcast();
  final _userLeftCall = StreamController<CallUserEvent>.broadcast();
  final _peerMuteChanged = StreamController<PeerMuteEvent>.broadcast();

  Stream<CallParticipantsEvent> get callParticipantsUpdated => _callParticipantsUpdated.stream;
  Stream<CallUserEvent> get userJoinedCall => _userJoinedCall.stream;
  Stream<CallUserEvent> get userLeftCall => _userLeftCall.stream;
  Stream<PeerMuteEvent> get peerMuteChanged => _peerMuteChanged.stream;

  // -- 프로젝트: Room WebRTC --
  final _webRTCOffer = StreamController<RoomWebRTCEvent>.broadcast();
  final _webRTCAnswer = StreamController<RoomWebRTCEvent>.broadcast();
  final _webRTCIce = StreamController<RoomWebRTCEvent>.broadcast();

  Stream<RoomWebRTCEvent> get webRTCOffer => _webRTCOffer.stream;
  Stream<RoomWebRTCEvent> get webRTCAnswer => _webRTCAnswer.stream;
  Stream<RoomWebRTCEvent> get webRTCIce => _webRTCIce.stream;

  // -- 프로젝트: 재생 제어 --
  final _onPlay = StreamController<PlaybackEvent>.broadcast();
  final _onPause = StreamController<PlaybackEvent>.broadcast();
  final _onStop = StreamController<PlaybackEvent>.broadcast();
  final _timelineHeartbeat = StreamController<PlaybackEvent>.broadcast();

  Stream<PlaybackEvent> get onPlayStream => _onPlay.stream;
  Stream<PlaybackEvent> get onPauseStream => _onPause.stream;
  Stream<PlaybackEvent> get onStopStream => _onStop.stream;
  Stream<PlaybackEvent> get timelineHeartbeat => _timelineHeartbeat.stream;

  // ═══════════════════════════════════════════
  // 소켓 → Stream 바인딩
  // ═══════════════════════════════════════════

  void _bindMainSocketToStreams() {
    if (_mainSocket == null) return;

    // 개인 메시지
    _mainSocket!.on('receive-personal-message', (data) {
      _receivePersonalMessage.add(MessageData.fromJson(data));
    });

    // 유저 상태
    _mainSocket!.on('user-status-changed', (data) {
      _userStatusChanged.add(UserStatusChangedEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // 1:1 통화
    _mainSocket!.on('direct-call-accepted', (data) {
      _directCallAccepted.add(DirectCallAcceptedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('direct-call-rejected', (data) {
      _directCallRejected.add(DirectCallRejectedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('direct-call-ended', (data) {
      _directCallEnded.add(DirectCallEndedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('direct-call-timeout', (data) {
      _directCallTimeout.add(DirectCallTimeoutEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // Direct WebRTC
    _mainSocket!.on('direct-webrtc-offer', (data) {
      _directWebRTCOffer.add(DirectWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'offer'));
    });
    _mainSocket!.on('direct-webrtc-answer', (data) {
      _directWebRTCAnswer.add(DirectWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'answer'));
    });
    _mainSocket!.on('direct-webrtc-ice-candidate', (data) {
      _directWebRTCIce.add(DirectWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'candidate'));
    });

    // 트랙
    _mainSocket!.on('track-added', (data) {
      _trackAdded.add(TrackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('track-updated', (data) {
      _trackUpdated.add(TrackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('track-deleted', (data) {
      _trackDeleted.add(TrackDeletedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _mainSocket!.on('permissions-updated', (data) {
      _roomAuthUpdated.add(null);
    });
  }

  void _bindProjectSocketToStreams() {
    if (_projectSocket == null) return;

    // 유저 입퇴장
    _projectSocket!.on('user-joined', (data) {
      _userJoined.add(RoomUserEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('user-left', (data) {
      _userLeft.add(RoomUserEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // 메시지
    _projectSocket!.on('receive-message', (data) {
      _receiveMessage.add(MessageData.fromJson(data));
    });
    _projectSocket!.on('receive-message-project-whole', (data) {
      _receiveMessageProjectWhole.add(MessageData.fromJson(data));
    });

    // 상태
    _projectSocket!.on('state-updated', (data) {
      _stateUpdated.add(StateUpdatedEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // 방 CRUD
    _projectSocket!.on('room-created', (data) {
      _roomCreated.add(RoomCreatedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('room-updated', (data) {
      _roomUpdated.add(RoomUpdatedEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('room-deleted', (data) {
      _roomDeleted.add(RoomDeletedEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // 통화
    _projectSocket!.on('call-participants-updated', (data) {
      _callParticipantsUpdated.add(CallParticipantsEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('user-joined-call', (data) {
      _userJoinedCall.add(CallUserEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('user-left-call', (data) {
      _userLeftCall.add(CallUserEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('peer-mute-changed', (data) {
      _peerMuteChanged.add(PeerMuteEvent.fromJson(Map<String, dynamic>.from(data)));
    });

    // Room WebRTC
    _projectSocket!.on('webrtc-offer', (data) {
      _webRTCOffer.add(RoomWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'offer'));
    });
    _projectSocket!.on('webrtc-answer', (data) {
      _webRTCAnswer.add(RoomWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'answer'));
    });
    _projectSocket!.on('webrtc-ice-candidate', (data) {
      _webRTCIce.add(RoomWebRTCEvent.fromJson(Map<String, dynamic>.from(data), 'candidate'));
    });

    // 재생 제어
    _projectSocket!.on('project-play', (data) {
      _onPlay.add(PlaybackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('project-pause', (data) {
      _onPause.add(PlaybackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('project-stop', (data) {
      _onStop.add(PlaybackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('timeline-auto-stopped', (data) {
      _onStop.add(PlaybackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
    _projectSocket!.on('timeline-heartbeat', (data) {
      _timelineHeartbeat.add(PlaybackEvent.fromJson(Map<String, dynamic>.from(data)));
    });
  }

  // ═══════════════════════════════════════════
  // 연결
  // ═══════════════════════════════════════════

  /// 서버를 자동으로 찾아서 연결
  Future<bool> autoConnect() async {
    if (_isDiscovering) return false;
    _isDiscovering = true;

    print('🔍 서버 자동 탐색 시작...');

    try {
      final result = await DiscoveryService.discoverServer(
        timeout: const Duration(seconds: 5),
      );

      if (result != null) {
        print('✅ 서버 발견: ${result.url}');
        serverUrl = result.url;
        socketIoPath = result.socketPath;

        // Hive에 저장 (다음 실행 시 빠른 연결용)
        _hiveService.sessionSave(HiveKeyModel().lastURL, result.url);
        _hiveService.sessionSave(HiveKeyModel().lastIP, result.ip);

        connectToMainServer();
        _isDiscovering = false;
        return true;
      }

      print('❌ 서버를 찾지 못함');
      _isDiscovering = false;
      return false;
    } catch (e) {
      print('❌ 자동 연결 오류: $e');
      _isDiscovering = false;
      return false;
    }
  }

  /// 서버를 찾을 때까지 계속 시도 (백그라운드)
  void startAutoDiscovery({
    Function(String serverUrl)? onFound,
    Function()? onSearching,
  }) {
    _discoverySub?.cancel();

    _discoverySub = DiscoveryService.discoverServerStream(
      searchTimeout: const Duration(seconds: 5),
      retryInterval: const Duration(seconds: 10),
    ).listen((result) {
      // 이미 같은 서버에 연결되어 있으면 무시
      if (isMainConnected && serverUrl == result.url) return;

      print('✅ 서버 발견: ${result.url}');
      serverUrl = result.url;
      socketIoPath = result.socketPath;
      _hiveService.sessionSave(HiveKeyModel().lastURL, result.url);

      onFound?.call(result.url);

      // 연결 안 되어 있으면 자동 연결
      if (!isMainConnected) {
        connectToMainServer();
      }
    });
  }

  void stopAutoDiscovery() {
    _discoverySub?.cancel();
    _discoverySub = null;
  }

  void connectToMainServer() {

    // ★ 이미 연결 시도 중이면 무시
    if (_isMainConnecting) {
      print('⚠️ 이미 연결 시도 중 — 무시');
      return;
    }

    // ★ 기존 소켓 완전 정리
    if (_mainSocket != null) {
      _mainSocket!.clearListeners();
      _mainSocket!.disconnect();
      _mainSocket!.dispose();
      _mainSocket = null;
      print('🧹 기존 메인 소켓 정리 완료');
    }

    // ★ IO 캐시도 제거
    IO.cache.clear();

    _isMainConnecting = true;


    try {

      _sessionCookie = _hiveService.sessionRead(HiveKeyModel().sessionCookieKey, null);
      print('🔍 [연결시작] 세션쿠키: $_sessionCookie');
      print('🔍 [연결시작] 서버URL: $serverUrl');

      final builder = IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(_reconnectionDelay)
          .setReconnectionDelayMax(_reconnectionDelayMax)
          .setReconnectionAttempts(_reconnectionAttempts)
          .setPath(socketIoPath)
          .setAuth({'type': type});

      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        builder.setExtraHeaders({'Cookie': _sessionCookie!});
      }

      _mainSocket = IO.io(serverUrl, builder.build());

      // ★ 인증 만료/실패 → 세션 초기화 후 로그인 화면 복귀
      _mainSocket!.on('auth-expired', (data) {
        print('⛔ 인증 만료 — 로그인 화면으로 복귀: $data');
        _isMainConnecting = false;
        _autoLoginExpired = true;
        _sessionCookie = null;
        _hiveService.sessionDelete(HiveKeyModel().sessionCookieKey);
        onSessionExpired?.call();
      });

      _mainSocket!.onConnect((_) {
        _isMainConnecting = false;  // ★
        if (kDebugMode) print('메인 서버에 연결됨');
      });

      _mainSocket!.onDisconnect((_) {
        _isMainConnecting = false;
        if (kDebugMode) print('메인 서버 연결 해제됨');
      });

      _mainSocket!.onError((error) {
        _isMainConnecting = false;
        if (kDebugMode) print('연결 오류: $error');
      });

      _mainSocket!.onConnectError((error) {
        print('❌❌❌ 연결 에러: $error');
      });

      _mainSocket!.onReconnect((attemptNumber) {
        print('🔄🔄🔄 재연결 성공: $attemptNumber');
      });

      _mainSocket!.onReconnectAttempt((attemptNumber) {
        print('🔄 재연결 시도 #$attemptNumber');
      });

      _mainSocket!.onReconnectError((error) {
        print('❌ 재연결 에러: $error');
      });

      _mainSocket!.onReconnectFailed((_) {
        _isMainConnecting = false;
        print('💀💀💀 재연결 최종 실패 — 5초 후 자동 재시도');
        Timer(const Duration(seconds: 5), () {
          if (_mainSocket != null && !_mainSocket!.connected) {
            connectToMainServer();
          }
        });
      });

      // ★ 소켓 내부 이벤트 전부 모니터링
      _mainSocket!.onAny((event, data) {
        print('📡 [ANY] 이벤트: $event');
        print('📡 [ANY] 이벤트: $data');
      });


      _bindMainSocketToStreams();
      _mainSocket!.connect();
    } catch (e) {
      _isMainConnecting = false;
      print('connection error = $e');
    }
  }

  // ═══════════════════════════════════════════
  // HTTP 로그인 / 로그아웃
  // ═══════════════════════════════════════════

  /// POST /admin/login 또는 POST /login → 세션 쿠키 획득
  Future<Map<String, dynamic>> login(
    String loginId,
    String password, {
    required bool isAdmin,
  }) async {
    try {
      final endpoint = isAdmin ? '$serverUrl/admin/login' : '$serverUrl/login';
      final body = jsonEncode({'login_id': loginId, 'password': password});

      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse(endpoint));
        request.headers.contentType = ContentType.json;
        request.write(body);

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody) as Map<String, dynamic>;

        if (response.statusCode == 200 && data['success'] == true) {
          final setCookie = response.headers.value('set-cookie');
          final cookie = _extractSessionCookie(setCookie);
          if (cookie != null) {
            _sessionCookie = cookie;
            // ★ 항상 Hive에 저장 (현재 실행 중 재연결/화면 전환에 필요)
            await _hiveService.sessionSave(HiveKeyModel().sessionCookieKey, cookie);
            print('🍪 세션 쿠키 저장됨: $cookie');
          }

          type = isAdmin ? 'admin' : 'client';
          name = loginId;

          final adminId = data['adminId'];
          if (adminId != null) {
            _adminId = adminId;
            _userId = adminId.toString();
          }

          final user = data['user'];
          if (user != null && user is Map<String, dynamic>) {
            name = user['name']?.toString() ?? name;
            final uid = user['id'];
            if (uid != null) _userId = uid.toString();
          }
        }

        return data;
      } finally {
        client.close();
      }
    } catch (e) {
      print('❌ 로그인 오류: $e');
      return {'success': false, 'message': '서버 연결에 실패했습니다'};
    }
  }

  /// POST /logout → 세션 파괴
  Future<bool> logout() async {
    try {
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        final client = HttpClient();
        try {
          final request = await client.postUrl(Uri.parse('$serverUrl/logout'));
          request.headers.set(HttpHeaders.cookieHeader, _sessionCookie!);
          await request.close();
        } finally {
          client.close();
        }
      }

      disconnect();
      _sessionCookie = null;
      await _hiveService.sessionDelete(HiveKeyModel().sessionCookieKey);
      _adminId = null;
      _userId = null;
      type = 'admin';
      print('✅ 로그아웃 완료');
      return true;
    } catch (e) {
      print('❌ 로그아웃 오류: $e');
      return false;
    }
  }

  /// 자동 로그인(세션 쿠키 재사용) 시 내 userId/이름 복원 — GET /session
  Future<bool> restoreSessionInfo() async {
    if (_sessionCookie == null || _sessionCookie!.isEmpty) return false;
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('$serverUrl/session'));
        request.headers.set(HttpHeaders.cookieHeader, _sessionCookie!);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (response.statusCode == 200 && data['success'] == true) {
          final user = data['user'];
          if (user != null && user is Map<String, dynamic>) {
            final uid = user['id']?.toString();
            if (uid != null) {
              _userId = uid;
              // 관리자 세션은 userId == adminId
              if (type == 'admin') _adminId = uid;
            }
            final userName = user['name']?.toString();
            if (userName != null && userName.isNotEmpty) name = userName;
          }
          return true;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('❌ 세션 정보 복원 오류: $e');
    }
    return false;
  }

  /// "localSessionId=s%3Aabc123.sig; Path=/; HttpOnly" → "localSessionId=s%3Aabc123.sig"
  String? _extractSessionCookie(String? setCookieHeader) {
    if (setCookieHeader == null) return null;
    for (final cookie in setCookieHeader.split(',')) {
      final trimmed = cookie.trim();
      if (trimmed.startsWith('localSessionId=')) {
        return trimmed.split(';')[0].trim();
      }
    }
    return null;
  }

  Future<void> connectToProject(
      String projectId,
      Function() onConnected,
      Function()? onDisConnected,
      Function(String error)? onError,
      ) async {

    // final previousProjectId = _projectSocketConnectedProjectId;

    if (_projectSocket != null) {
      _projectSocket!.clearListeners();
      _projectSocket!.disconnect();
      _projectSocket!.dispose();
      _projectSocket = null;
      _projectSocketConnectedProjectId = null;
    }

    // ★ 프로젝트 소켓 캐시 제거
    IO.cache.remove('$serverUrl/$projectId');

    // currentProjectId = projectId;

    if (_sessionCookie == null) {
      onError?.call('세션 쿠키 없음');
      return;
    }

    await Future.delayed(const Duration(milliseconds: 500));

    _projectSocket = IO.io(
      '$serverUrl/$projectId',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(_reconnectionDelay)
          .setReconnectionDelayMax(_reconnectionDelayMax)
          .setReconnectionAttempts(_reconnectionAttempts)
          // .enableForceNew()
          .setPath(socketIoPath)
          .setAuth({'type': type, 'name': name})
          .setExtraHeaders({'cookie': _sessionCookie!})
          .build(),
    );

    // ★★★ 핵심: 현재 소켓 인스턴스를 캡처하여 콜백에서 비교 ★★★
    final thisSocket = _projectSocket;

    _projectSocket!.onConnect((_) {

      // ★ 이 소켓이 여전히 현재 활성 소켓인지 확인
      if (_projectSocket != thisSocket) {
        print('⚠️ onConnect: 이미 다른 소켓으로 교체됨 — 무시');
        return;
      }

      if (kDebugMode) print('프로젝트 $projectId에 연결됨');
      _projectSocketConnectedProjectId = projectId;
      onConnected?.call();
    });

    _projectSocket!.onDisconnect((_) {

      // ★★★ 핵심: 이 소켓이 현재 활성 소켓이 아니면 콜백 호출하지 않음 ★★★
      if (_projectSocket != thisSocket) {
        print('⚠️ onDisconnect: 이전 소켓의 이벤트 — 무시');
        return;
      }

      if (kDebugMode) print('프로젝트 $projectId 연결 해제됨');
      if (_projectSocketConnectedProjectId == projectId) {
        _projectSocketConnectedProjectId = null;
      }
      onDisConnected?.call();
    });

    _projectSocket!.onError((error) {

      // ★ 동일하게 현재 소켓인지 확인
      if (_projectSocket != thisSocket) {
        print('⚠️ onError: 이전 소켓의 이벤트 — 무시');
        return;
      }

      if (kDebugMode) print('연결 오류: $error');
      if (_projectSocketConnectedProjectId == projectId) {
        _projectSocketConnectedProjectId = null;
      }
      onError?.call(error.toString());
    });

    _bindProjectSocketToStreams();
    _projectSocket!.connect();
  }

  // ═══════════════════════════════════════════
  // Emit 메서드
  // ═══════════════════════════════════════════

  // -- 프로젝트 CRUD --
  void getProjectList(Function(List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('project-list', {}, ack: (data) {
      data['success'] == true
          ? callback(List<Map<String, dynamic>>.from(data['projects'] ?? []))
          : callback([]);
    });
  }

  void createProject(String projectName, int duration,  Function(bool, Map<String, dynamic>) callback) {
    _mainSocket!.emitWithAck('project-create', {
      'projectName': projectName, 'duration': duration,
    }, ack: (data) {
      callback(data['success'] ?? false, data['projects'] ?? {});
    });
  }

  void updateProject(String projectId, String projectName, int duration, Function(bool, List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('project-update', {
      'projectId': projectId, 'projectName': projectName, 'duration': duration,
    }, ack: (data) {
      callback(data['success'] ?? false, List<Map<String, dynamic>>.from(data['projects'] ?? []));
    });
  }

  void deleteProject(String projectId, Function(bool, List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('project-remove', {'projectId': projectId}, ack: (data) {
      callback(data['success'] ?? false, List<Map<String, dynamic>>.from(data['projects'] ?? []));
    });
  }

  // -- 유저 CRUD --
  void getUserList(Function(List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('user-list', {}, ack: (data) {
      data['success'] == true
          ? callback(List<Map<String, dynamic>>.from(data['users'] ?? []))
          : callback([]);
    });
  }

  void createUser(String login_id, String name, String password, Function(bool, Map<String, dynamic>?) callback) {
    _mainSocket!.emitWithAck('user-create', {
      'login_id': login_id, 'name': name, 'password': password,
    }, ack: (data) {
      callback(data['success'] ?? false, data['user']);
    });
  }

  void updateUser(String userId, String login_id, String name, Function(bool, Map<String, dynamic>?) callback) {
    _mainSocket!.emitWithAck('user-update', {
      'userId': userId, 'login_id': login_id, 'name': name,
    }, ack: (data) {
      callback(data['success'] ?? false, data['user']);
    });
  }

  void updateUserPassword(String userId, Function(bool, String) callback) {
    _mainSocket!.emitWithAck('user-password-update', {'userId': userId}, ack: (data) {
      callback(data['success'] ?? false, data['password']);
    });
  }

  void deleteUser(String userId, Function(bool) callback) {
    _mainSocket!.emitWithAck('user-remove', {'userId': userId}, ack: (data) {
      callback(data['success'] ?? false);
    });
  }

  void getRoomListUserAuth(Function(bool, List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('user-auth-roomlist', {}, ack: (data) {
      callback(data['success'] ?? false, List<Map<String, dynamic>>.from(data['roomList'] ?? []));
    });
  }

  void getUserAuthList(String? userId, Function(bool, List<Map<String, dynamic>>) callback) {
    // 서버가 일반 사용자는 세션 기준(본인)으로 강제하므로 userId 미지원(자동로그인)도 동작
    _mainSocket!.emitWithAck('user-auth-list', {'userId': userId ?? ''}, ack: (data) {
      callback(data['success'] ?? false, List<Map<String, dynamic>>.from(data['roomList'] ?? []));
    });
  }

  void updateUserAuth(String userId, List<String> updateRoomIds, List<String> deleteRoomIds, Function(bool) callback) {
    _mainSocket!.emitWithAck('user-auth-update', {
      'userId': userId, 'updateRoomIds': updateRoomIds, 'deleteRoomIds': deleteRoomIds,
    }, ack: (data) {
      callback(data['success'] ?? false);
    });
  }

  // -- 타임라인/트랙 --
  void getTimelineList(Function(List<dynamic>) callback) {
    _mainSocket!.emitWithAck('timeline-list', {}, ack: (data) {
      data['success'] == true ? callback(data['timelines'] ?? []) : callback([]);
    });
  }

  void getProjectTimelinesAndRooms(String projectId, Function(Map<String, dynamic>?) callback) {
    _mainSocket!.emitWithAck('project-timeline-room', {'projectId': projectId}, ack: (data) {
      data['success'] == true ? callback(data['data'] ?? {}) : callback(null);
    });
  }

  void addTrack(String projectId, String name, String roomId, List<Cue> cues, Function(bool, Map<String, dynamic>?) callback) {
    _mainSocket!.emitWithAck('create-track', {
      'projectId': projectId, 'name': name, 'roomId': roomId, 'cues': cues,
    }, ack: (data) {
      data['success'] == true ? callback(true, data['track']) : callback(false, null);
    });
  }

  void updateTrack(String projectId, String trackId, String name, String roomId, List<Cue> cues, Function(bool, Map<String, dynamic>?) callback) {
    _mainSocket!.emitWithAck('update-track', {
      'projectId': projectId, 'trackId': trackId, 'name': name, 'roomId': roomId, 'cues': cues,
    }, ack: (data) {
      data['success'] == true ? callback(true, data['track']) : callback(false, null);
    });
  }

  void deleteTrack(String projectId, String roomId, String trackId, Function(bool, String?) callback) {
    _mainSocket!.emitWithAck('delete-track', {
      'projectId': projectId, 'roomId': roomId, 'trackId': trackId,
    }, ack: (data) {
      data['success'] == true ? callback(true, data['trackId']) : callback(false, null);
    });
  }

  // -- 방 CRUD --
  void createRoom(String roomName, Function(bool) callback) {
    _projectSocket!.emitWithAck('create-room', {'roomName': roomName}, ack: (data) {
      callback(data['success'] ?? false);
    });
  }

  void deleteRoom(String roomId, Function(bool) callback) {
    _projectSocket!.emitWithAck('delete-room', {'roomId': roomId}, ack: (data) {
      callback(data['success'] ?? false);
    });
  }

  void updateRoom(String roomId, String roomName, Function(bool) callback) {
    _projectSocket!.emitWithAck('update-room', {'roomId': roomId, 'roomName': roomName}, ack: (data) {
      callback(data['success'] ?? false);
    });
  }

  void joinRoom(String roomId, String username, Function(bool, List<Map<String, dynamic>>) callback) {
    // currentRoomId = roomId;
    // currentUsername = username;
    _projectSocket!.emitWithAck('join-room', {'roomId': roomId, 'userName': username}, ack: (data) {
      data['success'] == true
          ? callback(true, List<Map<String, dynamic>>.from(data['members'] ?? []))
          : callback(false, []);
    });
  }

  void getAllRooms(Function(List<Map<String, dynamic>>) callback) {
    _projectSocket!.emitWithAck('room-list', {}, ack: (data) {
      if (data['success']) callback(List<Map<String, dynamic>>.from(data['rooms']));
    });
  }

  void getRoomInfo(String roomId, Function(bool, dynamic) callback) {
    _projectSocket?.emitWithAck('get-room-info', {'roomId': roomId}, ack: (data) {
      callback(data?['success'] == true, data?['room']);
    });
  }

  void getTimeLine(String roomId, Function(Map<String, dynamic>?) callback) {
    _projectSocket!.emitWithAck('get-timeline', {'roomId': roomId}, ack: (data) {
      data['success'] == true ? callback(data['timeline']) : callback(null);
    });
  }

  void getRoomMessages(String roomId, Function(List<Map<String, dynamic>>) callback) {
    _projectSocket!.emitWithAck('get-messages-room', {'roomId': roomId}, ack: (data) {
      data['success'] == true
          ? callback(List<Map<String, dynamic>>.from(data['messages'] ?? []))
          : callback([]);
    });
  }

  void getPersonalMessages(String userId, Function(List<Map<String, dynamic>>) callback) {
    _mainSocket!.emitWithAck('get-messages-personal', {'userId': userId}, ack: (data) {
      data['success'] == true
          ? callback(List<Map<String, dynamic>>.from(data['messages'] ?? []))
          : callback([]);
    });
  }

  // -- 메시지 --
  void sendMessage(String message) {
    _projectSocket!.emit('send-message', {'message': message});
  }

  void sendPersonalMessage(String userId, String message, Function(bool, Map<String, dynamic>) callback) {
    _mainSocket!.emitWithAck('send-personal-message', {
      'userId': userId, 'fromUsername': displayName, 'message': message,
    }, ack: (data) {
      callback(data['success'], data['messageData'] ?? <String, dynamic>{});
    });
  }

  void sendMessageWhole(String message, Function(bool) callback) {
    _projectSocket!.emitWithAck('project-message-whole', {'message': message}, ack: (data) {
      callback(data['success']);
    });
  }

  void sendTimelineUpdated(Map<String, dynamic> timelinedata) {
    _projectSocket!.emit('timeline-updated', {'timeline': timelinedata});
  }

  void updateState(dynamic state) {
    _projectSocket!.emit('update-state', {'state': state});
  }

  void leaveRoom() {
    _projectSocket?.emitWithAck('leave-room', {});
    // currentRoomId = null;
  }

  // -- 통화 (방) --
  void getActiveCall(String roomId, Function(bool, dynamic) callback) {
    _projectSocket?.emitWithAck('get-active-call', {'roomId': roomId}, ack: (response) {
      callback(response?['success'] == true, response);
    });
  }

  void joinRoomCall(String roomId, bool isMuted, Function(bool, dynamic) callback) {
    _projectSocket?.emitWithAck('join-room-call', {'roomId': roomId, 'isMuted': isMuted}, ack: (response) {
      callback(response?['success'] == true, response);
    });
  }

  void leaveRoomCall(String roomId, Function(bool, dynamic) callback) {
    _projectSocket?.emitWithAck('leave-room-call', {'roomId': roomId}, ack: (response) {
      callback(response?['success'] == true, response);
    });
  }

  void toggleMute(String roomId, bool isMuted) {
    _projectSocket?.emit('toggle-mute', {'roomId': roomId, 'isMuted': isMuted});
  }

  // -- 1:1 통화 emit --
  void requestDirectCall(String targetUserId, String callerName, Function(bool, String?, String?) callback) {
    _mainSocket?.emitWithAck('request-direct-call', {
      'targetUserId': targetUserId, 'callerName': callerName,
    }, ack: (response) {
      callback(response['success'] ?? false, response['callId'], response['message']);
    });
  }

  void cancelDirectCall(String callId, Function(bool)? callback) {
    _mainSocket?.emitWithAck('cancel-direct-call', {'callId': callId}, ack: (response) {
      callback?.call(response['success'] ?? false);
    });
  }

  void endDirectCall(String callId, Function(bool)? callback) {
    _mainSocket?.emitWithAck('end-direct-call', {'callId': callId}, ack: (response) {
      callback?.call(response['success'] ?? false);
    });
  }

  // -- WebRTC (Room) --
  void sendWebRTCOffer(String to, dynamic offer) {
    _projectSocket?.emit('webrtc-offer', {'to': to, 'offer': offer});
  }

  void sendWebRTCAnswer(String to, dynamic answer) {
    _projectSocket?.emit('webrtc-answer', {'to': to, 'answer': answer});
  }

  void sendWebRTCIceCandidate(String to, dynamic candidate) {
    _projectSocket?.emit('webrtc-ice-candidate', {'to': to, 'candidate': candidate});
  }

  // -- WebRTC (Direct) --
  void sendDirectWebRTCOffer(String callId, String to, dynamic offer) {
    _mainSocket?.emit('direct-webrtc-offer', {'callId': callId, 'to': to, 'offer': offer});
  }

  void sendDirectWebRTCAnswer(String callId, String to, dynamic answer) {
    _mainSocket?.emit('direct-webrtc-answer', {'callId': callId, 'to': to, 'answer': answer});
  }

  void sendDirectWebRTCIceCandidate(String callId, String to, dynamic candidate) {
    _mainSocket?.emit('direct-webrtc-ice-candidate', {'callId': callId, 'to': to, 'candidate': candidate});
  }

  // -- 재생 제어 --
  void sendPlay(String projectId, double time ,Function(bool) callback) {
    _mainSocket!.emitWithAck('project-play', {'projectId': projectId, 'time' : time}, ack: (data) {
      callback(data['success']);
    });
  }

  void sendPause(String projectId, double time, Function(bool) callback) {
    _mainSocket!.emitWithAck('project-pause', {'projectId': projectId, 'time' : time}, ack: (data) {
      callback(data['success']);
    });
  }

  void sendStop(String projectId, Function(bool) callback) {
    _mainSocket!.emitWithAck('project-stop', {'projectId': projectId}, ack: (data) {
      callback(data['success']);
    });
  }

  // ═══════════════════════════════════════════
  // 정리
  // ═══════════════════════════════════════════

  void disconnect() {
    if (_projectSocket != null) {
      _projectSocket!.clearListeners();
      _projectSocket!.disconnect();
      _projectSocket!.dispose();
      _projectSocket = null;
      _projectSocketConnectedProjectId = null;
    }

    if (_mainSocket != null) {
      _mainSocket!.clearListeners();
      _mainSocket!.disconnect();
      _mainSocket!.dispose();
      _mainSocket = null;
    }

    // ★ 캐시 전체 정리
    IO.cache.clear();

    _isMainConnecting = false;
  }

  void disposeAll() {
    stopAutoDiscovery();
    disconnect();
  }
}
