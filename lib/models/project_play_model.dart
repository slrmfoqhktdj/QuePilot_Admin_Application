class ProjectPlayData {
  final String projectId;
  final double time;

  ProjectPlayData({
    required this.projectId,
    required this.time,

  });

  factory ProjectPlayData.fromJson(Map<String, dynamic> json) {

    return ProjectPlayData(
      projectId: json['projectId'] as String,
      time: json['time'] as double,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectId': projectId,
      'time': time,
    };
  }
}