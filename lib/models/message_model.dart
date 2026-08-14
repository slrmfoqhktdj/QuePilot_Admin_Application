class MessageData {
  final String fromUserId;
  String fromUsername;
  final String message;
  final DateTime timestamp;

  MessageData({
    required this.fromUserId,
    required this.fromUsername,
    required this.message,
    required this.timestamp,
  });

  void setFromUserName(String FromUserName) {
    fromUsername = FromUserName;
  }

  factory MessageData.fromJson(Map<String, dynamic> json) {

    return MessageData(
      fromUserId: json['fromUserId'] as String,
      fromUsername: json['fromUsername'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromUserId': fromUserId,
      'fromUsername': fromUsername,
      'message' : message,
      'timestamp': timestamp,
    };
  }
}