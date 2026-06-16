import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import '../models/timeline_cue_model.dart';
import '../models/timeline_model.dart';
import '../models/timeline_track_model.dart';

class TimelineController extends ChangeNotifier {
  TimelineData? _timelineData;
  double _currentTime = 0;
  bool _isPlaying = false;
  Timer? _timer;
  double _playbackSpeed = 1.0;
  double _zoom = 1.0;

  final int _frame_milliseconds = 16;

  // 정지시 호출되는 콜백
  VoidCallback? onStopCallback;

  TimelineData? get timelineData => _timelineData;
  double get currentTime => _currentTime;
  bool get isPlaying => _isPlaying;
  double get playbackSpeed => _playbackSpeed;
  double get zoom => _zoom;

  // JSON Map에서 직접 로드
  void loadFromMap(Map<String, dynamic> timelineMap) {
    try {
      _timelineData = TimelineData.fromJson(timelineMap);
      _currentTime = 0;
      notifyListeners();
      if (kDebugMode) {
        print('타임라인 로드 성공: ${_timelineData?.tracks.length} 트랙');
      }
    } catch (e) {
      if (kDebugMode) {
        print('타임라인 로드 실패: $e');
      }
    }
  }

  // JSON 문자열에서 로드
  void loadFromJsonString(String jsonString) {
    try {
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      loadFromMap(jsonData);
    } catch (e) {
      if (kDebugMode) {
        print('타임라인 파싱 실패: $e');
      }
    }
  }

  // 타임라인 전체 업데이트
  void updateTimeline(Map<String, dynamic> timelineMap) {
    try {
      final currentPlayingState = _isPlaying;
      final currentTime = _currentTime;

      _timelineData = TimelineData.fromJson(timelineMap);

      // 재생 상태 유지
      if (currentPlayingState) {
        _currentTime = currentTime;
      }

      notifyListeners();
      if (kDebugMode) {
        print('타임라인 업데이트됨');
      }
    } catch (e) {
      if (kDebugMode) {
        print('타임라인 업데이트 실패: $e');
      }
    }
  }

  // 프로젝트 업데이트
  void updateProjectInfo(String name, double duration){
    if (_timelineData == null) return;

    // 현재 시간이 새 duration을 초과하면 조정
    if (_currentTime > duration) {
      _currentTime = duration;
    }

    // TimelineData 업데이트
    _timelineData = TimelineData(
      duration: duration,
      // fps: fps,
      projectId: _timelineData!.projectId,
      tracks: _timelineData!.tracks,
      createdAt: _timelineData!.createdAt,
    );

    notifyListeners();

  }

