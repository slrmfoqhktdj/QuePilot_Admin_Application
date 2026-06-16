import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:que_pilot_admin_01/utils/ColorUtils.dart';
import '../controllers/timeline_controller.dart';
import '../dialog/track_add_dialog.dart';
import '../dialog/track_delete_dialog.dart';
import '../dialog/track_update_dialog.dart';
import '../models/timeline_cue_model.dart';
import '../models/timeline_track_model.dart';

class TimelineWidget extends StatefulWidget {
  final TimelineController controller;
  final VoidCallback sendPlay;
  final VoidCallback sendStop;
  final VoidCallback sendPause;
  // final Function playFunction;
  // final Function pauseFunction;
  // final Function stopFunction;

  const TimelineWidget({
    Key? key,
    required this.controller,
    required this.sendPlay,
    required this.sendStop,
    required this.sendPause,
    // required this.playFunction,
    // required this.pauseFunction,
    // required this.stopFunction,

  }) : super(key: key);

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> with TickerProviderStateMixin{
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final double trackHeight = 60.0;
  final double timelineHeaderHeight = 40.0;
  final double trackLabelWidth = 120.0; // 트랙 이름 표시 영역
  final double trackIconLabelWidth = 60.0; // 트랙 이름 표시 영역

  bool _isCommentPanelExpanded = false;  // 🎯 패널 확장 상태

  // late Ticker _ticker;
  // double _targetScrollPosition = 0.0;
  // double _lastUpdateTime = 0.0;


  // ⭐ 타임라인 실제 너비 저장
  double _timelineActualWidth = 0.0;


  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTimelineUpdate);
    widget.controller.onStopCallback = _scrollToStart; // 콜백 등록

