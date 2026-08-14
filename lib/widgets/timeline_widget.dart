import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:que_pilot_admin_01/utils/ColorUtils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../controllers/timeline_controller.dart';
import '../db/hive_service.dart';
import '../dialog/cue_delete_dialog.dart';
import '../dialog/cue_update_dialog.dart';
import '../dialog/track_delete_dialog.dart';
import '../dialog/track_update_dialog.dart';
import '../models/timeline_cue_model.dart';
import '../models/timeline_room_model.dart';
import '../models/timeline_track_model.dart';

class TimelineWidget extends StatefulWidget {
  final TimelineController controller;
  final void Function(double time)? sendPlay;
  final void Function()? sendStop;
  final void Function(double time)? sendPause;
  // final Function playFunction;
  // final Function pauseFunction;
  // final Function stopFunction;

  // ⭐ 추가: 큐 직접 조작 콜백 (서버 전송은 부모에서 처리)
  final void Function(String projectId, Track track, double startTime)?
      onCueCreateRequest;
  final void Function(String projectId, Track track)? onCueUpdateRequest;
  final void Function(String projectId, Track track)? onCueDeleteRequest;
  // 드래그로 이동 완료 시 (startTime 변경) — 서버 전송용
  final void Function(String projectId, Track track, {bool showSnackBar})?
      onCueMoved;
  // 트랙 편집
  final void Function(String projectId, Track track)? onTrackUpdateRequest;
  final void Function(String projectId, Track track)? onTrackDeleteRequest;
  // 트랙 추가 (빈 상태 클릭 시)
  final void Function()? onTrackAddRequest;
  // 복사/붙여넣기
  final void Function(String projectId, Track track)? onCuesPasteRequest;
  // 코멘트 표시 시점 (초)
  final double commentOffset;
  // 방 목록
  final List<Room>? roomsWithoutTrack;
  final List<Room>? roomsAll;
  // 재생/정지/일시정지 제어 권한 (일반 사용자는 false)
  final bool canControl;
  // 관리자 여부 — 일반 사용자는 프로젝트 전체 트랙(room_id==project_id) 편집 불가
  final bool isAdminUser;

  const TimelineWidget({
    Key? key,
    required this.controller,
    required this.sendPlay,
    required this.sendStop,
    required this.sendPause,
    this.onCueCreateRequest,
    this.onCueUpdateRequest,
    this.onCueDeleteRequest,
    this.onCueMoved,
    this.onTrackUpdateRequest,
    this.onTrackDeleteRequest,
    this.onTrackAddRequest,
    this.onCuesPasteRequest,
    this.commentOffset = 2.0,
    this.roomsWithoutTrack,
    this.roomsAll,
    this.canControl = true,
    this.isAdminUser = true,
  }) : super(key: key);

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget>
    with TickerProviderStateMixin {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _trackLabelsScrollController = ScrollController();
  final ScrollController _timelineContentScrollController = ScrollController();
  final ScrollController _trackIconsScrollController = ScrollController();
  bool _isSyncingScroll = false;
  final double trackHeight = 60.0;
  final double timelineHeaderHeight = 40.0;
  final double trackLabelWidth = 120.0; // 트랙 이름 표시 영역
  final double trackIconLabelWidth = 60.0; // 트랙 이름 표시 영역

  final double commentPanelHight_max = 360.0; // 코맨트 표시 영역
  final double commentPanelHight_min = 86.0; // 코맨트 표시 영역
  final HiveService hiveService = HiveService();

  bool _isCommentPanelExpanded = false; // 🎯 패널 확장 상태
  double _commentPanelHeight = 360.0; // 🎯 확장 시 조절된 높이 (드래그 리사이즈)
  bool _isResizingCommentPanel = false; // 🎯 드래그 중 애니메이션 off
  bool _scrollVerticalMode = false; // true=세로(↕), false=가로(↔)

  // late Ticker _ticker;
  // double _targetScrollPosition = 0.0;
  // double _lastUpdateTime = 0.0;

  static const double _minZoom = 0.1;
  static const double _maxZoom = 2.0;
  static const double _zoomStep = 0.1;

  // 단축키 포커스 관리
  final FocusNode _focusNode = FocusNode(debugLabel: 'TimelineZoomFocus');

  // 드래그 상태
  String? _draggingCueId;
  final ValueNotifier<double?> _draggingStartTime =
      ValueNotifier<double?>(null);

  // Ctrl 키 상태 (휠 줌 시 세로 스크롤 방지)
  bool _isCtrlDown = false;

  // ⭐ 멀티 셀렉트 상태
  final Set<String> _selectedCueIds = {};
  final Set<String> _hoveredCueIds = {}; // 마키 호버 중인 큐
  bool _isMarqueeDragging = false;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  Map<String, int> _multiDragStartTimes = {};
  bool _cueClickPending = false; // 큐 클릭 시 선택 해제 방지 플래그

  // 복사/붙여넣기 상태
  List<Cue> _clipboardCues = [];
  List<int> _clipboardTrackIndices = [];
  Offset? _lastMouseGlobalPosition;
  List<Map<String, dynamic>> _pendingPasteSelection = [];

  // 리사이즈 상태
  String? _resizingCueId;
  String? _resizeEdge; // 'left' | 'right'
  double _resizeBaseValue = 0;
  final ValueNotifier<double?> _resizeCurrentValue =
      ValueNotifier<double?>(null);
  bool _isResizingCue = false;

  // 트랙 순서 변경 드래그 상태
  bool _isDraggingTrack = false;
  int? _draggingTrackIndex;
  int? _dragTargetIndex;

  // 트랙 드래그 오버레이
  final GlobalKey _trackLabelsKey = GlobalKey();
  OverlayEntry? _trackDragOverlay;
  final ValueNotifier<Offset> _trackDragPosition = ValueNotifier(Offset.zero);
  AnimationController? _trackDropAnimController;
  Animation<Offset>? _trackDropAnimation;
  Offset _trackDragStartGlobal = Offset.zero;

  // ⭐ 타임라인 실제 너비 저장
  double _timelineActualWidth = 0.0;

  // 자동 스크롤 (드래그 시 가장자리)
  final GlobalKey _timelineAreaKey = GlobalKey();
  Timer? _autoScrollTimer;
  double _autoScrollDelta = 0.0;

  // 휠 스크롤 노치 누적/보정 (1노치 = 정확히 1초)
  double _wheelAccumulator = 0.0;
  double _detectedNotchDelta = 0.0;

  // 줌 쓰로틀
  Timer? _zoomThrottleTimer;
  double? _pendingZoomValue;

  OverlayEntry? _contextMenuEntry;

  bool _isDraggingCue = false;

  @override
  void initState() {
    super.initState();
    _isCommentPanelExpanded = hiveService.readCommentPanelExpanded();
    _commentPanelHeight = hiveService
        .readCommentPanelHeight()
        .clamp(commentPanelHight_min, commentPanelHight_max);
    widget.controller.addListener(_onTimelineUpdate);
    widget.controller.currentTimeNotifier.addListener(_onTimelineUpdate);
    widget.controller.onStopCallback = _scrollToStart;
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _zoomThrottleTimer?.cancel();
    _draggingStartTime.dispose();
    _resizeCurrentValue.dispose();
    _removeContextMenu();
    _removeTrackDragOverlay();
    _trackDragPosition.dispose();
    _focusNode.dispose();
    widget.controller.removeListener(_onTimelineUpdate);
    widget.controller.currentTimeNotifier.removeListener(_onTimelineUpdate);
    widget.controller.onStopCallback = null;
    _horizontalScrollController.dispose();
    _trackLabelsScrollController.dispose();
    _timelineContentScrollController.dispose();
    _trackIconsScrollController.dispose();

    super.dispose();
  }

  void _removeContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  void _setZoom(double value, {double? cursorLocalX}) {
    final oldZoom = widget.controller.zoom;
    final clamped = value.clamp(_minZoom, _maxZoom);

    double? cursorTime;
    if (cursorLocalX != null && _horizontalScrollController.hasClients) {
      final oldPPS = oldZoom * 50;
      cursorTime = (_horizontalScrollController.offset + cursorLocalX) / oldPPS;
    }

    _pendingZoomValue = clamped;
    if (_zoomThrottleTimer == null || !_zoomThrottleTimer!.isActive) {
      widget.controller.setZoom(clamped);
      _pendingZoomValue = null;
      _zoomThrottleTimer = Timer(const Duration(milliseconds: 30), () {
        if (_pendingZoomValue != null) {
          widget.controller.setZoom(_pendingZoomValue!);
          _pendingZoomValue = null;
        }
      });
    }

    if (cursorTime != null && _horizontalScrollController.hasClients) {
      final newPPS = clamped * 50;
      final newOffset = cursorTime * newPPS - cursorLocalX!;
      // ⭐ 왼쪽 기준점(오프셋)을 정수초로 스냅
      final snapped =
          (newOffset / newPPS).roundToDouble() * newPPS;
      _horizontalScrollController.jumpTo(snapped.clamp(
          0.0, _horizontalScrollController.position.maxScrollExtent));
    } else if (_horizontalScrollController.hasClients) {
      // ⭐ 커서 없는 줌(슬라이더/+/-): 오프셋을 정수초로 스냅
      final newPPS = clamped * 50;
      final snapped =
          (_horizontalScrollController.offset / newPPS).roundToDouble() *
              newPPS;
      _horizontalScrollController.jumpTo(snapped.clamp(
          0.0, _horizontalScrollController.position.maxScrollExtent));
    }
  }

  void _applyZoomImmediate() {
    _zoomThrottleTimer?.cancel();
    _zoomThrottleTimer = null;
    if (_pendingZoomValue != null) {
      widget.controller.setZoom(_pendingZoomValue!);
      _pendingZoomValue = null;
    }
  }

  void _zoomIn() {
    _setZoom(widget.controller.zoom + _zoomStep);
  }

  void _zoomOut() {
    _setZoom(widget.controller.zoom - _zoomStep);
  }

  // ── 드래그 시 가장자리 자동 스크롤 ──
  static const double _autoScrollEdgeZone = 60.0;
  // ⭐ 줌 무관 타임라인 시간 기준 스크롤
  static const double _wheelNotchDelta = 120.0; // 보정 실패 시 폴백 노치 크기
  static const double _minNotchDelta = 40.0; // 이 이상의 델타면 '노치'로 간주
  static const double _scrollSecondsPerNotch = 1.0; // 휠 노치당 타임라인 1초
  // 기존 12px/tick(zoom 1.0, 50px/s 기준)을 시간 단위로 환산 → 0.24초/tick
  static const double _autoScrollMaxSecondsPerTick = 0.24;

  double _wheelScrollPixels(double scrollDeltaY) {
    final pixelsPerSecond = widget.controller.zoom * 50;
    final absD = scrollDeltaY.abs();

    // 첫 '노치급' 이벤트(>=40)로 실제 1노치 크기 보정 (예: 96 또는 120)
    if (absD >= _minNotchDelta && _detectedNotchDelta == 0) {
      _detectedNotchDelta = absD;
    }
    final notch = _detectedNotchDelta > 0
        ? _detectedNotchDelta
        : _wheelNotchDelta;

    // 델타 누적 후 정수 노치만큼만 1초씩 이동, 잔여는 다음 이벤트로 이월
    _wheelAccumulator += scrollDeltaY;
    final steps = (_wheelAccumulator / notch).truncate();
    if (steps != 0) _wheelAccumulator -= steps * notch;

    return steps * _scrollSecondsPerNotch * pixelsPerSecond;
  }

  void _updateAutoScroll(Offset globalPosition) {
    final renderBox =
        _timelineAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final widgetLeft = renderBox.localToGlobal(Offset.zero).dx;
    final widgetRight = widgetLeft + renderBox.size.width;
    final mouseX = globalPosition.dx;

    if (mouseX < widgetLeft + _autoScrollEdgeZone) {
      final ratio =
          ((widgetLeft + _autoScrollEdgeZone) - mouseX) / _autoScrollEdgeZone;
      _autoScrollDelta = -_autoScrollMaxSecondsPerTick *
          ratio.clamp(0.0, 1.0) *
          (widget.controller.zoom * 50);
    } else if (mouseX > widgetRight - _autoScrollEdgeZone) {
      final ratio =
          (mouseX - (widgetRight - _autoScrollEdgeZone)) / _autoScrollEdgeZone;
      _autoScrollDelta = _autoScrollMaxSecondsPerTick *
          ratio.clamp(0.0, 1.0) *
          (widget.controller.zoom * 50);
    } else {
      _autoScrollDelta = 0.0;
    }

    if (_autoScrollDelta != 0.0 &&
        (_autoScrollTimer == null || !_autoScrollTimer!.isActive)) {
      _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (_horizontalScrollController.hasClients && _autoScrollDelta != 0.0) {
          final oldOffset = _horizontalScrollController.offset;
          final newOffset = (oldOffset + _autoScrollDelta)
              .clamp(0.0, _horizontalScrollController.position.maxScrollExtent);
          _horizontalScrollController.jumpTo(newOffset);

          final actualDelta = newOffset - oldOffset;
          if (actualDelta != 0.0) {
            final pixelsPerSecond = widget.controller.zoom * 50;
            final timeDelta = actualDelta / pixelsPerSecond;
            if (_isDraggingCue && _draggingStartTime.value != null) {
              final duration = widget.controller.timelineData!.duration;
              _draggingStartTime.value =
                  (_draggingStartTime.value! + timeDelta).clamp(0.0, duration);
            } else if (_isResizingCue && _resizeCurrentValue.value != null) {
              final duration = widget.controller.timelineData!.duration;
              _resizeCurrentValue.value =
                  (_resizeCurrentValue.value! + timeDelta).clamp(0.0, duration);
            }
          }
        }
      });
    } else if (_autoScrollDelta == 0.0) {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDelta = 0.0;
  }