  // 큐 추가
  void addCueToTrack(String trackId, Cue cue) {
    if (_timelineData == null) return;

    final trackIndex = _timelineData!.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex != -1) {
      final track = _timelineData!.tracks[trackIndex];
      final updatedCues = List<Cue>.from(track.cues)..add(cue);

      final updatedTrack = Track(
        id: track.id,
        name: track.name,
        room_id: track.room_id,
        cues: updatedCues,
      );

      final updatedTracks = List<Track>.from(_timelineData!.tracks);
      updatedTracks[trackIndex] = updatedTrack;

      _timelineData = TimelineData(
        duration: _timelineData!.duration,
        // fps: _timelineData!.fps,
        projectId: _timelineData!.projectId,
        // room_id: _timelineData!.room_id,
        tracks: updatedTracks,
        createdAt: _timelineData!.createdAt,
      );

      notifyListeners();
    }
  }

  // 큐 업데이트
  void updateCueInTrack(String trackId, String cueId, Cue updatedCue) {
    if (_timelineData == null) return;

    final trackIndex = _timelineData!.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex != -1) {
      final track = _timelineData!.tracks[trackIndex];
      final cueIndex = track.cues.indexWhere((c) => c.id == cueId);

      if (cueIndex != -1) {
        final updatedCues = List<Cue>.from(track.cues);
        updatedCues[cueIndex] = updatedCue;

        final updatedTrack = Track(
          id: track.id,
          name: track.name,
          room_id: track.room_id,
          cues: updatedCues,
        );

        final updatedTracks = List<Track>.from(_timelineData!.tracks);
        updatedTracks[trackIndex] = updatedTrack;

        _timelineData = TimelineData(
          duration: _timelineData!.duration,
          // fps: _timelineData!.fps,
          projectId: _timelineData!.projectId,
          // room_id: _timelineData!.room_id,
          tracks: updatedTracks,
          createdAt: _timelineData!.createdAt,
        );

        notifyListeners();
      }
    }
  }

  // 큐 삭제
  void deleteCueFromTrack(String trackId, String cueId) {
    if (_timelineData == null) return;

    final trackIndex = _timelineData!.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex != -1) {
      final track = _timelineData!.tracks[trackIndex];
      final updatedCues = track.cues.where((c) => c.id != cueId).toList();

      final updatedTrack = Track(
        id: track.id,
        name: track.name,
        room_id: track.room_id,
        cues: updatedCues,
      );

      final updatedTracks = List<Track>.from(_timelineData!.tracks);
      updatedTracks[trackIndex] = updatedTrack;

      _timelineData = TimelineData(
        duration: _timelineData!.duration,
        // fps: _timelineData!.fps,
        projectId: _timelineData!.projectId,
        // room_id: _timelineData!.room_id,
        tracks: updatedTracks,
        createdAt: _timelineData!.createdAt,
      );

      notifyListeners();
    }
  }

  // 트랙 추가
  void addTrack(Track track) {
    if (_timelineData == null) return;

    final updatedTracks = List<Track>.from(_timelineData!.tracks)..add(track);

    _timelineData = TimelineData(
      duration: _timelineData!.duration,
      // fps: _timelineData!.fps,
      projectId: _timelineData!.projectId,
      // room_id: _timelineData!.room_id,
      tracks: updatedTracks,
      createdAt: _timelineData!.createdAt,
    );

    notifyListeners();
  }

  // 트랙 업데이트
  void updateTrack(Track track) {
    if (_timelineData == null) return;

    final updatedTracks = List<Track>.from(_timelineData!.tracks);
    final trackIndex = _timelineData!.tracks.indexWhere((t) => t.id == track.id);

    if(trackIndex == -1) return;

    updatedTracks[trackIndex] = track;

    _timelineData = TimelineData(
      duration: _timelineData!.duration,
      // fps: _timelineData!.fps,
      projectId: _timelineData!.projectId,
      // room_id: _timelineData!.room_id,
      tracks: updatedTracks,
      createdAt: _timelineData!.createdAt,
    );

    notifyListeners();
  }

  // 큐 삭제
  void deleteTrack(String trackId) {
    if (_timelineData == null) return;

    final trackIndex = _timelineData!.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex != -1) {
      _timelineData!.tracks.removeAt(trackIndex);
      notifyListeners();
    }
  }

  // 재생/일시정지 토글
  void togglePlayback() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  // 재생
  void play() {
    if (_timelineData == null) return;

    _isPlaying = true;
    _timer = Timer.periodic(Duration(milliseconds: _frame_milliseconds), (timer) {
      _currentTime += _frame_milliseconds * 0.001 * _playbackSpeed;
      // print(_currentTime.toString());
      if (_currentTime >= _timelineData!.duration) {
        _currentTime = _timelineData!.duration;
        pause();
      }

      notifyListeners();
    });
    notifyListeners();
  }

  // 일시정지
  void pause() {
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  // 정지
  void stop() {
    pause();
    _currentTime = 0;
    notifyListeners();

    onStopCallback?.call();
  }

  // 특정 시간으로 이동
  void seekTo(double time) {
    if (_timelineData == null) return;
    // _currentTime = time.clamp(0, _timelineData!.duration);
    _currentTime = time;
    notifyListeners();
  }

  // 재생 속도 변경
  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    notifyListeners();
  }

  // 줌 레벨 변경
  void setZoom(double zoom) {
    _zoom = zoom.clamp(0.1, 10.0);
    notifyListeners();
  }

  // 현재 활성 큐 찾기
  List<Cue> getActiveCues() {
    if (_timelineData == null) return [];

    List<Cue> activeCues = [];
    for (var track in _timelineData!.tracks) {
      for (var cue in track.cues) {
        if (_currentTime >= cue.startTime && _currentTime <= cue.endTime) {
          activeCues.add(cue);
        }
      }
    }
    return activeCues;
  }

  // 타임라인 데이터를 Map으로 변환
  Map<String, dynamic>? toMap() {
    return _timelineData?.toJson();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}



