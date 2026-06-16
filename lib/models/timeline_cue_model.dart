class Cue {
  final String? id;
  final int startTime;
  final int duration;
  final String label;
  final String? comment;
  final String color;
  final Map<String, dynamic>? data;

  Cue({
    this.id,
    required this.startTime,
    required this.duration,
    required this.label,
    this.comment,
    required this.color,
    this.data,
  });

  int get endTime => startTime + duration;

  factory Cue.fromJson(Map<String, dynamic> json) {
    return Cue(
      id: json['id'] as String?,
      startTime: (json['startTime'] as num).toInt(),
      duration: (json['duration'] as num).toInt(),
      label: json['label'] as String,
      comment: json['comment'] as String?,
      color: json['color'] as String,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'startTime': startTime,
      'duration': duration,
      'label': label,
      if (comment != null) 'comment': comment,
      'color': color,
      if (data != null) 'data': data,
    };
  }
}