    // _ticker = createTicker(_onTick);
    // _ticker.start();

  }

  @override
  void dispose() {
    // _ticker.dispose();

    widget.controller.removeListener(_onTimelineUpdate);
    widget.controller.onStopCallback = null;  //콜백 제거
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();

    super.dispose();
  }

  // 🎯 매 프레임 (약 1/60초)마다 실행
  // void _onTick(Duration elapsed) {
  //   if (widget.controller.isPlaying && _horizontalScrollController.hasClients) {
  //     final zoom = widget.controller.zoom;
  //     final pixelsPerSecond = zoom * 50;
  //     final currentTimePosition = widget.controller.currentTime * pixelsPerSecond;
  //
  //     // 화면 중앙을 기준으로 스크롤
  //     final screenWidth = MediaQuery.of(context).size.width - trackLabelWidth;
  //     final targetScroll = currentTimePosition - (screenWidth / 2);
  //
  //     if (targetScroll > 0 && targetScroll < _horizontalScrollController.position.maxScrollExtent) {
  //       // _horizontalScrollController.animateTo(
  //       //   targetScroll,
  //       //   duration: const Duration(milliseconds: 1),
  //       //   curve: Curves.linear,
  //       // );
  //       _horizontalScrollController.jumpTo(targetScroll);
  //     }
  //   }
  // }



  // 재생 시 자동 스크롤
  void _onTimelineUpdate() {
    if (widget.controller.isPlaying && _horizontalScrollController.hasClients) {
      final zoom = widget.controller.zoom;
      final pixelsPerSecond = zoom * 50;
      final currentTimePosition = widget.controller.currentTime * pixelsPerSecond;

      // 화면 중앙을 기준으로 스크롤
      // final screenWidth = MediaQuery.of(context).size.width - trackLabelWidth - trackIconLabelWidth - 880 - 200;

      if(_timelineActualWidth <= 0) return;

      final targetScroll = currentTimePosition - (_timelineActualWidth / 2) ;

      if (targetScroll > 0 && targetScroll < _horizontalScrollController.position.maxScrollExtent) {
        // _horizontalScrollController.animateTo(
        //   targetScroll,
        //   duration: const Duration(milliseconds: 1),
        //   curve: Curves.linear,
        // );
        _horizontalScrollController.jumpTo(targetScroll);
      }

    }

  }

  void _scrollToStart(){
    if(_horizontalScrollController.hasClients){
      _horizontalScrollController.animateTo(0, duration: const Duration(milliseconds: 100), curve: Curves.easeInOut,);
    }
  }

  void _updateTracks(String projectId, String trackId, String roomId, String name, List<Cue> cues){
    showDialog(
      context: context,
      builder: (context) => UpdateTrackDialog(
        projectId: projectId,
        // roomList: null,
        onTimelineUpdated: (data) {
          widget.controller.updateTrack(Track.fromJson(data));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('타임라인이 수정되었습니다')),
          );
        },
        roomId: roomId,
        cueList: cues,
        trackName: name,
        trackId: trackId,
      ),
    );
  }

  void _deleteTracks(String projectId,String roomId, String trackId, String trackName){
    showDialog(
      context: context,
      builder: (context) => DeleteTrackDialog(
        projectId: projectId,
        // roomList: null,
        onTrackDeleted: (success, trackId) {
          widget.controller.deleteTrack(trackId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('타임라인이 삭제되었습니다')),
          );
        },
        roomId: roomId,
        trackName: trackName,
        trackId: trackId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        if (widget.controller.timelineData == null || widget.controller.timelineData!.tracks.isEmpty) {
          return const Center(
            child: Text(
              '타임라인이 없습니다',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          );
        }

        return Column(
          children: [
            _buildControlPanel(),
            // _buildControlPanel2(),
            Expanded(
              child: _buildTimelineView(),
            ),

            _buildCommentPanel(),
          ],
        );
      },
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
                    _buildTimePanel(),_buildControlPlay(),
                    // Expanded(
                    //     child: _buildTimePanel()
                    // ),
                    //
                    // Expanded(
                    //     child: _buildControlPlay()
                    // ),
                    //
                    // Expanded(
                    //     child: _buildControlZoom()
                    // )

                  ],
                ),
                Row(
                  children: [
                    _buildControlZoom()
                  ],
                ),
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

          Text(
            _formatTime(widget.controller.currentTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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

          // IconButton(
          //     onPressed: () => {
          //       // socketService.sendPlay();
          //       widget.sendPlay.call()
          //     },
          //     icon: const Icon(Icons.play_arrow, color: Colors.white,)
          // ),
          // IconButton(
          //     onPressed: () => {
          //       //  socketService.sendPause()
          //       widget.sendPause.call()
          //     },
          //     icon: const Icon(Icons.pause, color: Colors.white,)
          // ),
          // IconButton(
          //     onPressed: () => {
          //       // socketService.sendStop()
          //       widget.sendStop.call()
          //     },
          //     icon: const Icon(Icons.stop, color: Colors.white,)
          // ),
          IconButton(
            icon: Icon(
              widget.controller.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 28,
            ),
            // onPressed: widget.controller.togglePlayback,
            onPressed: () => widget.controller.isPlaying ? widget.sendPause.call() : widget.sendPlay.call(),
            tooltip: widget.controller.isPlaying ? '일시정지' : '재생',
          ),
          IconButton(
            icon: const Icon(Icons.stop, color: Colors.white, size: 28),
            onPressed: () => widget.sendStop.call(),
            tooltip: '정지',
          ),
        ],
      ),
    );
  }


  Widget _buildControlZoom() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      color: Colors.grey[850],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Zoom:', style: TextStyle(color: Colors.white)),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Slider(
              value: widget.controller.zoom,
              min: 0.1,
              max: 5.0,
              onChanged: (value) => widget.controller.setZoom(value),
            ),
          ),
        ],
      ),
    );
  }


  // 🎯 현재 재생 시간에 활성화된 큐들을 찾는 메서드
  List<Map<String, dynamic>> _getActiveCues() {
    if (widget.controller.timelineData == null ) return [];

    final currentTime = widget.controller.currentTime;
    final activeCues = <Map<String, dynamic>>[];

    if(widget.controller.timelineData!.tracks.isEmpty){
      return [];
    }

    for (var track in widget.controller.timelineData!.tracks) {
      for (var cue in track.cues) {
        if (currentTime >= cue.startTime && currentTime <= cue.endTime) {
          activeCues.add({
            'track': track,
            'cue': cue,
          });
        }
      }
    }

    return activeCues;
  }

  // 짧은 시간 포맷 (초 단위만)
  String _formatTimeShort(double seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).floor().toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Widget _buildCommentPanel() {
    final activeCues = _getActiveCues();
    // print('activeCues = ${activeCues.isEmpty}');
    final panelHeight = _isCommentPanelExpanded ? 300.0 : 100.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
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
              const Icon(
                Icons.comment,
                color: Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                _formatTime(widget.controller.currentTime),
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
                },
                tooltip: _isCommentPanelExpanded ? '축소' : '확장',
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 코멘트 목록
          Expanded(
            child: activeCues.isEmpty ?
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
    );
  }

  // 🎯 개별 코멘트 아이템
  Widget _buildCommentItem(Track track, Cue cue) {
    final color = ColorUtils.parseColor(cue.color);
    final hasComment = cue.comment != null && cue.comment!.isNotEmpty;
    final progress = ((widget.controller.currentTime - cue.startTime) / cue.duration)
        .clamp(0.0, 1.0);

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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      _formatTimeShort(cue.startTime.toDouble()),
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
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),
                    Text(
                      _formatTimeShort(cue.endTime.toDouble()),
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
                  fontSize: 13,
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
        children: [
          // 왼쪽: 트랙 레이블 영역 (고정)
          _buildTrackLabels(),

          // 오른쪽: 타임라인 콘텐츠 영역 (스크롤 가능)
          Expanded(
            child: LayoutBuilder(
                builder: (context, constraints) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if(_timelineActualWidth != constraints.maxWidth) {
                      setState(() {
                        _timelineActualWidth = constraints.maxWidth;
                      });
                    }
                  });
                  return Stack(
                    children: [
                      //마우스 스크롤 지원
                      ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            }
                        ),
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SingleChildScrollView(
                            primary: false,
                            controller: _verticalScrollController,
                            child: SizedBox(
                              width: timelineWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTimeRuler(timelineWidth),
                                  ...widget.controller.timelineData!.tracks.map(
                                        (track) => _buildTrackContent(track, timelineWidth),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 중앙 고정 재생바
                      _buildFixedPlayhead(),
                    ],
                  );
                }),
          ),

          // 오른쪽 : 해당 타임라인 아이콘 버튼
          _buildTrackIcons(),


        ],
      ),
    );
  }

  // 왼쪽 트랙 레이블 (고정)
  Widget _buildTrackLabels() {
    return Container(
      width: trackLabelWidth,
      color: Colors.grey[850],
      child: SingleChildScrollView(
        controller: _verticalScrollController,
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
            // 각 트랙 레이블
            ...widget.controller.timelineData!.tracks.map(
                  (track) => Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[700]!),
                    right: BorderSide(color: Colors.grey[700]!),
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      track.name,
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


          ],
        ),
      ),
    );
  }

  // 오른쪽 트랙 레이블 (고정)
  Widget _buildTrackIcons() {
    return Container(
      width: trackIconLabelWidth,
      color: Colors.grey[850],
      child: SingleChildScrollView(
        controller: _verticalScrollController,
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
              // child: const Center(
              //   child: Text(
              //     'Tracks',
              //     style: TextStyle(
              //       color: Colors.white,
              //       fontWeight: FontWeight.bold,
              //     ),
              //   ),
              // ),
            ),
            // 각 트랙 레이블
            ...widget.controller.timelineData!.tracks.map(
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child:
                    // IconButton(onPressed: () => _updateTracks(widget.controller.timelineData!.project_id,track.id,track.room_id,track.name, track.cues), icon: const Icon(Icons.settings, color: Colors.white))
                    PopupMenuButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        color: Colors.grey[800],
                        tooltip: '타임라인 설정',
                        itemBuilder: (context) => <PopupMenuEntry> [
                          PopupMenuItem(
                            onTap: () => _updateTracks(widget.controller.timelineData!.projectId,track.id,track.room_id,track.name, track.cues),
                            child: const ListTile(
                              leading:const Icon(Icons.mode, color: Colors.white),
                              title: Text('타임라인 수정',style: TextStyle(color: Colors.white),),
                            ),
                          ),
                          PopupMenuItem(
                            onTap: () => _deleteTracks(widget.controller.timelineData!.projectId,track.room_id,track.id,track.name),
                            child: const ListTile(
                              leading:const Icon(Icons.remove, color: Colors.white),
                              title: Text('타임라인 삭제',style: TextStyle(color: Colors.white),),
                            ),
                          ),
                        ]
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
        border: Border(
          bottom: BorderSide(color: Colors.grey[700]!),
        ),
      ),
      child: CustomPaint(
        painter: TimeRulerPainter(
          duration: widget.controller.timelineData!.duration,
          zoom: widget.controller.zoom,
        ),
      ),
    );
  }

  Widget _buildTrackContent(Track track, double width) {
    return Container(
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
    );
  }

  Widget _buildCue(Cue cue, Track track) {
    final zoom = widget.controller.zoom;
    final pixelsPerSecond = zoom * 50;

    final left = cue.startTime * pixelsPerSecond;
    final width = cue.duration * pixelsPerSecond;

    final color = ColorUtils.parseColor(cue.color);
    final isActive = widget.controller.currentTime >= cue.startTime &&
        widget.controller.currentTime <= cue.endTime;

    return Positioned(
      left: left,
      top: 8,
      child: GestureDetector(
        onTap: () => widget.controller.seekTo(cue.startTime.toDouble()),
        child: Container(
          width: width.clamp(20.0, double.infinity),
          height: trackHeight - 16,
          decoration: BoxDecoration(
            color: isActive ? color : color.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? Colors.white : color.withValues(alpha: 0.5),
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                cue.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 화면 중앙에 고정된 재생바
  Widget _buildFixedPlayhead() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
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

  String _formatTime(double seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).floor().toString().padLeft(2, '0');
    final millis = ((seconds % 1) * 100).floor().toString().padLeft(2, '0');
    return '$minutes:$secs.$millis';
  }

}

class TimeRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;

  TimeRulerPainter({required this.duration, required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    final pixelsPerSecond = zoom * 50;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // 눈금 간격 동적 조정
    int interval = 1;
    if (zoom < 0.5) {
      interval = 10;
    } else if (zoom < 1.0) {
      interval = 5;
    }

    for (int i = 0; i <= duration; i++) {
      final x = i * pixelsPerSecond;

      // 주요 눈금
      if (i % interval == 0) {
        canvas.drawLine(
          Offset(x, size.height - 15),
          Offset(x, size.height),
          paint..strokeWidth = 2,
        );

        textPainter.text = TextSpan(
          text: _formatTime(i.toDouble()),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 3, 5));
      } else if (i % (interval ~/ 2) == 0 && interval > 1) {
        // 중간 눈금
        canvas.drawLine(
          Offset(x, size.height - 10),
          Offset(x, size.height),
          paint..strokeWidth = 1,
        );
      } else {
        // 작은 눈금
        canvas.drawLine(
          Offset(x, size.height - 5),
          Offset(x, size.height),
          paint..strokeWidth = 1,
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
