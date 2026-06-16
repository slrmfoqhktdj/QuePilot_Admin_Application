import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveryResult {
  final String ip;
  final int port;
  final String url;
  final String socketPath;
  final String serverName;

  DiscoveryResult({
    required this.ip,
    required this.port,
    required this.url,
    required this.socketPath,
    required this.serverName,
  });

  factory DiscoveryResult.fromJson(Map<String, dynamic> json) {
    return DiscoveryResult(
      ip: json['ip'] ?? '',
      port: json['port'] is int ? json['port'] : int.tryParse(json['port'].toString()) ?? 8888,
      url: json['url'] ?? '',
      socketPath: json['socketPath'] ?? '/api',
      serverName: json['name'] ?? '',
    );
  }

  @override
  String toString() => 'DiscoveryResult($url, name: $serverName)';
}

class DiscoveryService {
  static const int _discoveryPort = 9999;
  static const String _discoveryMagic = 'QUEPILOT_DISCOVER';
  static const Duration _defaultTimeout = Duration(seconds: 5);

  /// 내부망에서 QuePilot 서버를 자동으로 찾습니다.
  /// 타임아웃 내에 서버를 찾으면 DiscoveryResult 반환, 못 찾으면 null.
  static Future<DiscoveryResult?> discoverServer({
    Duration timeout = _defaultTimeout,
  }) async {
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // OS가 사용 가능한 포트 자동 할당
      );
      socket.broadcastEnabled = true;

      final completer = Completer<DiscoveryResult?>();
      Timer? timer;

      // 타임아웃 설정
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          print('⏰ 서버 탐색 타임아웃 (${timeout.inSeconds}초)');
          completer.complete(null);
        }
      });

      // 응답 수신 대기
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram == null) return;

          try {
            final response = utf8.decode(datagram.data);
            final json = jsonDecode(response) as Map<String, dynamic>;

            if (json['magic'] == 'QUEPILOT_SERVER') {
              print('✅ 서버 발견: ${json['url']} (${json['name']})');

              if (!completer.isCompleted) {
                timer?.cancel();
                completer.complete(DiscoveryResult.fromJson(json));
              }
            }
          } catch (e) {
            print('⚠️ 응답 파싱 실패: $e');
          }
        }
      });

      // 브로드캐스트 전송
      final message = utf8.encode(_discoveryMagic);
      socket.send(
        message,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
      print('📡 서버 탐색 브로드캐스트 전송 (포트: $_discoveryPort)');

      // 1초 간격으로 재전송 (첫 패킷이 유실될 수 있으므로)
      final resendTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!completer.isCompleted) {
          socket?.send(
            message,
            InternetAddress('255.255.255.255'),
            _discoveryPort,
          );
        }
      });

      final result = await completer.future;

      resendTimer.cancel();
      return result;
    } catch (e) {
      print('❌ 디스커버리 오류: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  /// 서버를 찾을 때까지 반복 시도합니다.
  /// 한 번 찾으면 Stream이 값을 emit하고, 이후에도 주기적으로 확인합니다.
  static Stream<DiscoveryResult> discoverServerStream({
    Duration searchTimeout = _defaultTimeout,
    Duration retryInterval = const Duration(seconds: 10),
  }) async* {
    while (true) {
      final result = await discoverServer(timeout: searchTimeout);
      if (result != null) {
        yield result;
      }
      await Future.delayed(retryInterval);
    }
  }
}
