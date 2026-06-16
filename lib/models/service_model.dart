// ═══════════════════════════════════════════
// 1:1 통화 이벤트
// ═══════════════════════════════════════════

class DirectCallAcceptedEvent {
  final String callId;
  final String receiverId;
  final String receiverName;

  DirectCallAcceptedEvent({required this.callId, required this.receiverId, required this.receiverName});

  factory DirectCallAcceptedEvent.fromJson(Map<String, dynamic> data) {
    return DirectCallAcceptedEvent(
      callId: data['callId'] as String,
      receiverId: data['receiverId'] as String,
      receiverName: data['receiverName'] as String? ?? 'User',
    );
  }
}

class DirectCallRejectedEvent {
  final String callId;
  final String receiverId;
  final String receiverName;

  DirectCallRejectedEvent({required this.callId, required this.receiverId, required this.receiverName});

  factory DirectCallRejectedEvent.fromJson(Map<String, dynamic> data) {
    return DirectCallRejectedEvent(
      callId: data['callId'] as String,
      receiverId: data['receiverId'] as String,
      receiverName: data['receiverName'] as String? ?? 'User',
    );
  }
}

class DirectCallEndedEvent {
  final String callId;
  final String endedBy;
  final String endedByName;
  final String? reason;

  DirectCallEndedEvent({required this.callId, required this.endedBy, required this.endedByName, this.reason});

  factory DirectCallEndedEvent.fromJson(Map<String, dynamic> data) {
    return DirectCallEndedEvent(
      callId: data['callId'] as String,
      endedBy: data['endedBy'] as String,
      endedByName: data['endedByName'] as String? ?? 'Unknown',
      reason: data['reason'] as String?,
    );
  }
}

class DirectCallTimeoutEvent {
  final String callId;
  final String receiverId;

  DirectCallTimeoutEvent({required this.callId, required this.receiverId});

  factory DirectCallTimeoutEvent.fromJson(Map<String, dynamic> data) {
    return DirectCallTimeoutEvent(
      callId: data['callId'] as String,
      receiverId: data['receiverId'] as String,
    );
  }
}

class DirectWebRTCEvent {
  final String callId;
  final String from;
  final dynamic payload;

  DirectWebRTCEvent({required this.callId, required this.from, required this.payload});

  factory DirectWebRTCEvent.fromJson(Map<String, dynamic> data, String payloadKey) {
    return DirectWebRTCEvent(
      callId: data['callId'] as String,
      from: data['from'] as String,
      payload: data[payloadKey],
    );
  }
}

// ═══════════════════════════════════════════
// 유저 상태
// ═══════════════════════════════════════════

class UserStatusChangedEvent {
  final String userId;
  final String userName;
  final int online;
  final String? ip;
  final String? projectId;

  UserStatusChangedEvent({required this.userId, required this.userName, required this.online, this.ip, this.projectId});

  factory UserStatusChangedEvent.fromJson(Map<String, dynamic> data) {
    return UserStatusChangedEvent(
      userId: data['userId'] as String,
      userName: data['userName'] as String? ?? '',
      online: data['online'] as int? ?? 0,
      ip: data['ip'] as String?,
      projectId: data['projectId'] as String?,
    );
  }
}

// ═══════════════════════════════════════════
// 트랙
// ═══════════════════════════════════════════

class TrackEvent {
  final String projectId;
  final Map<String, dynamic> track;

  TrackEvent({required this.projectId, required this.track});

  factory TrackEvent.fromJson(Map<String, dynamic> data) {
    return TrackEvent(
      projectId: data['projectId'] as String,
      track: Map<String, dynamic>.from(data['track'] ?? {}),
    );
  }
}

class TrackDeletedEvent {
  final String projectId;
  final String trackId;

  TrackDeletedEvent({required this.projectId, required this.trackId});

