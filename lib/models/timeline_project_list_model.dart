class ProjectData {
  final double duration;
  final int fps;
  final String projectId;
  // final String room_id;
  final DateTime createdAt;

  ProjectData({
    required this.duration,
    required this.fps,
    required this.projectId,
    // required this.room_id,
    required this.createdAt,
  });

  factory ProjectData.fromJson(Map<String, dynamic> json) {
    // print(json);
    return ProjectData(
      duration: (json['duration'] as num).toDouble(),
      fps: json['fps'] as int,
      projectId: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duration': duration,
      'fps': fps,
      'project_id' : projectId,
      'created_at': createdAt,
    };
  }
}