  // 재생 시 자동 스크롤 (playhead가 왼쪽 끝이므로 currentTime 위치로 스크롤)
  void _onTimelineUpdate() {
    if (_isDraggingCue || _isResizingCue) return;

    if (_pendingPasteSelection.isNotEmpty) {
      _selectPastedCues();
    }

    if (widget.controller.isPlaying && _horizontalScrollController.hasClients) {
      final zoom = widget.controller.zoom;
      final pixelsPerSecond = zoom * 50;
      final currentTimePosition =
          widget.controller.currentTime * pixelsPerSecond;

      // final screenWidth = MediaQuery.of(context).size.width - trackLabelWidth - trackIconLabelWidth - 880 - 200;

      if (_timelineActualWidth <= 0) return;

      final targetScroll = currentTimePosition;

      if (targetScroll >= 0 &&
          targetScroll < _horizontalScrollController.position.maxScrollExtent) {
        // _horizontalScrollController.animateTo(
        //   targetScroll,
        //   duration: const Duration(milliseconds: 1),
        //   curve: Curves.linear,
        // );
        _horizontalScrollController.jumpTo(targetScroll);
      }
    }
  }

  void _scrollToStart() {
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    }
  }

  // ── ⭐ 마키 셀렉션 ──
  Offset? _marqueePointerDownGlobal;
  int? _marqueePointerDownPointerId;

  void _startMarquee(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kPrimaryButton) return;
    if (HardwareKeyboard.instance.isShiftPressed) return;

    _marqueePointerDownGlobal = event.position;
    _marqueePointerDownPointerId = event.pointer;

    GestureBinding.instance.pointerRouter
        .addGlobalRoute(_onMarqueePointerEvent);
  }

  void _onMarqueePointerEvent(PointerEvent event) {
    if (event.pointer != _marqueePointerDownPointerId) return;

    if (event is PointerMoveEvent) {
      if (!_isMarqueeDragging) {
        final distance = (event.position - _marqueePointerDownGlobal!).distance;
        if (distance > 4) {
          // 글로벌을 로컬로 변환
          final localStart = _globalToLocal(_marqueePointerDownGlobal!);
          final localEnd = _globalToLocal(event.position);
          if (localStart != null && localEnd != null) {
            setState(() {
              _isMarqueeDragging = true;
              _marqueeStart = localStart;
              _marqueeEnd = localEnd;
              _hoveredCueIds.clear();
            });
          }
        }
      } else {
        final localEnd = _globalToLocal(event.position);
        if (localEnd != null) {
          setState(() {
            _marqueeEnd = localEnd;
            _updateMarqueeHoveredCues();
          });
        }
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      GestureBinding.instance.pointerRouter
          .removeGlobalRoute(_onMarqueePointerEvent);
      if (_isMarqueeDragging) {
        setState(() {
          _selectedCueIds.addAll(_hoveredCueIds);
          _isMarqueeDragging = false;
          _marqueeStart = null;
          _marqueeEnd = null;
          _hoveredCueIds.clear();
        });
      }
      _marqueePointerDownGlobal = null;
      _marqueePointerDownPointerId = null;
    }
  }

  Offset? _globalToLocal(Offset global) {
    final box =
        _timelineAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(global);
  }

  void _updateMarqueeHoveredCues() {
    if (_marqueeStart == null || _marqueeEnd == null) return;

    final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
    final zoom = widget.controller.zoom;
    final pixelsPerSecond = zoom * 50;
    final tracks = widget.controller.timelineData!.tracks;

    final horizontalScrollOffset =
        _horizontalScrollController.hasClients ? _horizontalScrollController.offset : 0.0;
    final verticalScrollOffset =
        _timelineContentScrollController.hasClients ? _timelineContentScrollController.offset : 0.0;

    final newHovered = <String>{};
    for (int ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      for (final cue in track.cues) {
        if (cue.id == null) continue;
        final cueLeft = cue.startTime * pixelsPerSecond - horizontalScrollOffset;
        final cueRight = cue.endTime * pixelsPerSecond - horizontalScrollOffset;
        final cueTop = timelineHeaderHeight + ti * trackHeight - verticalScrollOffset;
        final cueBottom = cueTop + trackHeight;

        final cueRect = Rect.fromLTRB(cueLeft, cueTop, cueRight, cueBottom);
        if (rect.overlaps(cueRect)) {
          newHovered.add(cue.id!);
        }
      }
    }
    _hoveredCueIds
      ..clear()
      ..addAll(newHovered);
  }

  // 일반 사용자는 권한 있는 방의 트랙만 편집 가능하고, 프로젝트 전체 트랙은 편집 불가
  bool _canEditTrack(Track track) {
    if (!widget.canControl) return false;
    if (!widget.isAdminUser) {
      final projectId = widget.controller.timelineData?.projectId;
      if (projectId != null && track.room_id == projectId) return false;
    }
    return true;
  }

  void _updateTracks(String projectId, track) {
    final currentRoom = widget.roomsAll?.where((r) => r.id == track.room_id).firstOrNull
        ?? (track.room_id == projectId
            ? Room(id: projectId, name: '프로젝트 트랙', createdAt: DateTime.now())
            : null);
    final emptyRooms = widget.roomsWithoutTrack ?? [];
    final effectiveRoomList = <Room>[];
    if (currentRoom != null) {
      effectiveRoomList.add(currentRoom);
    }
    for (final r in emptyRooms) {
      if (!effectiveRoomList.any((e) => e.id == r.id)) {
        effectiveRoomList.add(r);
      }
    }

    showDialog(
      context: context,
      builder: (context) => UpdateTrackDialog(
        projectId: projectId,
        roomList: effectiveRoomList.isNotEmpty ? effectiveRoomList : null,
        onTimelineUpdated: (updatedTrack) {
          widget.onTrackUpdateRequest?.call(projectId, updatedTrack);
        },

        roomId: track.room_id,
        cueList: track.cues,
        trackName: track.name,
        trackId: track.id,
      ),
    );
  }

  void _deleteTracks(String projectId, track) {
    showDialog(
      context: context,
      builder: (context) => DeleteTrackDialog(
        projectId: projectId,
        // roomList: null,
        onTrackDeleted: () {
          widget.onTrackDeleteRequest?.call(projectId, track);
        },
        roomId: track.room_id,
        trackName: track.name,
        trackId: track.id,
      ),
    );
  }

  void _updateCue(String projectId, Track track, Cue cue) async {
    final updated = await CueUpdateDialog.showForUpdate(
      context,
      cue: cue,
      existingCues: track.cues,
    );
    if (updated != null) {
      _trimOverlappingCues(track, updated.startTime, updated.duration,
          excludeId: updated.id);
      // 여기서 기존 onUpdate(updated) 콜백 호출
      final idx = track.cues.indexWhere((c) => c.id == updated.id);
      if (idx != -1) {
        track.cues[idx] = updated;
      }

      _syncCueColors(track, sourceCueId: updated.id);
      widget.onCueUpdateRequest?.call(projectId, track);
    }
  }

  /// 겹치는 기존 큐들을 자동으로 트림한다.
  /// 새 큐 [newStart, newStart+newDuration)와 겹치는 기존 큐를 잘라내거나 삭제한다.
  /// excludeId: 비교에서 제외할 큐 ID (단일 이동 시 자기 자신)
  /// excludeIds: 비교에서 제외할 큐 ID 집합 (멀티 이동 시 선택된 큐들)
  void _trimOverlappingCues(
    Track track,
    int newStart,
    int newDuration, {
    String? excludeId,
    Set<String>? excludeIds,
  }) {
    final newEnd = newStart + newDuration;
    final toRemove = <String>[];
    final toAdd = <Cue>[];

    for (int i = 0; i < track.cues.length; i++) {
      final existing = track.cues[i];
      final existingId = existing.id;
      if (existingId == null) continue;
      if (excludeId != null && existingId == excludeId) continue;
      if (excludeIds != null && excludeIds.contains(existingId)) continue;

      // 겹침 검사: [newStart, newEnd) vs [existing.startTime, existing.endTime)
      if (newStart >= existing.endTime || newEnd <= existing.startTime) continue;

      // Case 1: 새 큐가 기존 큐를 완전히 감싸면 → 기존 큐 삭제
      if (newStart <= existing.startTime && newEnd >= existing.endTime) {
        toRemove.add(existingId);
        continue;
      }

      // 신규: 새 큐가 기존 큐 내부에 완전히 들어옴 (양쪽 여유 공간) → 두 개로 분할
      if (newStart > existing.startTime && newEnd < existing.endTime) {
        final rightPiece = Cue(
          id: null,
          label: existing.label,
          comment: existing.comment,
          startTime: newEnd,
          duration: existing.endTime - newEnd,
          color: existing.color,
        );
        track.cues[i] = Cue(
          id: existingId,
          label: existing.label,
          comment: existing.comment,
          startTime: existing.startTime,
          duration: newStart - existing.startTime,
          color: existing.color,
        );
        toAdd.add(rightPiece);
        continue;
      }

      // Case 2: 새 큐의 끝이 기존 큐의 끝보다 앞에 있으면 → 기존 큐 시작을 newEnd로 트림
      if (newEnd < existing.endTime) {
        final trimmedDuration = existing.endTime - newEnd;
        track.cues[i] = Cue(
          id: existingId,
          label: existing.label,
          comment: existing.comment,
          startTime: newEnd,
          duration: trimmedDuration,
          color: existing.color,
        );
        continue;
      }

      // Case 3: 새 큐의 끝이 기존 큐의 끝 이상 → 기존 큐 끝을 newStart로 트림
      final trimmedDuration = newStart - existing.startTime;
      if (trimmedDuration > 0) {
        track.cues[i] = Cue(
          id: existingId,
          label: existing.label,
          comment: existing.comment,
          startTime: existing.startTime,
          duration: trimmedDuration,
          color: existing.color,
        );
      } else {
        // 트림 후 길이가 0 이하 → 삭제
        toRemove.add(existingId);
      }
    }

    // 역순으로 삭제 (인덱스 보존)
    for (int i = toRemove.length - 1; i >= 0; i--) {
      track.cues.removeWhere((c) => c.id == toRemove[i]);
    }

    // 분할로 생성된 조각 추가 (왼쪽 조각은 위 루프에서 교체, 오른쪽 조각 여기서 추가)
    track.cues.addAll(toAdd);
  }

  /// 큐 생성 시 앞쪽 겹침은 잘라내고, 뒤쪽 겹침은 뒤로 밀어내기.
  /// - 기존 큐가 새 큐보다 앞에서 시작하면 → 기존 큐 끝을 새 큐 시작으로 트림
  /// - 기존 큐가 새 큐 위치에서 겹치면 → 기존 큐 + 이후 큐들을 뒤로 밀어냄
  /// 밀어내기 후 duration을 초과하는 큐가 있으면 true 반환.
  bool _pushBackOnCreate(Track track, int newStart, int newDuration) {
    final newEnd = newStart + newDuration;
    final timelineDuration = widget.controller.timelineData!.duration.toInt();
    bool exceedsDuration = false;

    // 1단계: 앞쪽 겹침 트림 (기존 큐가 새 큐보다 앞에서 시작하는 경우)
    for (int i = track.cues.length - 1; i >= 0; i--) {
      final cue = track.cues[i];
      if (cue.startTime < newStart && cue.endTime > newStart) {
        final trimmedDuration = newStart - cue.startTime;
        if (trimmedDuration > 0) {
          track.cues[i] = Cue(
            id: cue.id,
            label: cue.label,
            comment: cue.comment,
            startTime: cue.startTime,
            duration: trimmedDuration,
            color: cue.color,
          );
        } else {
          track.cues.removeAt(i);
        }
      }
    }

    // 2단계: 뒤쪽 겹침 밀어내기 — 겹친만큼 ALL 후속 큐 밀기
    int pushAmount = 0;
    for (int i = 0; i < track.cues.length; i++) {
      final cue = track.cues[i];
      if (cue.startTime >= newStart && cue.startTime < newEnd) {
        pushAmount = newEnd - cue.startTime;
        break;
      }
    }

    if (pushAmount > 0) {
      for (int i = 0; i < track.cues.length; i++) {
        final cue = track.cues[i];
        if (cue.startTime >= newStart) {
          final newStartTime = cue.startTime + pushAmount;
          if (newStartTime + cue.duration > timelineDuration) {
            exceedsDuration = true;
          }
          track.cues[i] = Cue(
            id: cue.id,
            label: cue.label,
            comment: cue.comment,
            startTime: newStartTime,
            duration: cue.duration,
            color: cue.color,
          );
        }
      }
    }

    return exceedsDuration;
  }

  /// duration 초과 시 확인 다이얼로그
  Future<bool> _showDurationExceedDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title:
            const Text('타임라인 초과', style: TextStyle(color: Colors.white)),
        content: const Text(
          '밀어내기 후 일부 큐가 타임라인 범위를 초과합니다.\n그래도 진행하시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('진행', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ⭐ 멀티 셀렉트 헬퍼 메서드
  int _getCueStartTime(String cueId) {
    for (final track in widget.controller.timelineData!.tracks) {
      for (final cue in track.cues) {
        if (cue.id == cueId) return cue.startTime;
      }
    }
    return 0;
  }

  int _getCueDuration(String cueId) {
    for (final track in widget.controller.timelineData!.tracks) {
      for (final cue in track.cues) {
        if (cue.id == cueId) return cue.duration;
      }
    }
    return 0;
  }

  Track? _getCueTrack(String cueId) {
    for (final track in widget.controller.timelineData!.tracks) {
      for (final cue in track.cues) {
        if (cue.id == cueId) return track;
      }
    }
    return null;
  }

  void _createCue(String projectId, Track track, int startTime) async {
    final created = await CueUpdateDialog.showForCreate(
      context,
      startTime: startTime,
      existingCues: track.cues,
    );
    if (created != null) {
      final exceedsDuration =
          _pushBackOnCreate(track, created.startTime, created.duration);

      if (exceedsDuration) {
        final confirmed = await _showDurationExceedDialog();
        if (!confirmed) return;
      }

      track.cues.add(created);
      _syncCueColors(track);
      widget.onCueCreateRequest?.call(projectId, track, startTime.toDouble());
    }
  }

  void _deleteCue(String projectId, Track track, Cue cue) async {
    final deleted = await CueDeleteDialog.show(
      context,
      cue: cue,
    );
    if (deleted != null) {
      // 여기서 기존 onUpdate(updated) 콜백 호출
      final idx = track.cues.indexWhere((c) => c.id == deleted.id);
      if (idx != -1) {
        track.cues.removeAt(idx);
      }

      widget.onCueDeleteRequest?.call(projectId, track);
    }
  }

  void _handleMultiDelete() async {
    if (!widget.canControl) return;
    final selectedCues = <Cue>[];
    for (final track in widget.controller.timelineData!.tracks) {
      if (!_canEditTrack(track)) continue;
      for (final cue in track.cues) {
        if (cue.id != null && _selectedCueIds.contains(cue.id)) {
          selectedCues.add(cue);
        }
      }
    }
    if (selectedCues.isEmpty) return;

    final confirmed = await CueDeleteDialog.show(context, cues: selectedCues);
    if (confirmed == null) return;

    final projectId = widget.controller.timelineData!.projectId;
    for (final track in widget.controller.timelineData!.tracks) {
      if (!_canEditTrack(track)) continue;
      final beforeCount = track.cues.length;
      track.cues
          .removeWhere((c) => c.id != null && _selectedCueIds.contains(c.id));
      if (track.cues.length != beforeCount) {
        widget.onCueDeleteRequest?.call(projectId, track);
      }
    }
    setState(() {
      _selectedCueIds.clear();
    });
  }

  void _copySelectedCues() {
    _clipboardCues.clear();
    _clipboardTrackIndices.clear();
    final tracks = widget.controller.timelineData!.tracks;
    for (int t = 0; t < tracks.length; t++) {
      for (final cue in tracks[t].cues) {
        if (cue.id != null && _selectedCueIds.contains(cue.id)) {
          _clipboardCues.add(Cue(
            id: null,
            startTime: cue.startTime,
            duration: cue.duration,
            label: cue.label,
            comment: cue.comment,
            color: cue.color,
            data: cue.data,
          ));
          _clipboardTrackIndices.add(t);
        }
      }
    }
  }

  void _pasteCues() {
    if (!widget.canControl) return;
    if (_clipboardCues.isEmpty || _lastMouseGlobalPosition == null) return;
    if (widget.controller.timelineData == null) return;

    final box = _timelineAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final localPos = box.globalToLocal(_lastMouseGlobalPosition!);
    final pixelsPerSecond = widget.controller.zoom * 50.0;
    final cursorTime = (localPos.dx + _horizontalScrollController.offset) / pixelsPerSecond;

    final minStartTime = _clipboardCues
        .map((c) => c.startTime)
        .reduce((a, b) => a < b ? a : b);

    final projectId = widget.controller.timelineData!.projectId;
    final tracks = widget.controller.timelineData!.tracks;
    final affectedTracks = <String, Track>{};
    _pendingPasteSelection.clear();

    for (int i = 0; i < _clipboardCues.length; i++) {
      final copiedCue = _clipboardCues[i];
      final newStartTime = cursorTime.toInt() + (copiedCue.startTime - minStartTime);
      final newCue = Cue(
        id: null,
        startTime: newStartTime,
        duration: copiedCue.duration,
        label: copiedCue.label,
        comment: copiedCue.comment,
        color: copiedCue.color,
        data: copiedCue.data,
      );

      final trackIndex = _clipboardTrackIndices[i];
      if (trackIndex < tracks.length) {
        final targetTrack = tracks[trackIndex];
        if (!_canEditTrack(targetTrack)) continue;
        _pushBackOnCreate(targetTrack, newStartTime, newCue.duration);
        targetTrack.cues.add(newCue);
        _syncCueColors(targetTrack);
        affectedTracks[targetTrack.id] = targetTrack;
        _pendingPasteSelection.add({
          'trackId': targetTrack.id,
          'label': copiedCue.label,
          'startTime': newStartTime,
          'duration': copiedCue.duration,
        });
      }
    }

    _selectedCueIds.clear();

    for (final track in affectedTracks.values) {
      widget.onCueCreateRequest?.call(projectId, track, cursorTime);
    }

    setState(() {    });
  }

  void _selectPastedCues() {
    if (_pendingPasteSelection.isEmpty) return;
    if (widget.controller.timelineData == null) return;

    final toSelect = <String>{};
    final matched = <int>[];

    for (int i = 0; i < _pendingPasteSelection.length; i++) {
      final pending = _pendingPasteSelection[i];
      final trackId = pending['trackId'] as String;
      final label = pending['label'] as String;
      final startTime = pending['startTime'] as int;
      final duration = pending['duration'] as int;

      for (final track in widget.controller.timelineData!.tracks) {
        if (track.id != trackId) continue;
        for (final cue in track.cues) {
          if (cue.id != null &&
              cue.label == label &&
              cue.startTime == startTime &&
              cue.duration == duration) {
            toSelect.add(cue.id!);
            matched.add(i);
          }
        }
      }
    }

    for (int i = matched.length - 1; i >= 0; i--) {
      _pendingPasteSelection.removeAt(matched[i]);
    }

    setState(() {
      _selectedCueIds.addAll(toSelect);
    });
  }

  void _syncCueColors(Track track, {String? sourceCueId}) {
    final colorMap = <String, String>{};
    for (final cue in track.cues) {
      if (cue.label.isNotEmpty) {
        colorMap[cue.label] = cue.color;
      }
    }
    if (sourceCueId != null) {
      for (final cue in track.cues) {
        if (cue.id == sourceCueId && cue.label.isNotEmpty) {
          colorMap[cue.label] = cue.color;
          break;
        }
      }
    }
    for (int i = 0; i < track.cues.length; i++) {
      final syncColor = colorMap[track.cues[i].label];
      if (syncColor != null && track.cues[i].color != syncColor) {
        track.cues[i] = Cue(
          id: track.cues[i].id,
          startTime: track.cues[i].startTime,
          duration: track.cues[i].duration,
          label: track.cues[i].label,
          comment: track.cues[i].comment,
          color: syncColor,
          data: track.cues[i].data,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 빈 영역도 탭이 잡히도록
      behavior: HitTestBehavior.translucent,
      // ⭐ 위젯 영역을 탭하면 포커스 다시 획득 + 선택 해제
      onTap: () {
        _focusNode.requestFocus();
        if (!_cueClickPending) {
          setState(() {
            _selectedCueIds.clear();
          });
        }
        _cueClickPending = false;
      },
      child: Focus(
        focusNode: _focusNode, // ⭐ autofocus 대신 명시적 node 사용
        autofocus: true, // 처음 한 번 자동 포커스 (선택)
        onKeyEvent: (node, event) {
          // Ctrl 키 상태 추적
          if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
              event.logicalKey == LogicalKeyboardKey.controlRight) {
            final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
            if (_isCtrlDown != isDown) {
              setState(() {
                _isCtrlDown = isDown;
              });
            }
          }

          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }

          final key = event.logicalKey;

          if (key == LogicalKeyboardKey.equal ||
              key == LogicalKeyboardKey.add ||
              key == LogicalKeyboardKey.numpadAdd) {
            _zoomIn();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.numpadSubtract) {
            _zoomOut();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit0 ||
              key == LogicalKeyboardKey.numpad0) {
            _setZoom(1.0);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape) {
            setState(() {
              _selectedCueIds.clear();
            });
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.delete) {
            if (_selectedCueIds.isNotEmpty && event is KeyDownEvent) {
              _handleMultiDelete();
              return KeyEventResult.handled;
            }
          }
          // Ctrl+C: 복사
          if (HardwareKeyboard.instance.isControlPressed &&
              key == LogicalKeyboardKey.keyC &&
              event is KeyDownEvent) {
            if (_selectedCueIds.isNotEmpty) {
              _copySelectedCues();
            }
            return KeyEventResult.handled;
          }
          // Ctrl+V: 붙여넣기
          if (HardwareKeyboard.instance.isControlPressed &&
              key == LogicalKeyboardKey.keyV &&
              event is KeyDownEvent) {
            if (_clipboardCues.isNotEmpty && _lastMouseGlobalPosition != null) {
              _pasteCues();
            }
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, child) {
            if (widget.controller.timelineData == null ||
                widget.controller.timelineData!.tracks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '타임라인이 없습니다',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    if (widget.canControl)
                      IconButton(
                        onPressed: () => widget.onTrackAddRequest?.call(),
                        icon: Icon(Icons.add,
                            size: 32, color: Colors.blue.shade300),
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.all(12),
                          backgroundColor: Colors.blue.withValues(alpha: 0.15),
                          shape: CircleBorder(),
                        ),
                        tooltip: '타임라인 추가',
                      ),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    _buildControlPanel(),
                    Expanded(child: _buildTimelineView()),
                    _buildCommentPanel(constraints.maxHeight),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      color: Colors.grey[850],
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildTimePanel(),
                    if (widget.canControl) _buildControlPlay(),
                    const Spacer(),
                    _buildControlZoom(),
                    const Spacer(),
                    _buildScrollDirectionToggle(),
                  ],
                ),
                // Row(
                //   children: [
                //     _buildControlZoom(),
                //     const Spacer(),
                //     _buildScrollDirectionToggle(),
                //   ],
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: widget.controller.currentTimeNotifier,
            builder: (context, value, child) {
              return Text(
                _formatTime(value),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
          Text(
            ' / ${_formatTime(widget.controller.timelineData!.duration)}',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              widget.controller.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              if (widget.controller.isPlaying) {
                print("btnPause");
                widget.sendPause?.call(widget.controller.currentTime);
              } else {
                print("btnPlay");
                final startTime = _getPlayheadVisualTime();
                widget.controller.seekTo(startTime);
                widget.sendPlay?.call(startTime);
              }
            },
            tooltip: widget.controller.isPlaying ? '일시정지' : '재생',
          ),
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.white, size: 28),
            onPressed: () {
              widget.sendStop?.call();
              if (_horizontalScrollController.hasClients) {
                _horizontalScrollController.animateTo(0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut);
              }
            },
            tooltip: '정지',
          ),
        ],
      ),
    );
  }

  Widget _buildControlZoom() {
    final zoom = widget.controller.zoom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Zoom:', style: TextStyle(color: Colors.white)),
          const SizedBox(width: 8),

          // 축소 버튼
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white, size: 20),
            // 최소값에서는 비활성화
            onPressed: zoom > _minZoom ? _zoomOut : null,
            tooltip: '축소 (Ctrl -)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          SizedBox(
            width: 150,
            child: Slider(
              value: zoom.clamp(_minZoom, _maxZoom),
              min: _minZoom,
              max: _maxZoom,
              onChanged: (value) => _setZoom(value),
              onChangeEnd: (value) => _applyZoomImmediate(),
            ),
          ),

          // 확대 버튼
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 20),
            onPressed: zoom < _maxZoom ? _zoomIn : null,
            tooltip: '확대 (Ctrl +)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          const SizedBox(width: 8),

          // 현재 배율 표시
          SizedBox(
            width: 48,
            child: Text(
              '${zoom.toStringAsFixed(1)}x',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollDirectionToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // const Text('스크롤:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 4),
          // _scrollVerticalMode ?
          IconButton(
            icon: Icon(_scrollVerticalMode ? Icons.swap_vert : Icons.swap_horiz,
                color: Colors.blue, size: 20),
            onPressed: () => setState(() => _scrollVerticalMode
                ? {_scrollVerticalMode = false}
                : {_scrollVerticalMode = true}),
            tooltip: _scrollVerticalMode ? '세로 스크롤 (↕)' : '가로 스크롤 (↔)',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          )
          // :
          // IconButton(
          //   icon: const Icon(Icons.swap_horiz, color: Colors.blue, size: 20),
          //   onPressed: () => setState(() => _scrollVerticalMode = true),
          //   tooltip: '가로 스크롤 (↔)',
          //   padding: EdgeInsets.zero,
          //   constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          // ),
        ],
      ),
    );
  }

  // 🎯 현재 재생 시간에 활성화된 큐들을 찾는 메서드
  List<Map<String, dynamic>> _getActiveCues() {
    if (widget.controller.timelineData == null) return [];

    final currentTime = widget.controller.currentTime;
    final activeCues = <Map<String, dynamic>>[];

    if (widget.controller.timelineData!.tracks.isEmpty) {
      return [];
    }

    final commentOffset = widget.commentOffset; // 코멘트를 설정값만큼 먼저 표시
    for (var track in widget.controller.timelineData!.tracks) {
      for (var cue in track.cues) {
        if (currentTime >= cue.startTime - commentOffset &&
            currentTime <= cue.endTime) {
          activeCues.add({
            'track': track,
            'cue': cue,
          });
        }
      }
    }

    return activeCues;
  }

  Widget _buildCommentPanel(double availableHeight) {
    final double maxResizeHeight = (availableHeight - 120) < commentPanelHight_min
        ? commentPanelHight_min
        : (availableHeight - 120);
    final double panelHeight = _isCommentPanelExpanded
        ? _commentPanelHeight.clamp(commentPanelHight_min, maxResizeHeight)
        : commentPanelHight_min;
    final bool isClamping =
        _isCommentPanelExpanded && _commentPanelHeight > maxResizeHeight;

    return ValueListenableBuilder<double>(
      valueListenable: widget.controller.currentTimeNotifier,
      builder: (context, currentTime, child) {
        final activeCues = _getActiveCues();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎯 확장 상태에서만 리사이즈 핸들 (회색줄 바깥, 축소 시 미표시)
            if (_isCommentPanelExpanded)
              _buildCommentPanelResizeHandle(maxResizeHeight),
            AnimatedContainer(
              duration: _isResizingCommentPanel || isClamping
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: panelHeight,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                border: Border(
                  top: BorderSide(color: Colors.grey[700]!, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더 (확장 버튼 포함)
                  Row(
                children: [
                  // const Icon(
                  //   Icons.comment,
                  //   color: Colors.blue,
                  //   size: 20,
                  // ),
                  // const SizedBox(width: 8),
                  const Text(
                    'Comments',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // 활성 큐 개수 표시
                  if (activeCues.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${activeCues.length}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // 현재 시간
                  Text(
                    _formatTime(currentTime),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 확장/축소 버튼
                  IconButton(
                    icon: Icon(
                      _isCommentPanelExpanded
                          ? Icons.expand_more
                          : Icons.expand_less,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCommentPanelExpanded = !_isCommentPanelExpanded;
                      });
                      hiveService.saveCommentPanelExpanded(_isCommentPanelExpanded);
                    },
                    tooltip: _isCommentPanelExpanded ? '축소' : '확장',
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 코멘트 목록
              Expanded(
                child: activeCues.isEmpty
                    ?
                    // Center(
                    //   child: Column(
                    //     mainAxisAlignment: MainAxisAlignment.center,
                    //     children: [
                    //       Icon(
                    //         Icons.comment_outlined,
                    //         size: 48,
                    //         color: Colors.grey[700],
                    //       ),
                    //       const SizedBox(height: 8),
                    //       Text(
                    //         'No active cues at this time',
                    //         style: TextStyle(
                    //           color: Colors.grey[600],
                    //           fontSize: 14,
                    //         ),
                    //       ),
                    //     ],
                    //   ),
                    // )
                    Container()
                    : ListView.builder(
                        itemCount: activeCues.length,
                        itemBuilder: (context, index) {
                          final item = activeCues[index];
                          final track = item['track'] as Track;
                          final cue = item['cue'] as Cue;

                          return _buildCommentItem(track, cue);
                        },
                      ),
              ),
            ],
          ),
        ),
          ],
        );
      },
    );
  }

  // 🎯 코멘트 패널 리사이즈 핸들 (확장 시에만 표시, 방 패널과 동일한 투명 그래브 존)
  Widget _buildCommentPanelResizeHandle(double maxResizeHeight) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          setState(() {
            _isResizingCommentPanel = true;
          });
        },
        onVerticalDragUpdate: (details) {
          setState(() {
            _commentPanelHeight = (_commentPanelHeight - details.delta.dy)
                .clamp(commentPanelHight_min, maxResizeHeight);
          });
        },
        onVerticalDragEnd: (_) {
          setState(() {
            _isResizingCommentPanel = false;
          });
          hiveService.saveCommentPanelHeight(_commentPanelHeight);
        },
        child: Container(
          height: 6,
          color: Colors.transparent,
        ),
      ),
    );
  }

  // 🎯 개별 코멘트 아이템
  Widget _buildCommentItem(Track track, Cue cue) {
    final color = ColorUtils.parseColor(cue.color);
    final hasComment = cue.comment != null && cue.comment!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 영역
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 트랙과 큐 정보
                Row(
                  children: [
                    // 색상 인디케이터
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 트랙 이름
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[900]?.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        track.name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 큐 라벨
                    Expanded(
                      child: Text(
                        cue.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 시간 정보 및 진행바
                Row(
                  children: [
                    Text(
                      _formatTime(cue.startTime.toDouble()),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // 진행바
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: ValueListenableBuilder<double>(
                          valueListenable:
                              widget.controller.currentTimeNotifier,
                          builder: (context, value, child) {
                            final p = ((value - cue.startTime) / cue.duration)
                                .clamp(0.0, 1.0);
                            return FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: p,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    Text(
                      _formatTime(cue.endTime.toDouble()),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 코멘트 내용
          if (hasComment)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                cue.comment!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.5,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'No comment available',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineView() {
    final duration = widget.controller.timelineData!.duration;
    final zoom = widget.controller.zoom;
    final timelineWidth = duration * zoom * 50;

    return Container(
      color: Colors.grey[900],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 중간: 트랙 레이블 영역 (고정)
          _buildTrackLabels(),

          // 오른쪽: 타임라인 콘텐츠 영역 (스크롤 가능)
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_timelineActualWidth != constraints.maxWidth) {
                  setState(() {
                    _timelineActualWidth = constraints.maxWidth;
                  });
                }
              });
              return Listener(
                key: _timelineAreaKey,
                onPointerHover: (event) {
                  _lastMouseGlobalPosition = event.position;
                },
                onPointerMove: (event) {
                  _lastMouseGlobalPosition = event.position;
                },
                onPointerDown: (event) {
                  _lastMouseGlobalPosition = event.position;
                },
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    if (HardwareKeyboard.instance.isControlPressed) {
                      final delta =
                          event.scrollDelta.dy > 0 ? -_zoomStep : _zoomStep;
                      _setZoom(widget.controller.zoom + delta,
                          cursorLocalX: event.localPosition.dx);
                    } else if (!widget.controller.isPlaying &&
                        !_scrollVerticalMode) {
                      final newOffset = (_horizontalScrollController.offset +
                              _wheelScrollPixels(event.scrollDelta.dy))
                          .clamp(
                              0.0,
                              _horizontalScrollController
                                  .position.maxScrollExtent);
                      _horizontalScrollController.jumpTo(newOffset);
                    }
                  }
                },
                child: Stack(
                  children: [
                    //마우스 스크롤 지원 (가로: Listener가 처리)
                    ScrollbarTheme(
                      data: ScrollbarThemeData(
                        thumbColor: WidgetStateProperty.all(
                            Colors.grey.shade300.withAlpha(70)),
                        thickness: WidgetStateProperty.all(8),
                        trackVisibility: WidgetStateProperty.all(true),
                      ),
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        trackVisibility: true,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.trackpad,
                          }),
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: _isDraggingCue || _isResizingCue
                                ? const NeverScrollableScrollPhysics()
                                : const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              width: timelineWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RepaintBoundary(
                                      child: _buildTimeRuler(timelineWidth)),
                                  Expanded(
                                    child: NotificationListener<
                                        ScrollNotification>(
                                      onNotification: (_) {
                                        _syncScroll(
                                            _timelineContentScrollController);
                                        return false;
                                      },
                                      child: ScrollConfiguration(
                                        behavior:
                                            ScrollConfiguration.of(context),
                                        child: SingleChildScrollView(
                                          controller:
                                              _timelineContentScrollController,
                                          physics: (_scrollVerticalMode &&
                                                  !_isCtrlDown &&
                                                  !widget.controller.isPlaying)
                                              ? null
                                              : const NeverScrollableScrollPhysics(),
                                          child: Column(
                                            children: widget
                                                .controller.timelineData!.tracks
                                                .map(
                                                  (track) => _buildTrackContent(
                                                      track, timelineWidth),
                                                )
                                                .toList(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 중앙 고정 재생바
                    _buildFixedPlayhead(),

                    // ⭐ 마키 셀렉션 박스
                    if (_isMarqueeDragging &&
                        _marqueeStart != null &&
                        _marqueeEnd != null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _MarqueePainter(
                            start: _marqueeStart!,
                            end: _marqueeEnd!,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),

          // 오른쪽 : 해당 타임라인 아이콘 버튼
          _buildTrackIcons(),
        ],
      ),
    );
  }

  // ── 세로 스크롤 동기화 ──
  void _syncScroll(ScrollController source) {
    if (_isSyncingScroll) return;
    _isSyncingScroll = true;
    final offset = source.offset;
    if (source != _trackLabelsScrollController &&
        _trackLabelsScrollController.hasClients) {
      _trackLabelsScrollController.jumpTo(offset);
    }
    if (source != _timelineContentScrollController &&
        _timelineContentScrollController.hasClients) {
      _timelineContentScrollController.jumpTo(offset);
    }
    if (source != _trackIconsScrollController &&
        _trackIconsScrollController.hasClients) {
      _trackIconsScrollController.jumpTo(offset);
    }
    _isSyncingScroll = false;
  }

  // ── 트랙 순서 변경 드래그 핸들러 ──

  void _onTrackDragStart(int index, LongPressStartDetails details) {
    final tracks = widget.controller.timelineData?.tracks ?? [];
    if (index >= tracks.length) return;
    if (!_canEditTrack(tracks[index])) return;

    final RenderBox? renderBox =
        _trackLabelsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _trackDragStartGlobal = details.globalPosition;

    setState(() {
      _isDraggingTrack = true;
      _draggingTrackIndex = index;
      _dragTargetIndex = index;
    });

    _trackDragPosition.value = details.globalPosition;

    _trackDragOverlay = OverlayEntry(
      builder: (context) {
        return ValueListenableBuilder<Offset>(
          valueListenable: _trackDragPosition,
          builder: (context, pos, child) {
            return Positioned(
              left: pos.dx - trackLabelWidth / 2,
              top: pos.dy - trackHeight / 2,
              width: trackLabelWidth,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withAlpha(220),
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(120),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        widget.controller.timelineData!.tracks[index].name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_trackDragOverlay!);
  }

  void _onTrackDragMove(LongPressMoveUpdateDetails details) {
    if (!_isDraggingTrack || _draggingTrackIndex == null) return;

    final newPos = Offset(
      _trackDragStartGlobal.dx,
      _trackDragStartGlobal.dy + details.localOffsetFromOrigin.dy,
    );
    _trackDragPosition.value = newPos;

    // 타겟 인덱스 계산
    final RenderBox? renderBox =
        _trackLabelsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final areaTop = renderBox.localToGlobal(Offset.zero).dy;
    final scrollOffset = _trackLabelsScrollController.positions.isNotEmpty
        ? _trackLabelsScrollController.positions.first.pixels
        : 0.0;
    final relativeY = newPos.dy - areaTop - timelineHeaderHeight + scrollOffset;
    int newTarget = (relativeY / trackHeight).round();
    newTarget =
        newTarget.clamp(0, widget.controller.timelineData!.tracks.length - 1);

    if (newTarget != _dragTargetIndex) {
      setState(() {
        _dragTargetIndex = newTarget;
      });
    }
  }

  void _onTrackDragEnd(LongPressEndDetails details) {
    if (!_isDraggingTrack ||
        _draggingTrackIndex == null ||
        _dragTargetIndex == null) {
      _removeTrackDragOverlay();
      return;
    }

    if (_draggingTrackIndex == _dragTargetIndex) {
      _removeTrackDragOverlay();
      return;
    }

    // 드롭 애니메이션
    final RenderBox? renderBox =
        _trackLabelsKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      widget.controller.reorderTrack(_draggingTrackIndex!, _dragTargetIndex!);
      _removeTrackDragOverlay();
      return;
    }

    final areaTop = renderBox.localToGlobal(Offset.zero).dy;
    final scrollOffset = _trackLabelsScrollController.positions.isNotEmpty
        ? _trackLabelsScrollController.positions.first.pixels
        : 0.0;
    final targetScreenY = areaTop +
        timelineHeaderHeight +
        _dragTargetIndex! * trackHeight -
        scrollOffset +
        trackHeight / 2;

    final startPos = _trackDragPosition.value;
    final endPos = Offset(startPos.dx, targetScreenY);

    _trackDropAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _trackDropAnimation = Tween<Offset>(begin: startPos, end: endPos).animate(
      CurvedAnimation(parent: _trackDropAnimController!, curve: Curves.easeOut),
    );

    _trackDropAnimation!.addListener(() {
      _trackDragPosition.value = _trackDropAnimation!.value;
    });

    final fromIndex = _draggingTrackIndex!;
    final toIndex = _dragTargetIndex!;

    _trackDropAnimController!.forward().then((_) {
      widget.controller.reorderTrack(fromIndex, toIndex);
      _removeTrackDragOverlay();
    });
  }

  void _removeTrackDragOverlay() {
    _trackDragOverlay?.remove();
    _trackDragOverlay = null;
    _trackDropAnimController?.dispose();
    _trackDropAnimController = null;
    _trackDropAnimation = null;

    if (_isDraggingTrack) {
      setState(() {
        _isDraggingTrack = false;
        _draggingTrackIndex = null;
        _dragTargetIndex = null;
      });
    }
  }

  // 왼쪽 트랙 레이블 (고정)
  Widget _buildTrackLabels() {
    final tracks = widget.controller.timelineData!.tracks;

    return GestureDetector(
      key: _trackLabelsKey,
      onSecondaryTapUp: (details) {
        _removeContextMenu();
        _showAddTrackContextMenu(details.globalPosition);
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            if (HardwareKeyboard.instance.isControlPressed) {
              final delta = event.scrollDelta.dy > 0 ? -_zoomStep : _zoomStep;
              _setZoom(widget.controller.zoom + delta,
                  cursorLocalX: event.localPosition.dx);
            } else if (!widget.controller.isPlaying && !_scrollVerticalMode) {
              final newOffset =
                  (_horizontalScrollController.offset +
                      _wheelScrollPixels(event.scrollDelta.dy))
                      .clamp(0.0,
                          _horizontalScrollController.position.maxScrollExtent);
              _horizontalScrollController.jumpTo(newOffset);
            }
          }
        },
        child: Container(
          width: trackLabelWidth,
          color: Colors.grey[850],
          child: Column(
            children: [
              // 시간 눈금자 영역의 헤더
              Container(
                height: timelineHeaderHeight,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[700]!),
                    right: BorderSide(color: Colors.grey[700]!),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Tracks',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // 각 트랙 레이블 (세로 스크롤)
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _syncScroll(_trackLabelsScrollController);
                    return false;
                  },
                  child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: _trackLabelsScrollController,
                        physics: (_scrollVerticalMode &&
                            !_isCtrlDown &&
                            !widget.controller.isPlaying)
                            ? null
                            : const NeverScrollableScrollPhysics(),
                        child: Column(
                          children: List.generate(tracks.length, (index) {
                            final track = tracks[index];
                            final isDragging = _isDraggingTrack &&
                                _draggingTrackIndex == index;
                            final isTarget = _isDraggingTrack &&
                                _dragTargetIndex == index &&
                                _draggingTrackIndex != index;

                            return GestureDetector(
                              onSecondaryTapUp: (details) {
                                _removeContextMenu();
                                _showTrackLabelContextMenu(
                                    details.globalPosition, track);
                              },
                              onLongPressStart: (details) =>
                                  _onTrackDragStart(index, details),
                              onLongPressMoveUpdate: (details) =>
                                  _onTrackDragMove(details),
                              onLongPressEnd: (details) =>
                                  _onTrackDragEnd(details),
                              child: Container(
                                height: trackHeight,
                                decoration: BoxDecoration(
                                  color: isDragging
                                      ? Colors.blue.withAlpha(80)
                                      : isTarget
                                      ? Colors.blue.withAlpha(40)
                                      : Colors.grey[850],
                                  border: Border(
                                    bottom:
                                    BorderSide(color: Colors.grey[700]!),
                                    right: BorderSide(color: Colors.grey[700]!),
                                  ),
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: track.room_id == widget.controller.timelineData!.projectId
                                        ? Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                track.name,
                                                style: TextStyle(
                                                  color: isDragging
                                                      ? Colors.blue[200]
                                                      : Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                width: 40,
                                                height: 3,
                                                decoration: BoxDecoration(
                                                  color: Colors.orange[300],
                                                  borderRadius: BorderRadius.circular(2),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            track.name,
                                            style: TextStyle(
                                              color: isDragging
                                                  ? Colors.blue[200]
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 오른쪽 트랙 레이블 (고정)
  Widget _buildTrackIcons() {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (HardwareKeyboard.instance.isControlPressed) {
            final delta = event.scrollDelta.dy > 0 ? -_zoomStep : _zoomStep;
            _setZoom(widget.controller.zoom + delta,
                cursorLocalX: event.localPosition.dx);
          } else if (!widget.controller.isPlaying && !_scrollVerticalMode) {
            final newOffset = (_horizontalScrollController.offset +
                _wheelScrollPixels(event.scrollDelta.dy))
                .clamp(
                0.0, _horizontalScrollController.position.maxScrollExtent);
            _horizontalScrollController.jumpTo(newOffset);
          }
        }
      },


      child: Container(
        width: trackIconLabelWidth,
        color: Colors.grey[850],
        child: Column(
          children: [
          // 시간 눈금자 영역의 헤더
          Container(
          height: timelineHeaderHeight,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            border: Border(
              bottom: BorderSide(color: Colors.grey[700]!),
              left: BorderSide(color: Colors.grey[700]!),
            ),
          ),
        ),
        // 각 트랙 아이콘 (세로 스크롤)
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _syncScroll(_trackIconsScrollController);
              return false;
            },
            child: Theme(
              data: Theme.of(context).copyWith(
                scrollbarTheme: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(Colors.grey.shade300.withAlpha(70)),
                  thickness: WidgetStateProperty.all(8),
                  trackVisibility: WidgetStateProperty.all(true),
                ),
              ),
              child: SingleChildScrollView(
                controller: _trackIconsScrollController,
                physics: (_scrollVerticalMode &&
                    !_isCtrlDown &&
                    !widget.controller.isPlaying)
                    ? null
                    : const NeverScrollableScrollPhysics(),
                child: Column(
                  children: widget.controller.timelineData!.tracks
                      .map(
                        (track) => Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        border: Border(
                          bottom: BorderSide(color: Colors.grey[700]!),
                          left: BorderSide(color: Colors.grey[700]!),
                        ),
                      ),
                      child: Center(
                        child: Padding(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                          child: _canEditTrack(track)
                              ? PopupMenuButton(
                              icon: const Icon(Icons.menu,
                                  color: Colors.white),
                              color: Colors.grey[800],
                              tooltip: '타임라인 설정',
                              itemBuilder: (context) => <PopupMenuEntry>[
                                PopupMenuItem(
                                  onTap: () => _updateTracks(
                                      widget.controller.timelineData!
                                          .projectId,
                                      track),
                                  child: const ListTile(
                                    leading: const Icon(Icons.mode,
                                        color: Colors.white),
                                    title: Text(
                                      '타임라인 수정',
                                      style: TextStyle(
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  onTap: () => _deleteTracks(
                                      widget.controller.timelineData!
                                          .projectId,
                                      track),
                                  child: const ListTile(
                                    leading: const Icon(Icons.remove,
                                        color: Colors.white),
                                    title: Text(
                                      '타임라인 삭제',
                                      style: TextStyle(
                                          color: Colors.white),
                                    ),
                                  ),
                                ),
                              ])
                              : null,
                        ),
                      ),
                    ),
                  )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
          ],
        ),
      ),

    );
  }

  Widget _buildTimeRuler(double width) {
    return Container(
      height: timelineHeaderHeight,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TimeRulerPainter(
            duration: widget.controller.timelineData!.duration,
            zoom: widget.controller.zoom,
          ),
        ),
      ),
    );
  }

  Widget _buildTrackContent(Track track, double width) {
    final zoom = widget.controller.zoom;
    final pixelsPerSecond = zoom * 50;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton) {
          // 좌클릭: 큐 히트 검사
          final dx = event.localPosition.dx;
          final time = dx / pixelsPerSecond;
          bool hitCue = false;
          for (final cue in track.cues.reversed) {
            if (time >= cue.startTime && time <= cue.endTime) {
              hitCue = true;
              break;
            }
          }
          if (!hitCue) {
            // 빈 영역 클릭 → 선택 해제 + 마키 시작
            setState(() {
              _selectedCueIds.clear();
            });
            _startMarquee(event);
          }
          return;
        }
        if (event.buttons != kSecondaryButton) return;

        // 기존 메뉴가 있으면 닫고
        _removeContextMenu();

        final dx = event.localPosition.dx;
        final time = dx / pixelsPerSecond;

        Cue? hitCue;
        for (final cue in track.cues.reversed) {
          if (time >= cue.startTime && time <= cue.endTime) {
            hitCue = cue;
            break;
          }
        }

        if (hitCue != null) {
          _showCueContextMenu(event.position, track, hitCue);
        } else {
          final clampedTime =
              time.clamp(0.0, widget.controller.timelineData!.duration);
          _showTrackContextMenu(event.position, track, clampedTime);
        }
      },
      child: Container(
        height: trackHeight,
        width: width,
        decoration: BoxDecoration(
          color: Colors.grey[850]?.withValues(alpha: 0.5),
          border: Border(
            bottom: BorderSide(color: Colors.grey[700]!),
          ),
        ),
        child: Stack(
          children: track.cues.map((cue) => _buildCue(cue, track)).toList(),
        ),
      ),
    );
  }

  void _showTrackContextMenu(Offset globalPosition, Track track, double time) {
    if (!_canEditTrack(track)) return;
    _removeContextMenu();

    // 우클릭 위치 time이 포함된 트랙 내 빈 공간 계산
    int? gapStart;
    int? nextStart;
    for (final cue in track.cues) {
      if (cue.endTime <= time && (gapStart == null || cue.endTime > gapStart)) {
        gapStart = cue.endTime;
      }
      if (cue.startTime >= time &&
          (nextStart == null || cue.startTime < nextStart)) {
        nextStart = cue.startTime;
      }
    }
    final gapStartValue = gapStart ?? 0;
    final canDeleteGap = nextStart != null && nextStart > gapStartValue;
    final gapLength = canDeleteGap ? nextStart - gapStartValue : 0;

    _contextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // 바깥 클릭(좌/우 모두) 감지용 투명 전체 레이어 — barrier 역할이지만 우클릭도 통과 처리
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeContextMenu(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: _buildMenuContainer(
                children: [
                  _menuItem(
                    icon: Icons.add,
                    label: '큐 생성',
                    subtitle: '${time.toStringAsFixed(1)}s 위치',
                    onTap: () {
                      _removeContextMenu();
                      _createCue(widget.controller.timelineData!.projectId,
                          track, time.round());
                    },
                  ),
                  if (canDeleteGap)
                    _menuItem(
                      icon: Icons.remove_circle_outline,
                      label: '빈공간 삭제',
                      subtitle: '$gapLength 초 구간',
                      iconColor: Colors.orangeAccent,
                      labelColor: Colors.orangeAccent,
                      onTap: () {
                        _removeContextMenu();
                        _deleteGapOnTrack(
                            widget.controller.timelineData!.projectId, track,
                            gapStart: gapStartValue, nextStart: nextStart!);
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  /// 빈 공간 삭제: [gapStart, nextStart) 구간을 제거하고
  /// 해당 트랙에서 nextStart 이후의 큐들을 앞으로 당긴다.
  void _deleteGapOnTrack(String projectId, Track track,
      {required int gapStart, required int nextStart}) {
    final pullAmount = nextStart - gapStart;
    if (pullAmount <= 0) return;

    for (int i = 0; i < track.cues.length; i++) {
      final cue = track.cues[i];
      if (cue.startTime >= nextStart) {
        track.cues[i] = Cue(
          id: cue.id,
          label: cue.label,
          comment: cue.comment,
          startTime: cue.startTime - pullAmount,
          duration: cue.duration,
          color: cue.color,
        );
      }
    }

    widget.onCueMoved?.call(projectId, track);
  }

  void _showAddTrackContextMenu(Offset globalPosition) {
    if (!widget.canControl) return;
    _removeContextMenu();

    _contextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeContextMenu(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: _buildMenuContainer(
                children: [
                  _menuItem(
                    icon: Icons.add,
                    label: '타임라인 추가',
                    onTap: () {
                      _removeContextMenu();
                      widget.onTrackAddRequest?.call();
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  void _showTrackLabelContextMenu(Offset globalPosition, Track track) {
    if (!_canEditTrack(track)) return;
    _removeContextMenu();

    _contextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeContextMenu(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: _buildMenuContainer(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      track.name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  _menuItem(
                    icon: Icons.mode,
                    label: '타임라인 수정',
                    onTap: () {
                      _removeContextMenu();
                      _updateTracks(
                          widget.controller.timelineData!.projectId, track);
                    },
                  ),
                  _menuItem(
                    icon: Icons.delete,
                    label: '타임라인 삭제',
                    iconColor: Colors.redAccent,
                    labelColor: Colors.redAccent,
                    onTap: () {
                      _removeContextMenu();
                      _deleteTracks(
                          widget.controller.timelineData!.projectId, track);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  Widget _buildCue(Cue cue, Track track) {
    const edgeWidth = 8.0;
    final color = ColorUtils.parseColor(cue.color);
    final staticZoom = widget.controller.zoom;
    final staticPixelsPerSecond = staticZoom * 50;
    final staticLeft = cue.startTime * staticPixelsPerSecond;

    return Positioned(
      left: staticLeft,
      top: 8,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _draggingStartTime,
          _resizeCurrentValue,
          widget.controller.currentTimeNotifier
        ]),
        builder: (context, child) {
          final zoom = widget.controller.zoom;
          final pixelsPerSecond = zoom * 50;
          final origWidth = cue.duration * pixelsPerSecond;
          final isDragging = _isDraggingCue && _draggingCueId == cue.id;
          final isResizing = _isResizingCue && _resizingCueId == cue.id;
          final dragValue = _draggingStartTime.value;
          final resizeValue = _resizeCurrentValue.value;
          final isMove = isDragging && dragValue != null;
          final isResize = isResizing && resizeValue != null;
          final isActive = widget.controller.currentTime >= cue.startTime &&
              widget.controller.currentTime <= cue.endTime;
          final isSelected = _selectedCueIds.contains(cue.id);
          final isHovered = _hoveredCueIds.contains(cue.id);
          final isMultiDragging = _isDraggingCue &&
              _selectedCueIds.contains(cue.id) &&
              _draggingCueId != cue.id;

          double effectiveStartTime;
          double effectiveWidth;
          if (isMove) {
            effectiveStartTime = dragValue;
            effectiveWidth = origWidth;
          } else if (isMultiDragging &&
              _multiDragStartTimes.containsKey(cue.id)) {
            // 멀티 드래그: 기준 큐의 delta를 적용
            final baseOldTime = _multiDragStartTimes[_draggingCueId] ?? 0;
            final baseNewTime = dragValue ?? baseOldTime.toDouble();
            final delta = baseNewTime - baseOldTime;
            effectiveStartTime = (cue.startTime + delta).clamp(
                0.0, widget.controller.timelineData!.duration - cue.duration);
            effectiveWidth = origWidth;
          } else if (isResize && _resizeEdge == 'left') {
            effectiveStartTime = resizeValue;
            effectiveWidth =
                (cue.startTime + cue.duration - resizeValue) * pixelsPerSecond;
          } else if (isResize && _resizeEdge == 'right') {
            effectiveStartTime = cue.startTime.toDouble();
            effectiveWidth = resizeValue * pixelsPerSecond;
          } else {
            effectiveStartTime = cue.startTime.toDouble();
            effectiveWidth = origWidth;
          }
          final dynamicOffset =
              (effectiveStartTime - cue.startTime) * pixelsPerSecond;
          final cueWidth = effectiveWidth.clamp(20.0, double.infinity);

          return SizedBox(
            width: cueWidth,
            height: trackHeight - 16,
            child: Transform.translate(
              offset: Offset(dynamicOffset, 0),
              child: Stack(
                children: [
                  // body: tap + drag for move
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        if (event.kind != PointerDeviceKind.mouse) return;
                        if (event.buttons != kPrimaryButton) return;
                        _cueClickPending = true;
                        final isShiftPressed =
                            HardwareKeyboard.instance.isShiftPressed;
                        if (isShiftPressed) {
                          // Shift+클릭: 토글 선택
                          if (cue.id == null) return;
                          setState(() {
                            if (_selectedCueIds.contains(cue.id)) {
                              _selectedCueIds.remove(cue.id);
                            } else {
                              _selectedCueIds.add(cue.id!);
                            }
                          });
                        } else if (!_selectedCueIds.contains(cue.id)) {
                          // 일반 클릭: 선택 해제 후 해당 큐만 선택
                          setState(() {
                            _selectedCueIds.clear();
                            if (cue.id != null) _selectedCueIds.add(cue.id!);
                          });
                        }
                      },
                      child: GestureDetector(
                        onDoubleTap: () {
                          if (!_canEditTrack(track)) return;
                          if (!_isDraggingCue && !_isResizingCue) {
                            final pid =
                                widget.controller.timelineData!.projectId;
                            _updateCue(pid, track, cue);
                          }
                        },
                        onHorizontalDragStart: (details) {
                          if (!_canEditTrack(track)) return;
                          if (widget.controller.isPlaying) return;
                          // Shift가 눌려있으면 드래그 시작하지 않음 (토글용)
                          if (HardwareKeyboard.instance.isShiftPressed) return;

                          // 선택된 큐가 있으면 멀티 드래그
                          if (_selectedCueIds.contains(cue.id)) {
                            _multiDragStartTimes = {
                              for (final id in _selectedCueIds)
                                id: _getCueStartTime(id),
                            };
                          } else {
                            _multiDragStartTimes.clear();
                          }

                          _draggingStartTime.value = cue.startTime.toDouble();
                          setState(() {
                            _draggingCueId = cue.id;
                            _isDraggingCue = true;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          if (!_isDraggingCue || _draggingCueId != cue.id)
                            return;
                          final deltaSeconds =
                              details.delta.dx / pixelsPerSecond;
                          final duration =
                              widget.controller.timelineData!.duration;
                          final maxStart =
                              (duration - cue.duration).clamp(0.0, duration);
                          _draggingStartTime.value =
                              (_draggingStartTime.value! + deltaSeconds)
                                  .clamp(0.0, maxStart);
                          _updateAutoScroll(details.globalPosition);
                        },
                        onHorizontalDragEnd: (details) {
                          _cueClickPending = false;
                          _stopAutoScroll();
                          final newStart = _draggingStartTime.value;
                          setState(() {
                            _draggingCueId = null;
                            _isDraggingCue = false;
                          });
                          _draggingStartTime.value = null;

                          if (newStart == null) return;

                          final delta = newStart - cue.startTime;
                          if (delta.abs() < 0.5) return;

                          // 멀티 드래그: 모든 선택된 큐 이동
                          if (_multiDragStartTimes.isNotEmpty) {
                            // 모든 큐의 새 위치 계산
                            final Map<String, int> newPositions = {};
                            for (final id in _selectedCueIds) {
                              final oldStart = _multiDragStartTimes[id] ?? 0;
                              final newTime = (oldStart + delta)
                                  .clamp(
                                      0,
                                      widget.controller.timelineData!.duration -
                                          _getCueDuration(id))
                                  .toInt();
                              newPositions[id] = newTime;
                            }

                            // 위치 변경 여부 확인
                            bool anyMoved = false;
                            for (final entry in newPositions.entries) {
                              if (entry.value != _getCueStartTime(entry.key)) {
                                anyMoved = true;
                                break;
                              }
                            }
                            if (!anyMoved) {
                              _multiDragStartTimes.clear();
                              return;
                            }

                            // 겹치는 기존 큐들 트림
                            for (final entry in newPositions.entries) {
                              final targetTrack = _getCueTrack(entry.key);
                              if (targetTrack == null) continue;
                              final cueDur = _getCueDuration(entry.key);
                              _trimOverlappingCues(
                                  targetTrack, entry.value, cueDur,
                                  excludeIds: _selectedCueIds);
                            }

                            // 모든 큐 업데이트
                            for (final entry in newPositions.entries) {
                              final targetTrack = _getCueTrack(entry.key);
                              if (targetTrack == null) continue;
                              final idx = targetTrack.cues
                                  .indexWhere((c) => c.id == entry.key);
                              if (idx == -1) continue;
                              final old = targetTrack.cues[idx];
                              targetTrack.cues[idx] = Cue(
                                id: old.id,
                                label: old.label,
                                comment: old.comment,
                                startTime: entry.value,
                                duration: old.duration,
                                color: old.color,
                              );
                            }

                            // 영향받은 트랙별로 서버 전송 (첫 번째만 스낵바)
                            final pid =
                                widget.controller.timelineData!.projectId;
                            final affectedTrackIds = <String>{};
                            for (final entry in newPositions.entries) {
                              final t = _getCueTrack(entry.key);
                              if (t != null) affectedTrackIds.add(t.id);
                            }
                            bool firstTrack = true;
                            for (final t
                                in widget.controller.timelineData!.tracks) {
                              if (affectedTrackIds.contains(t.id)) {
                                widget.onCueMoved
                                    ?.call(pid, t, showSnackBar: firstTrack);
                                firstTrack = false;
                              }
                            }
                          } else {
                            // 단일 드래그 (기존 동작)
                            final updatedCue = Cue(
                              id: cue.id,
                              label: cue.label,
                              comment: cue.comment,
                              startTime: newStart.round(),
                              duration: cue.duration,
                              color: cue.color,
                            );
                            _trimOverlappingCues(
                                track, newStart.round(), cue.duration,
                                excludeId: cue.id);
                            final idx =
                                track.cues.indexWhere((c) => c.id == cue.id);
                            if (idx != -1) {
                              track.cues[idx] = updatedCue;
                            }
                            widget.onCueMoved?.call(
                                widget.controller.timelineData!.projectId,
                                track);
                          }
                        },
                        child: MouseRegion(
                          cursor: _canEditTrack(track)
                              ? (isDragging
                                  ? SystemMouseCursors.grabbing
                                  : SystemMouseCursors.grab)
                              : SystemMouseCursors.basic,
                          child: AnimatedScale(
                            scale: isDragging ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isActive
                                    ? color
                                    : isHovered
                                        ? color.withValues(alpha: 0.9)
                                        : isSelected
                                            ? color.withValues(alpha: 0.85)
                                            : color.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isDragging
                                      ? Colors.yellow
                                      : isMultiDragging
                                          ? Colors.orange
                                          : isHovered
                                              ? Colors.lightBlueAccent
                                              : isSelected
                                                  ? Colors.white
                                                  : isActive
                                                      ? Colors.white.withValues(
                                                          alpha: 0.4)
                                                      : color.withValues(
                                                          alpha: 0.5),
                                  width: isDragging
                                      ? 3
                                      : (isMultiDragging
                                          ? 3
                                          : (isHovered
                                              ? 2
                                              : (isSelected
                                                  ? 2
                                                  : (isActive ? 2 : 1)))),
                                ),
                                boxShadow: isDragging
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.7),
                                          blurRadius: 16,
                                          spreadRadius: 4,
                                        ),
                                        BoxShadow(
                                          color: Colors.yellow
                                              .withValues(alpha: 0.3),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : isMultiDragging
                                        ? [
                                            BoxShadow(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.5),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : isHovered
                                            ? [
                                                BoxShadow(
                                                  color: Colors.lightBlueAccent
                                                      .withValues(alpha: 0.5),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                ),
                                              ]
                                            : isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.25),
                                                      blurRadius: 8,
                                                      spreadRadius: 1,
                                                    ),
                                                  ]
                                                : isActive
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.3),
                                                          blurRadius: 8,
                                                          spreadRadius: 1,
                                                        ),
                                                      ]
                                                    : null,
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    cue.label,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // left edge resize handle (drag)
                  if (!widget.controller.isPlaying && _canEditTrack(track))
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: edgeWidth,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          onHorizontalDragStart: (details) {
                            if (!_canEditTrack(track)) return;
                            _resizeBaseValue = cue.startTime.toDouble();
                            _resizeCurrentValue.value = _resizeBaseValue;
                            setState(() {
                              _resizingCueId = cue.id;
                              _resizeEdge = 'left';
                              _isResizingCue = true;
                            });
                          },
                          onHorizontalDragUpdate: (details) {
                            if (_resizingCueId != cue.id ||
                                _resizeEdge != 'left') return;
                            final deltaSeconds =
                                details.delta.dx / pixelsPerSecond;
                            final maxStart = cue.endTime - 1;
                            _resizeCurrentValue.value =
                                (_resizeCurrentValue.value! + deltaSeconds)
                                    .clamp(0.0, maxStart.toDouble());
                            _updateAutoScroll(details.globalPosition);
                          },
                          onHorizontalDragEnd: (details) {
                            _cueClickPending = false;
                            _stopAutoScroll();
                            if (_resizingCueId != cue.id ||
                                _resizeEdge != 'left') return;
                            final newStart = _resizeCurrentValue.value;
                            setState(() {
                              _resizingCueId = null;
                              _resizeEdge = null;
                              _isResizingCue = false;
                            });
                            _resizeCurrentValue.value = null;
                            if (newStart != null &&
                                newStart.round() != cue.startTime) {
                              final newDuration =
                                  cue.endTime - newStart.round();
                              _trimOverlappingCues(
                                  track, newStart.round(), newDuration,
                                  excludeId: cue.id);
                              final updatedCue = Cue(
                                id: cue.id,
                                label: cue.label,
                                comment: cue.comment,
                                startTime: newStart.round(),
                                duration: newDuration,
                                color: cue.color,
                              );
                              final idx =
                                  track.cues.indexWhere((c) => c.id == cue.id);
                              if (idx != -1) {
                                track.cues[idx] = updatedCue;
                              }
                              widget.onCueMoved?.call(
                                  widget.controller.timelineData!.projectId,
                                  track);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isResizing && _resizeEdge == 'left'
                                  ? Colors.yellow.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              border: isResizing && _resizeEdge == 'left'
                                  ? Border(
                                      right: BorderSide(
                                          color: Colors.yellow, width: 3))
                                  : null,
                              boxShadow: isResizing && _resizeEdge == 'left'
                                  ? [
                                      BoxShadow(
                                          color: Colors.yellow
                                              .withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 2)
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // right edge resize handle (drag)
                  if (!widget.controller.isPlaying && _canEditTrack(track))
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: edgeWidth,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          onHorizontalDragStart: (details) {
                            if (!_canEditTrack(track)) return;
                            _resizeBaseValue = cue.duration.toDouble();
                            _resizeCurrentValue.value = _resizeBaseValue;
                            setState(() {
                              _resizingCueId = cue.id;
                              _resizeEdge = 'right';
                              _isResizingCue = true;
                            });
                          },
                          onHorizontalDragUpdate: (details) {
                            if (_resizingCueId != cue.id ||
                                _resizeEdge != 'right') return;
                            final deltaSeconds =
                                details.delta.dx / pixelsPerSecond;
                            final maxDuration =
                                widget.controller.timelineData!.duration -
                                    cue.startTime;
                            _resizeCurrentValue.value =
                                (_resizeCurrentValue.value! + deltaSeconds)
                                    .clamp(1.0, maxDuration.toDouble());
                            _updateAutoScroll(details.globalPosition);
                          },
                          onHorizontalDragEnd: (details) {
                            _cueClickPending = false;
                            _stopAutoScroll();
                            if (_resizingCueId != cue.id ||
                                _resizeEdge != 'right') return;
                            final newDuration = _resizeCurrentValue.value;
                            setState(() {
                              _resizingCueId = null;
                              _resizeEdge = null;
                              _isResizingCue = false;
                            });
                            _resizeCurrentValue.value = null;
                            if (newDuration != null &&
                                newDuration.round() != cue.duration) {
                              _trimOverlappingCues(
                                  track, cue.startTime, newDuration.round(),
                                  excludeId: cue.id);
                              final updatedCue = Cue(
                                id: cue.id,
                                label: cue.label,
                                comment: cue.comment,
                                startTime: cue.startTime,
                                duration: newDuration.round(),
                                color: cue.color,
                              );
                              final idx =
                                  track.cues.indexWhere((c) => c.id == cue.id);
                              if (idx != -1) {
                                track.cues[idx] = updatedCue;
                              }
                              widget.onCueMoved?.call(
                                  widget.controller.timelineData!.projectId,
                                  track);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isResizing && _resizeEdge == 'right'
                                  ? Colors.yellow.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              border: isResizing && _resizeEdge == 'right'
                                  ? Border(
                                      left: BorderSide(
                                          color: Colors.yellow, width: 3))
                                  : null,
                              boxShadow: isResizing && _resizeEdge == 'right'
                                  ? [
                                      BoxShadow(
                                          color: Colors.yellow
                                              .withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 2)
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCueContextMenu(Offset globalPosition, Track track, Cue cue) {
    if (!_canEditTrack(track)) return;
    _removeContextMenu();

    _contextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // ⭐ 바깥 클릭 감지용 전체 레이어 (큐 생성 메뉴와 동일하게 추가)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeContextMenu(),
              ),
            ),
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy,
              child: _buildMenuContainer(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      cue.label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  _menuItem(
                    icon: Icons.mode,
                    label: '큐 수정',
                    onTap: () {
                      _removeContextMenu();
                      // widget.onCueUpdateRequest?.call(track, cue);
                      _updateCue(widget.controller.timelineData!.projectId,
                          track, cue);
                    },
                  ),
                  _menuItem(
                    icon: Icons.delete,
                    label: '큐 삭제',
                    iconColor: Colors.redAccent,
                    labelColor: Colors.redAccent,
                    onTap: () {
                      _removeContextMenu();
                      // widget.onCueDeleteRequest?.call(track, cue);
                      _deleteCue(widget.controller.timelineData!.projectId,
                          track, cue);
                    },
                  ),
                  _menuItem(
                    icon: Icons.select_all,
                    label: '이후 모든 큐 선택',
                    onTap: () {
                      _removeContextMenu();
                      setState(() {
                        if (!HardwareKeyboard.instance.isShiftPressed) {
                          _selectedCueIds.clear();
                        }
                        for (final c in track.cues) {
                          if (c.id != null && c.startTime >= cue.startTime) {
                            _selectedCueIds.add(c.id!);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_contextMenuEntry!);
  }

  // 화면 왼쪽 끝에 고정된 재생바
  Widget _buildFixedPlayhead() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 2,
            color: Colors.red,
            child: Column(
              children: [
                Container(
                  width: 0,
                  height: 0,
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(width: 6, color: Colors.transparent),
                      right: BorderSide(width: 6, color: Colors.transparent),
                      bottom: BorderSide(width: 10, color: Colors.red),
                    ),
                  ),
                ),
                Expanded(child: Container()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 화면 왼쪽 끝 플레이헤드가 가리키는 시간 계산
  double _getPlayheadVisualTime() {
    if (!_horizontalScrollController.hasClients) {
      return widget.controller.currentTime;
    }

    final zoom = widget.controller.zoom;
    final pixelsPerSecond = zoom * 50;

    final leftEdgeTime = _horizontalScrollController.offset / pixelsPerSecond;
    return leftEdgeTime.clamp(0, widget.controller.timelineData?.duration ?? 0);
  }

  String _formatTime(double seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).floor().toString().padLeft(2, '0');
    final millis = ((seconds % 1) * 100).floor().toString().padLeft(2, '0');
    return '$minutes:$secs.$millis';
  }

  Widget _buildMenuContainer({required List<Widget> children}) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    String? subtitle,
    Color iconColor = Colors.white,
    Color labelColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TimeRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;

  TimeRulerPainter({required this.duration, required this.zoom});

  // ⭐ Paint 객체를 미리 생성 (루프 안에서 strokeWidth 재할당 안 함)
  static final Paint _majorPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 2;
  static final Paint _minorPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final pixelsPerSecond = zoom * 50;

    // 동적 interval: 라벨 간 최소 80px 간격 유지, 최소 2
    final minPixelSpacing = 80.0;
    int interval = (minPixelSpacing / pixelsPerSecond).ceil().clamp(2, 60);
    const snaps = [2, 5, 10, 15, 20, 30, 60];
    int best = snaps.first;
    for (final s in snaps) {
      if (s >= interval) {
        best = s;
        break;
      }
    }
    interval = best;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i <= duration; i += interval) {
      final x = i * pixelsPerSecond;

      canvas.drawLine(
        Offset(x, size.height - 15),
        Offset(x, size.height),
        _majorPaint,
      );
      textPainter.text = TextSpan(
        text: _formatTime(i.toDouble()),
        style: const TextStyle(color: Colors.white, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 3, 5));

      // 중간 minor tick
      final mid = i + interval ~/ 2;
      if (mid <= duration) {
        final midX = mid * pixelsPerSecond;
        canvas.drawLine(
          Offset(midX, size.height - 10),
          Offset(midX, size.height),
          _minorPaint,
        );
      }
    }
  }

  String _formatTime(double seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).floor().toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return oldDelegate.duration != duration || oldDelegate.zoom != zoom;
  }
}

class _MarqueePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _MarqueePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);

    // 반투명 배경
    final bgPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, bgPaint);

    // 점선 테두리
    final borderPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path()..addRect(rect);
    final dashPath = Path();
    const double dashWidth = 6;
    const double dashSpace = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final start = metric.getTangentForOffset(distance)!.position;
        distance += dashWidth;
        if (distance > metric.length) distance = metric.length;
        final end = metric.getTangentForOffset(distance)!.position;
        dashPath.moveTo(start.dx, start.dy);
        dashPath.lineTo(end.dx, end.dy);
        distance += dashSpace;
      }
    }
    canvas.drawPath(dashPath, borderPaint);
  }

  @override
  bool shouldRepaint(_MarqueePainter oldDelegate) {
    return oldDelegate.start != start || oldDelegate.end != end;
  }
}