  factory TrackDeletedEvent.fromJson(Map<String, dynamic> data) {
    return TrackDeletedEvent(
      projectId: data['projectId'] as String,
      trackId: data['trackId'] as String,
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: 유저 입퇴장
// ═══════════════════════════════════════════

class RoomUserEvent {
  final String userId;
  final String userName;
  final int totalMembers;
  final DateTime timestamp;

  RoomUserEvent({required this.userId, required this.userName, required this.totalMembers, required this.timestamp});

  factory RoomUserEvent.fromJson(Map<String, dynamic> data) {
    return RoomUserEvent(
      userId: data['userId'] as String,
      userName: data['userName'] as String,
      totalMembers: data['totalMembers'] as int? ?? 0,
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: 상태
// ═══════════════════════════════════════════

class StateUpdatedEvent {
  final String from;
  final String fromUsername;
  final dynamic state;

  StateUpdatedEvent({required this.from, required this.fromUsername, required this.state});

  factory StateUpdatedEvent.fromJson(Map<String, dynamic> data) {
    return StateUpdatedEvent(
      from: data['from'] as String,
      fromUsername: data['fromUsername'] as String,
      state: data['state'],
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: 방 CRUD
// ═══════════════════════════════════════════

class RoomCreatedEvent {
  final String roomId;
  final String roomName;
  final DateTime createdAt;

  RoomCreatedEvent({required this.roomId, required this.roomName, required this.createdAt});

  factory RoomCreatedEvent.fromJson(Map<String, dynamic> data) {
    return RoomCreatedEvent(
      roomId: data['roomId'] as String,
      roomName: data['roomName'] as String,
      createdAt: DateTime.parse(data['createdAt'] as String),
    );
  }
}

class RoomUpdatedEvent {
  final String roomId;
  final String roomName;

  RoomUpdatedEvent({required this.roomId, required this.roomName});

  factory RoomUpdatedEvent.fromJson(Map<String, dynamic> data) {
    return RoomUpdatedEvent(
      roomId: data['roomId'] as String,
      roomName: data['roomName'] as String,
    );
  }
}

class RoomDeletedEvent {
  final String roomId;

  RoomDeletedEvent({required this.roomId});

  factory RoomDeletedEvent.fromJson(Map<String, dynamic> data) {
    return RoomDeletedEvent(
      roomId: data['roomId'] as String,
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: 통화
// ═══════════════════════════════════════════

class CallParticipantsEvent {
  final List<Map<String, dynamic>> participants;
  final int totalParticipants;

  CallParticipantsEvent({required this.participants, required this.totalParticipants});

  factory CallParticipantsEvent.fromJson(Map<String, dynamic> data) {
    return CallParticipantsEvent(
      participants: List<Map<String, dynamic>>.from(data['participants'] ?? []),
      totalParticipants: data['totalParticipants'] as int? ?? 0,
    );
  }
}

class CallUserEvent {
  final String userId;
  final String username;

  CallUserEvent({required this.userId, required this.username});

  factory CallUserEvent.fromJson(Map<String, dynamic> data) {
    return CallUserEvent(
      userId: data['userId'] as String,
      username: data['username'] as String,
    );
  }
}

class PeerMuteEvent {
  final String userId;
  final bool isMuted;

  PeerMuteEvent({required this.userId, required this.isMuted});

  factory PeerMuteEvent.fromJson(Map<String, dynamic> data) {
    return PeerMuteEvent(
      userId: data['userId'] as String,
      isMuted: data['isMuted'] as bool,
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: Room WebRTC
// ═══════════════════════════════════════════

class RoomWebRTCEvent {
  final String from;
  final dynamic payload;

  RoomWebRTCEvent({required this.from, required this.payload});

  factory RoomWebRTCEvent.fromJson(Map<String, dynamic> data, String payloadKey) {
    return RoomWebRTCEvent(
      from: data['from'] as String,
      payload: data[payloadKey],
    );
  }
}

// ═══════════════════════════════════════════
// 프로젝트: 재생 제어
// ═══════════════════════════════════════════

class PlaybackEvent {
  final String projectId;
  final bool isPlaying;
  final double currentTime;

  PlaybackEvent({required this.projectId, required this.currentTime, required this.isPlaying});

  factory PlaybackEvent.fromJson(Map<String, dynamic> data) {
    return PlaybackEvent(
      projectId: data['projectId'] as String,
      isPlaying : data['isPlaying'] as bool,
      currentTime: data['currentTime'] is int? data['currentTime'].toDouble() : data['currentTime'],
    );
  }
}
