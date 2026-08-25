import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import '../db/hive_service.dart';
import '../models/timeline_cue_model.dart';
import '../models/timeline_model.dart';
import '../models/timeline_track_model.dart';

class TimelineController extends ChangeNotifier {
  final ValueNotifier<double> currentTimeNotifier = ValueNotifier<double>(0);

  TimelineData? _timelineData;
  double _currentTime = 0;
  bool _isPlaying = false;
  Timer? _timer;
  double _playbackSpeed = 1.0;
  late double _zoom;
  final _hiveService = HiveService();

  final int _frame_milliseconds = 16;

  // 정지시 호출되는 콜백
  VoidCallback? onStopCallback;

  TimelineController() {
    _zoom = _hiveService.readTimelineZoom();
  }

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
      currentTimeNotifier.value = 0;
      // Hive에 저장된 트랙 순서 적용
      applyTrackOrder();
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
      currentTimeNotifier.value = _currentTime;
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
        project_id: track.project_id,
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
          project_id: track.project_id,
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
        project_id: track.project_id,
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
      // Hive에서 해당 트랙 순서 제거 + 재인덱싱
      _removeAndReindexTrackOrder(trackId);
      notifyListeners();
    }
  }

  // Hive 기준으로 트랙 순서 적용
  void applyTrackOrder() {
    if (_timelineData == null) return;
    if (_timelineData!.tracks.isEmpty) return;

    final hiveService = HiveService();
    final savedOrders = hiveService.getAllTrackOrders();
    if (savedOrders.isEmpty) return;

    final tracks = List<Track>.from(_timelineData!.tracks);
    final indexed = <int, Track>{};
    final unindexed = <Track>[];

    for (var track in tracks) {
      final order = savedOrders[track.id];
      if (order != null && order >= 0 && order < tracks.length) {
        indexed[order] = track;
      } else {
        unindexed.add(track);
      }
    }

    // indexed 위치에 배치, 비어있는 자리는 unindexed에서 채움
    final result = <Track>[];
    int unindexedIdx = 0;
    for (int i = 0; i < tracks.length; i++) {
      if (indexed.containsKey(i)) {
        result.add(indexed[i]!);
      } else if (unindexedIdx < unindexed.length) {
        result.add(unindexed[unindexedIdx++]);
      }
    }

    // unindexed가 남으면 끝에 추가
    while (unindexedIdx < unindexed.length) {
      result.add(unindexed[unindexedIdx++]);
    }

    _timelineData = TimelineData(
      duration: _timelineData!.duration,
      projectId: _timelineData!.projectId,
      tracks: result,
      createdAt: _timelineData!.createdAt,
    );
  }

  // 트랙 순서 변경 (드래그 완료 시 호출)
  void reorderTrack(int oldIndex, int newIndex) {
    if (_timelineData == null) return;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _timelineData!.tracks.length) return;
    if (newIndex < 0 || newIndex >= _timelineData!.tracks.length) return;

    final tracks = List<Track>.from(_timelineData!.tracks);
    final track = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, track);

    _timelineData = TimelineData(
      duration: _timelineData!.duration,
      projectId: _timelineData!.projectId,
      tracks: tracks,
      createdAt: _timelineData!.createdAt,
    );

    // 새 순서를 Hive에 저장
    _saveAllTrackOrders();
    notifyListeners();
  }

  // 현재 트랙 순서를 Hive에 저장
  void _saveAllTrackOrders() {
    if (_timelineData == null) return;
    final hiveService = HiveService();
    final orders = <String, int>{};
    for (int i = 0; i < _timelineData!.tracks.length; i++) {
      orders[_timelineData!.tracks[i].id] = i;
    }
    hiveService.saveTrackOrders(orders);
  }

  // Hive에서 트랙 순서 제거 후 재인덱싱
  void _removeAndReindexTrackOrder(String removedTrackId) {
    final hiveService = HiveService();
    hiveService.trackOrderRemove(removedTrackId);
    // 현재 리스트 기준으로 순서 재저장
    _saveAllTrackOrders();
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

    // 기존 타이머가 있으면 먼저 정리 (이중 타이머 방지)
    _timer?.cancel();
    _isPlaying = true;
    notifyListeners();
    _timer = Timer.periodic(Duration(milliseconds: _frame_milliseconds), (timer) {
      _currentTime += _frame_milliseconds * 0.001 * _playbackSpeed;
      if (_currentTime >= _timelineData!.duration) {
        _currentTime = _timelineData!.duration;
        pause();
        return;
      }

      currentTimeNotifier.value = _currentTime;
    });
  }

  // 일시정지
  void pause() {
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    currentTimeNotifier.value = _currentTime;
    notifyListeners();
  }

  // 정지
  void stop() {
    pause();
    _currentTime = 0;
    currentTimeNotifier.value = 0;
    notifyListeners();

    onStopCallback?.call();
  }

  // 특정 시간으로 이동
  void seekTo(double time) {
    if (_timelineData == null) return;
    _currentTime = time;
    currentTimeNotifier.value = time;
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
    _hiveService.saveTimelineZoom(_zoom);
    notifyListeners();
  }

  // 현재 활성 큐 찾기
  // List<Cue> getActiveCues() {
  //   if (_timelineData == null) return [];
  //
  //   List<Cue> activeCues = [];
  //   for (var track in _timelineData!.tracks) {
  //     for (var cue in track.cues) {
  //       if (_currentTime >= cue.startTime && _currentTime <= cue.endTime) {
  //         activeCues.add(cue);
  //       }
  //     }
  //   }
  //   return activeCues;
  // }

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



