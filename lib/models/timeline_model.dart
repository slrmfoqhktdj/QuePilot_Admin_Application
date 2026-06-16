import 'package:que_pilot_admin_01/models/timeline_track_model.dart';

class TimelineData {
  final double duration;
  // final int fps;
  final String projectId;
  // final String room_id;
  final List<Track> tracks;
  final DateTime createdAt;

  TimelineData({
    required this.duration,
    // required this.fps,
    required this.projectId,
    // required this.room_id,
    required this.tracks,
    required this.createdAt,
  });

  factory TimelineData.fromJson(Map<String, dynamic> json) {
    // print(json);
    return TimelineData(
      duration: (json['duration'] as num).toDouble(),
      // fps: json['fps'] as int,
      projectId: json['id'] as String,
      // room_id: json['room_id'] as String,
      tracks: (json['tracks'] as List<dynamic>)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      // 'fps': fps,
      'project_id' : projectId,
      // 'room_id' : room_id,
      'tracks': tracks.map((e) => e.toJson()).toList(),
      'created_at': createdAt,
    };
  }
}


