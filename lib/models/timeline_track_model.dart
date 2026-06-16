import 'package:que_pilot_admin_01/models/timeline_cue_model.dart';

class Track {
  final String id;
  final String name;
  // final String color;
  final String room_id;
  final List<Cue> cues;

  Track({
    required this.id,
    required this.name,
    // required this.color,
    required this.room_id,
    required this.cues,
  });

  factory Track.fromJson(Map<String, dynamic> json) {

    return Track(
      id: json['id'] as String,
      name: json['name'] as String,
      // color: json['color'] as String,
      room_id: json['room_id'] as String,
      cues: (json['cues'] as List<dynamic>)
          .map((e) => Cue.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cues': cues.map((e) => e.toJson()).toList(),
    };
  }
}