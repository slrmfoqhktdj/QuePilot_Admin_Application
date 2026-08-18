import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:que_pilot_admin_01/dialog/room_add_dialog.dart';
import 'package:que_pilot_admin_01/widgets/room_slide_chat_widget.dart';
import '../controllers/timeline_controller.dart';
import '../db/hive_service.dart';
import '../dialog/message_whole_dialog.dart';
import '../dialog/project_add_dialog.dart';
import '../dialog/project_delete_dialog.dart';
import '../dialog/project_update_dialog.dart';
import '../dialog/room_delete_dialog.dart';
import '../dialog/room_update_dialog.dart';
import '../dialog/track_add_dialog.dart';
import '../models/timeline_list_model.dart';
import '../models/timeline_room_model.dart';
import '../models/timeline_track_model.dart';
import '../services/socket_service.dart';
import '../widgets/timeline_widget.dart';

class TimelineListScreen extends StatefulWidget {
  // final List<Map<String, dynamic>> joinedMembers;

  const TimelineListScreen({
    Key? key,
    // required this.joinedMembers,
  }) : super(key: key);

  @override
  State<TimelineListScreen> createState() => _TimelineListScreenState();
}

class _TimelineListScreenState extends State<TimelineListScreen> with TickerProviderStateMixin {
  final socketService = SocketService();
  final List<StreamSubscription> _subs = [];
  List<TimelineProject> projects = [];

  // final double _leftProjectListPanelWidth = 280;      // 왼쪽 프로젝트 리스트 칸 넓이
  double _roomPanelWidth = 600;                        // 방 패널(방목록+채팅) 폭 (드래그로 조절)
  final double _roomListWidth = 190;                  // 방 목록 폭 (고정)
  final double _minRoomPanelWidth = 480;              // 방 패널 최소 폭 (방목록 240 + 채팅 최소 240)
  final double _minTimelineWidth = 800;               // 타임라인(큐·트랙) 최소 폭
  double get _infoPanelWidth => _roomPanelWidth - _roomListWidth; // 방 정보 패널 폭

  bool _isRoomInfoPanelOpen = true; // 방 정보 패널 열림/닫힘

  int? _selectedProjectIndex;
  final hiveService = HiveService();

  int? _selectedRoomIndex;

  // List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  // 일반 사용자: 내가 권한(편집 가능)이 있는 방 ID 집합
  final Set<String> _myAuthRoomIds = {};

  bool _isReordering = false; //드래그 여부

  // 프로젝트 롱클릭 드래그 상태
  // final GlobalKey _projectListKey = GlobalKey();
  final GlobalKey _projectMenuKey = GlobalKey();
  bool _isDraggingProject = false;
  // int? _draggedProjectIndex;
  // int? _dragTargetProjectIndex;
  // Offset _dragProjectPosition = Offset.zero;
  final ValueNotifier<Offset> _dragProjectPositionNotifier = ValueNotifier(Offset.zero);
  AnimationController? _projectDropAnimController;
  Animation<Offset>? _dropAnim;
  VoidCallback? _dropAnimListener;
  OverlayEntry? _projectDragOverlay;

  bool _isProjectLoading = true;  //프로젝트 로딩
  bool _isRoomLoading = false;     // 방 로딩


  // ★ 추가: 요청 무효화용 변수
  int _projectSelectRequestId = 0;       // 프로젝트 선택 요청 ID
  bool _isProjectSwitching = false;       // 프로젝트 전환 중 플래그
  int _roomSelectRequestId = 0;           // 방 선택 요청 ID
  // bool _isRoomSwitching = false;          // 방 전환 중 플래그
  bool _isProjectRefreshing = false;      // 프로젝트 새로고침 중 플래그

  OverlayEntry? _projectContextMenuEntry;

  // ★ 사용자 명령 직후 하트비트 자동복원 방지 (race condition 픽스)
  bool _pendingUserAction = false;

  // ★ 사용자 액션 순서 추적 (늦게 도착한 play 브로드캐스트 무시용)
  int _actionSeq = 0;
  int _lastUserPauseOrStopSeq = -1;

  final double _syncDiff = 0.5; // 싱크 오차범위

  @override
  void initState()  {
    super.initState();
    _isRoomInfoPanelOpen = hiveService.readRoomInfoPanelOpen();
    final savedPanelWidth = hiveService.readRoomPanelWidth();
    _roomPanelWidth = savedPanelWidth < _minRoomPanelWidth
        ? _minRoomPanelWidth
        : savedPanelWidth;
    _setupEventListener();

    _loadProjectList((){
      setState(() { _isProjectLoading = false; });
    });

    _projectDropAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );






    // _loadTimeLine((){
    //   if(projects.isNotEmpty){
    //     _selectedProjectIndex = 0;
    //     socketService.connectToProject(projects[_selectedProjectIndex!].id, (){ _setupEventListener(); },(){  _disposeEventListener(); }, (error){});
    //   }
    // });
  }

  TimelineController? _selectProjectControllerById(String projectId){
    for (var project in projects) {
      if (project.id == projectId) {
        return project.controller;
      }
    }

    return null;
  }
  
  void _setupEventListener(){
    print('📌 _setupEventListener 호출됨, 기존 _subs: ${_subs.length}개');
    // 새 리스너 설정 시 사용자 액션 플래그 초기화
    _pendingUserAction = false;

    _subs.add(socketService.trackAdded.listen((data) {
      print('📥 Track 업데이트 수신: ${data}');

      if (mounted) {
        setState(() {
          final addedTrack = Track.fromJson(data.track);
          _selectProjectControllerById(data.projectId)?.addTrack(addedTrack);
        });
      }
    }));

    _subs.add(socketService.trackUpdated.listen((data) {
      print('📥 Track 업데이트 수신: ${data}');

      if (mounted) {
        setState(() {
          _selectProjectControllerById(data.projectId)?.updateTrack(Track.fromJson(data.track));
        });
      }
    }));

    _subs.add(socketService.trackDeleted.listen((data) {
      print('📥 Track 삭제 수신: ${data.trackId}');

      if (mounted) {
        setState(() {
          _selectProjectControllerById(data.projectId)?.deleteTrack(data.trackId);
        });
      }
    }));

    _subs.add(socketService.onPlayStream.listen((data) {
      print('onPlay');
      _pendingUserAction = false;

      // 사용자가 일시정지/정지한 이후에 도착한 늦은 play 브로드캐스트는 무시
      if(_lastUserPauseOrStopSeq >= _actionSeq) return;

      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.seekTo(data.currentTime);
        _controller.play();
      }
    }));

    _subs.add(socketService.onPauseStream.listen((data) {
      print('onPause');
      _pendingUserAction = false;
      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.pause();
        _controller.seekTo(data.currentTime);
      }
    }));

    _subs.add(socketService.onStopStream.listen((data) {
      print('onStop');
      _pendingUserAction = false;
      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.stop();
      }
    }));

    _subs.add(socketService.timelineHeartbeat.listen((data) {
      // print('onTimelineHeartBeat');
      if(data.isPlaying){
        TimelineController? _controller = _selectProjectControllerById(data.projectId);

        if(_controller != null){
          // 500ms 이상 차이나면 서버 시간 적용, 그 이하면 건너뜀
          final diff = (data.currentTime - _controller.currentTime).abs();
          if(diff > _syncDiff){
            _controller.seekTo(data.currentTime);
          }

          // 사용자가 직접 조작한 직후에는 하트비트로 재생 상태를 변경하지 않음
          // (늦게 도착한 하트비트가 일시정지를 덮어쓰는 race condition 방지)
          if(!_controller.isPlaying && !_pendingUserAction){
            _controller.play();
          }
        }
      }
    }));

    _subs.add(socketService.roomCreated.listen((data) {
      setState(() {
        projects[_selectedProjectIndex!].roomsAll.add(Room(id: data.roomId, name: data.roomName, createdAt: data.createdAt));
      });
    }));

    _subs.add(socketService.roomUpdated.listen((data) {
      setState(() {
        if (_selectedRoomIndex != null &&
            _selectedRoomIndex! < projects[_selectedProjectIndex!].roomsAll.length &&
            projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id == data.roomId) {
          projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!] = Room(id: data.roomId, name: data.roomName, createdAt: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].createdAt);
        }
      });
    }));

    _subs.add(socketService.roomDeleted.listen((data) {
      setState(() {
        if (_selectedRoomIndex != null &&
            _selectedRoomIndex! < projects[_selectedProjectIndex!].roomsAll.length &&
            projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id == data.roomId) {
          _selectedRoomIndex = null;
          socketService.leaveRoom();
        }
        projects[_selectedProjectIndex!].roomsAll.removeWhere((room) => room.id == data.roomId);
      });
    }));

    _subs.add(socketService.roomAuthUpdated.listen((_) {
      // 관리자가 내 방 권한을 변경하면 권한 목록 갱신
      if (!_isAdminUser) _refreshMyRoomAuth();
    }));

    print('📌 _setupEventListener 완료, _subs: ${_subs.length}개');

  }


  // void _setupEventListeners() {
  //
  //
  //   //타임라인 업데이트
  //   socketService.onTimelineUpdated((timelineData){
  //     timelineController.updateTimeline(timelineData);
  //   });
  //
  //   //큐 추가 이벤트
  //   socketService.onCueAdded((trackId, cueData) {
  //     final cue = Cue.fromJson(cueData);
  //     timelineController.addCueToTrack(trackId, cue);
  //   });
  //
  //   //큐 업데이트 이벤트
  //   socketService.onCueUpdated((trackId, cueId, cueData){
  //     final cue = Cue.fromJson(cueData);
  //     timelineController.updateCueInTrack(trackId, cueId, cue);
  //   });
  //
  //   //큐 삭제 이벤트
  //   socketService.onCueDeleted((trackId, cueId) {
  //     timelineController.deleteCueFromTrack(trackId, cueId);
  //   });
  //
  //   //트랙 추가 이벤트
  //   socketService.onTrackAdded((trackData) {
  //     final track = Track.fromJson(trackData);
  //     timelineController.addTrack(track);
  //   });
  //
  //   socketService.onPlay((data){
  //     //시간 동기화
  //     timelineController.seekTo(data['currentTime'] is int ? data['currentTime'].toDouble() :data['currentTime']);
  //
  //     timelineController.play();
  //   });
  //
  //   socketService.onPause((data){
  //     timelineController.pause();
  //     //시간 동기화
  //     timelineController.seekTo(data['currentTime'] is int ? data['currentTime'].toDouble() :data['currentTime']);
  //   });
  //
  //   socketService.onStop((){
  //     timelineController.stop();
  //   });
  //
  //   socketService.onTimelineHeartBeat((data) {
  //     if(data['isPlaying']){
  //       // 진행 시간 조절
  //       timelineController.seekTo(data['currentTime'] is int ? data['currentTime'].toDouble() :data['currentTime']);
  //     }
  //
  //   });
  // }

  void _loadProjectList(Function() callback){

    socketService.getProjectList((projectList) {

      if (mounted) {
        setState(() {
          projects = projectList.map<TimelineProject>((projectData) {
            return TimelineProject.fromJson(projectData);
          }).toList();
        });

        //로컬 순서 적용
        _applyLocalOrder();

        callback.call();
      }

    });

  }
  

  // void _selectProject(int index) {
  //   if (_isReordering) return;// 드래그중 선택 방지
  //
  //   setState(() {
  //     _selectedProjectIndex = index;
  //     socketService.connectToProject(projects[_selectedProjectIndex!].id, (){ _setupEventListener(); },(){ _disposeEventListener(); }, (error){});
  //   });
  // }


  void _selectProjectList(int index) {
    _removeProjectContextMenu();
    if (_isReordering || _isDraggingProject) return;// 드래그중 선택 방지
    if (_selectedProjectIndex == index) return; // 이미 선택된 index 재선택 방지
    // if (_isProjectLoading) return; // 다른 프로젝트 선택해서 로딩중일시

    // ★ 이전 요청 무효화
    _projectSelectRequestId++;
    final thisRequestId = _projectSelectRequestId;


    // ★ 이전 방 선택 초기화
    if (_selectedRoomIndex != null) {
      _selectedRoomIndex = null;
      socketService.leaveRoom();
    }

    // ★ 이전 프로젝트 소켓 즉시 정리
    // if (_selectedProjectIndex != null) {
    //   _disposeEventListener();
    // }

    _disposeEventListener();

    setState(() {_isProjectSwitching = true; _selectedProjectIndex = null;});

    void finishSelect() {
      if (thisRequestId != _projectSelectRequestId) {
        print('⚠️ 프로젝트 선택 요청 무효화됨 (requestId: $thisRequestId, current: $_projectSelectRequestId)');
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedProjectIndex = index;
      });

      socketService.connectToProject( projects[index].id,
          //onConnected
        () {
          if (thisRequestId != _projectSelectRequestId) {
            print('⚠️ 연결 완료되었으나 이미 다른 프로젝트로 전환됨');
            return;
          }
          if (!mounted) return;

          print('onConnected');
          _setupEventListener();
          setState(() {
            _isProjectSwitching = false;
          });
        },
          //onDisconneted
        () {
          print('onDisconnected');
          if (mounted) {
            // _disposeEventListener();
            setState(() {
              _isProjectSwitching = false;
            });
          }
          },
          //onError
        (error) {
          print('onError');
          // _disposeEventListener();
          setState(() {
            _isProjectSwitching = false;
          });
        }
      );
    }

    if (_isAdminUser) {
      socketService.getProjectTimelinesAndRooms(projects[index].id, (projectData){
        // ★ 핵심: 이 요청이 여전히 유효한지 확인
        if (thisRequestId != _projectSelectRequestId) {
          print('⚠️ 프로젝트 선택 요청 무효화됨 (requestId: $thisRequestId, current: $_projectSelectRequestId)');
          return;
        }

        if (!mounted) return;

        if (projectData == null) {
          setState(() {
            _isProjectSwitching = false;
          });
          return;
        }

        projects[index] = TimelineProject.fromJson(projectData);
        finishSelect();
      });
    } else {
      // 일반 사용자: 전체 트랙을 받지 않고 방 목록만 로드 (방 입장 시 타임라인 조회)
      socketService.connectToProject( projects[index].id,
        //onConnected
        () {
          if (thisRequestId != _projectSelectRequestId) {
            print('⚠️ 연결 완료되었으나 이미 다른 프로젝트로 전환됨');
            return;
          }
          if (!mounted) return;

          socketService.getAllRooms((rooms) {
            if (thisRequestId != _projectSelectRequestId) {
              print('⚠️ 방 목록 요청 무효화됨');
              return;
            }
            if (!mounted) return;

            projects[index] = TimelineProject.fromJson({
              'id': projects[index].id,
              'name': projects[index].name,
              'duration': projects[index].duration,
              'created_at': projects[index].createdAt.toIso8601String(),
              'rooms': rooms,
              'tracks': <dynamic>[],
            });

            print('onConnected (일반 사용자, 방 목록만 로드)');
            _setupEventListener();
            _refreshMyRoomAuth();
            setState(() {
              _selectedProjectIndex = index;
              _isProjectSwitching = false;
            });
          });
        },
          //onDisconneted
        () {
          print('onDisconnected');
          if (mounted) {
            setState(() {
              _isProjectSwitching = false;
            });
          }
          },
          //onError
        (error) {
          print('onError');
          setState(() {
            _isProjectSwitching = false;
          });
        }
      );
    }
  }

  void _refreshCurrentProject() {
    if (_selectedProjectIndex == null || _isProjectRefreshing) return;

    setState(() { _isProjectRefreshing = true; });

    final projectId = projects[_selectedProjectIndex!].id;
    // 현재 선택된 방의 ID 저장 (인덱스가 아닌 실제 ID)
    final currentRoomId = _selectedRoomIndex != null &&
        _selectedRoomIndex! < projects[_selectedProjectIndex!].roomsAll.length
        ? projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id
        : null;

    if (_isAdminUser) {
      socketService.getProjectTimelinesAndRooms(projectId, (projectData) {
        if (!mounted) return;

        if (projectData == null) {
          setState(() { _isProjectRefreshing = false; });
          return;
        }

        projects[_selectedProjectIndex!] = TimelineProject.fromJson(projectData);

        // 현재 방이 여전히 존재하면 선택 유지, 없으면 해제
        if (currentRoomId != null) {
          final stillExists = projects[_selectedProjectIndex!].roomsAll
              .any((r) => r.id == currentRoomId);
          if (!stillExists) {
            _selectedRoomIndex = null;
            socketService.leaveRoom();
          }
        }

        setState(() { _isProjectRefreshing = false; });
      });
    } else {
      // 일반 사용자: 전체 트랙 없이 방 목록만 새로고침
      socketService.getAllRooms((rooms) {
        if (!mounted) return;

        final currentProject = projects[_selectedProjectIndex!];
        projects[_selectedProjectIndex!] = TimelineProject.fromJson({
          'id': currentProject.id,
          'name': currentProject.name,
          'duration': currentProject.duration,
          'created_at': currentProject.createdAt.toIso8601String(),
          'rooms': rooms,
          'tracks': <dynamic>[],
        });

        // 현재 방이 여전히 존재하면 선택 유지, 없으면 해제
        if (currentRoomId != null) {
          final stillExists = projects[_selectedProjectIndex!].roomsAll
              .any((r) => r.id == currentRoomId);
          if (!stillExists) {
            _selectedRoomIndex = null;
            socketService.leaveRoom();
          }
        }

        // 선택된 방 유지 시 해당 방 타임라인 재로드
        if (_selectedRoomIndex != null &&
            _selectedRoomIndex! < projects[_selectedProjectIndex!].roomsAll.length) {
          final rid = projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id;
          _loadRoomTimelineForNonAdmin(rid, _selectedRoomIndex!);
        }

        setState(() { _isProjectRefreshing = false; });
      });
    }
  }


  void _addTracks() {
    // 관리자는 전체, 일반 사용자는 편집 권한이 있는 방만 대상
    final roomList = _isAdminUser
        ? projects[_selectedProjectIndex!].roomsWithoutTrack
        : projects[_selectedProjectIndex!].roomsWithoutTrack
            .where((r) => _myAuthRoomIds.contains(r.id))
            .toList();

    if(roomList.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('타임라인을 추가할 그룹이 없습니다.'), duration: Duration(milliseconds: 500)),
      );

      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddTrackDialog(
        projectId: projects[_selectedProjectIndex!].id,
        roomList: List.from(roomList),
        onTimelineAdded: (data) {
          if (mounted) {
            setState(() {
              final addedTrack = Track.fromJson(data);
              final pid = projects[_selectedProjectIndex!].id;
              _selectProjectControllerById(pid)?.addTrack(addedTrack);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('타임라인이 추가되었습니다'), duration: Duration(milliseconds: 500)),
            );
          }
        },
      ),
    );

  }

  void _updateTracks(String projectId, Track track, {bool showSnackBar = true}){
    // 일반 사용자는 프로젝트 전체 트랙을 편집할 수 없고, 해당 트랙의 방에 대한 편집 권한이 있어야 함
    if (!_isAdminUser && (track.room_id == projectId || !_myAuthRoomIds.contains(track.room_id))) return;

    socketService.updateTrack(projectId, track.id, track.name, track.room_id, track.cues,
          (success, data) {
        if (mounted) {
          if (success) {
            projects[_selectedProjectIndex!].controller.updateTrack(Track.fromJson(data!));

            setState(() {});

            if (showSnackBar) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('타임라인 수정 성공'), duration: Duration(milliseconds: 500)),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('타임라인 수정 실패'), duration: Duration(milliseconds: 500)),
            );
          }
        }
      },
    );
  }

  void _deleteTracks(String projectId, Track track) {
    // 일반 사용자는 프로젝트 전체 트랙을 삭제할 수 없고, 해당 트랙의 방에 대한 편집 권한이 있어야 함
    if (!_isAdminUser && (track.room_id == projectId || !_myAuthRoomIds.contains(track.room_id))) return;
    socketService.deleteTrack(projectId,track.room_id,track.id, (success,trackId) {
      if (mounted) {
        if (success && trackId != null) {
          setState(() {
            projects[_selectedProjectIndex!].controller.deleteTrack(trackId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('타임라인이 삭제되었습니다'), duration: Duration(milliseconds: 500)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('타임라인 삭제 실패'), duration: Duration(milliseconds: 500)),
          );
        }
      }
    });
  }

  void _updateProject([int? index]) {
    if (!socketService.isAdminUser) return;
    final idx = index ?? _selectedProjectIndex;
    if (idx == null || idx >= projects.length) return;

    UpdateProjectDialog.showDraggable(
      context,
      projectId: projects[idx].id,
      projectName: projects[idx].name,
      duration: projects[idx].duration,
      onProjectUpdated: (name, duration) {
        setState(() {
          projects[idx].name = name;
          projects[idx].duration = duration * 3600;
          projects[idx].controller.updateProjectInfo(name, (duration * 3600).toDouble());
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로젝트가 수정되었습니다'), duration: Duration(milliseconds: 500)),
        );
      },
    );
  }

  void _deleteProject([int? index]) {
    if (!socketService.isAdminUser) return;
    final idx = index ?? _selectedProjectIndex;
    if (idx == null || idx >= projects.length) return;

    showDialog(
      context: context,
      builder: (context) => DeleteProjectDialog(
        projectId: projects[idx].id,
        projectName: projects[idx].name,
        onProjectDeleted: (data) {
          setState(() {
            projects.removeAt(idx);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트가 삭제되었습니다'), duration: Duration(milliseconds: 500)),
          );
        },
      ),
    );
  }

  void _addProject() {
    if (!socketService.isAdminUser) return;

    AddProjectDialog.showDraggable(
      context,
      onProjectAdded: (data) {
        // _loadTimeLine(null);
        setState(() {
          projects.add(TimelineProject.fromJson(data));
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로젝트가 생성되었습니다'), duration: Duration(milliseconds: 500)),
        );
      },
    );
  }

  void _sendWholeMessage() {

    MessageWholeDialog.showDraggable(
      context,
      onMessageSended: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지가 전송되었습니다'), duration: Duration(milliseconds: 500)),
        );
      },
    );
  }


  // void _leaveRoom() {
  //   socketService.leaveRoom();
  //   Navigator.of(context).pop();
  // }


  void _removeProjectContextMenu() {
    _projectContextMenuEntry?.remove();
    _projectContextMenuEntry = null;
  }

  Widget _buildProjectMenuContainer({required List<Widget> children}) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _projectMenuItem({
    required IconData icon,
    required String label,
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
            Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _showProjectContextMenu(TapUpDetails details, int index) {
    _removeProjectContextMenu();

    _projectContextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeProjectContextMenu(),
              ),
            ),
            Positioned(
              left: details.globalPosition.dx,
              top: details.globalPosition.dy,
              child: _buildProjectMenuContainer(
                children: [
                  if (socketService.isAdminUser) ...[
                    _projectMenuItem(
                      icon: Icons.edit,
                      label: '프로젝트 수정',
                      onTap: () {
                        _removeProjectContextMenu();
                        _updateProject(index);
                      },
                    ),
                    _projectMenuItem(
                      icon: Icons.delete,
                      label: '프로젝트 삭제',
                      iconColor: Colors.red,
                      labelColor: Colors.red,
                      onTap: () {
                        _removeProjectContextMenu();
                        _deleteProject(index);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_projectContextMenuEntry!);
  }

  // void _showProjectContextMenuEmpty(TapUpDetails details) {
  //   _removeProjectContextMenu();
  //
  //   _projectContextMenuEntry = OverlayEntry(
  //     builder: (context) {
  //       return Stack(
  //         children: [
  //           Positioned.fill(
  //             child: Listener(
  //               behavior: HitTestBehavior.translucent,
  //               onPointerDown: (_) => _removeProjectContextMenu(),
  //             ),
  //           ),
  //           Positioned(
  //             left: details.globalPosition.dx,
  //             top: details.globalPosition.dy,
  //             child: _buildProjectMenuContainer(
  //               children: [
  //                 _projectMenuItem(
  //                   icon: Icons.add,
  //                   label: '프로젝트 추가',
  //                   onTap: () {
  //                     _removeProjectContextMenu();
  //                     _addProject();
  //                   },
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  //
  //   Overlay.of(context).insert(_projectContextMenuEntry!);
  // }

  void _showProjectPopupMenu() {
    final RenderBox? button = _projectMenuKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null || !button.hasSize) return;
    final buttonPos = button.localToGlobal(Offset.zero);
    final buttonSize = button.size;

    int _hoveredIndex = -1;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.transparent),
                ),
                Positioned(
                  left: buttonPos.dx,
                  top: buttonPos.dy + buttonSize.height,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[850],
                    child: SizedBox(
                      width: buttonSize.width,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate(projects.length, (index) {
                            final project = projects[index];
                            final isSelected = _selectedProjectIndex == index;
                            final isHovered = _hoveredIndex == index;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) => setDialogState(() => _hoveredIndex = index),
                              onExit: (_) => setDialogState(() => _hoveredIndex = -1),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _selectProjectList(index);
                                },
                                onSecondaryTapUp: (details) {
                                  _showProjectContextMenu(details, index);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isHovered
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : isSelected
                                            ? Colors.blue.withValues(alpha: 0.2)
                                            : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.movie, size: 16,
                                        color: isSelected ? Colors.blue[300] : Colors.grey[500]),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              project.name,
                                              style: TextStyle(
                                                color: isSelected ? Colors.blue[300] : Colors.grey[200],
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '${(project.duration / 3600).toInt()}시간',
                                              style: TextStyle(color: Colors.grey[600], fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.check, size: 14, color: Colors.blue[300]),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const Divider(height: 1, color: Colors.grey),
                          if (socketService.isAdminUser)
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _addProject();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.add, size: 16, color: Colors.green),
                                      SizedBox(width: 10),
                                      Text('새 프로젝트', style: TextStyle(color: Colors.green, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addRoom(){
    AddRoomDialog.showDraggable(
      context,
      onRoomAdded: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방이 생성되었습니다'), duration: Duration(milliseconds: 500)),
        );
      },
    );
  }

  void _showRoomParticipants(TimelineProject project) {
    if (_selectedRoomIndex == null ||
        _selectedRoomIndex! >= project.roomsAll.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('참여인원을 볼 방을 먼저 선택해주세요'),
          duration: Duration(milliseconds: 500),
        ),
      );
      return;
    }

    final room = project.roomsAll[_selectedRoomIndex!];
    List<Map<String, dynamic>> members = [];
    bool loading = true;
    void Function(VoidCallback)? dialogSetState;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            dialogSetState = setDialogState;
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.people_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${room.name} — 참여인원 (${members.length}명)',
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 320,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : members.isEmpty
                        ? const Center(
                            child: Text(
                              '참여인원이 없습니다',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (context, index) {
                              final member = members[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.person,
                                  color: Colors.green,
                                ),
                                title: Text(
                                  member['userName']?.toString() ?? 'Unknown',
                                ),
                                subtitle: Text(
                                  member['userId']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );

    socketService.getRoomInfo(room.id, (success, roomInfo) {
      if (!mounted) return;
      members = (success && roomInfo != null)
          ? List<Map<String, dynamic>>.from(roomInfo['members'] ?? [])
          : _members;
      loading = false;
      dialogSetState?.call(() {});
    });
  }

  void _updateRoom({String? roomId, String? roomName}){
    final rid = roomId ?? projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id;
    final rname = roomName ?? projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].name;
    if (!_isAdminUser && !_myAuthRoomIds.contains(rid)) return;
    UpdateRoomDialog.showDraggable(
      context,
      roomId: rid,
      roomName: rname,
      onRoomUpdated: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방이 수정되었습니다'), duration: Duration(milliseconds: 500)),
        );
      },
    );
  }

  void _deleteRoom({String? roomId, String? roomName}){
    final rid = roomId ?? projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id;
    final rname = roomName ?? projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].name;
    if (!_isAdminUser) return;
    showDialog(
      context: context,
      builder: (context) => DeleteRoomDialog(
        roomId: rid,
        roomName: rname,
        onRoomDeleted: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방이 삭제되었습니다'), duration: Duration(milliseconds: 500)),
          );
        },
      ),
    );
  }

  void _showRoomContextMenu(TapUpDetails details, int index) {
    final room = projects[_selectedProjectIndex!].roomsAll[index];
    final canEdit = _isAdminUser || _myAuthRoomIds.contains(room.id);
    if (!canEdit) return;
    _removeProjectContextMenu();

    _projectContextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeProjectContextMenu(),
              ),
            ),
            Positioned(
              left: details.globalPosition.dx,
              top: details.globalPosition.dy,
              child: _buildProjectMenuContainer(
                children: [
                  if (canEdit)
                    _projectMenuItem(
                      icon: Icons.edit,
                      label: '방 수정',
                      onTap: () {
                        _removeProjectContextMenu();
                        _updateRoom(roomId: room.id, roomName: room.name);
                      },
                    ),
                  if (_isAdminUser)
                    _projectMenuItem(
                      icon: Icons.delete,
                      label: '방 삭제',
                      iconColor: Colors.red,
                      labelColor: Colors.red,
                      onTap: () {
                        _removeProjectContextMenu();
                        _deleteRoom(roomId: room.id, roomName: room.name);
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_projectContextMenuEntry!);
  }

  void _showRoomContextMenuEmpty(TapUpDetails details) {
    _removeProjectContextMenu();

    _projectContextMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _removeProjectContextMenu(),
              ),
            ),
            Positioned(
              left: details.globalPosition.dx,
              top: details.globalPosition.dy,
              child: _buildProjectMenuContainer(
                children: [
                  if (_isAdminUser)
                    _projectMenuItem(
                      icon: Icons.add,
                      label: '방 추가',
                      onTap: () {
                        _removeProjectContextMenu();
                        _addRoom();
                      },
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_projectContextMenuEntry!);
  }

  // 로컬에 저장된 순서를 프로젝트 리스트에 적용
  void _applyLocalOrder() {
    // final savedOrders = _hiveService.getProjectAllIndex();

    // if (savedOrders!.isEmpty) {
    //   print('⚠ 저장된 순서가 없습니다. 기본 순서 사용.');
    //   return;
    // }

    // print('📂 로컬 순서 적용 중...');

    // 순서가 저장된 프로젝트와 없는 프로젝트 분리
    final orderedProjects = <TimelineProject>[];
    final unorderedProjects = <TimelineProject>[];

    for (var project in projects) {
      if (project.index! >= 0) {
        orderedProjects.add(project);
      } else {
        unorderedProjects.add(project);
      }
    }

    // 저장된 순서대로 정렬
    // orderedProjects.sort((a, b) {
    //   final orderA = savedOrders[a.id] ?? 999999;
    //   final orderB = savedOrders[b.id] ?? 999999;
    //   return orderA.compareTo(orderB);
    // });

    // 저장된 순서대로 정렬
    orderedProjects.sort((a, b) => a.index!.compareTo(b.index!));
    unorderedProjects.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // print("order : ${orderedProjects}");
    // print("unorder : ${unorderedProjects}");

    // 순서가 없는 프로젝트는 뒤에 추가 (서버 순서 유지)
    projects = [...orderedProjects, ...unorderedProjects];

  }

  // 프로젝트 순서 변경
  // void _reorderProjects(int oldIndex, int newIndex) {
  //   setState(() {
  //     _isReordering = true;
  //
  //     // 리스트에서 아이템 이동
  //     final project = projects.removeAt(oldIndex);
  //     projects.insert(newIndex, project);
  //
  //     hiveService.projectIndexSave(project.id, newIndex);
  //
  //
  //     // 선택된 인덱스 업데이트
  //     if (_selectedProjectIndex != null) {
  //       if (_selectedProjectIndex == oldIndex) {
  //         _selectedProjectIndex = newIndex;
  //       } else if (oldIndex < _selectedProjectIndex! && newIndex >= _selectedProjectIndex!) {
  //         _selectedProjectIndex = _selectedProjectIndex! - 1;
  //       } else if (oldIndex > _selectedProjectIndex! && newIndex <= _selectedProjectIndex!) {
  //         _selectedProjectIndex = _selectedProjectIndex! + 1;
  //       }
  //     }
  //   });
  //
  //
  //
  //   // 드래그 완료 후 잠시 후 플래그 해제
  //   Future.delayed(const Duration(milliseconds: 300), () {
  //     if (mounted) {
  //       setState(() {
  //         _isReordering = false;
  //       });
  //     }
  //   });
  // }

  // ── 프로젝트 롱클릭 드래그 ──

  // void _onProjectDragStart(LongPressStartDetails details, int index) {
  //   final RenderBox? listBox =
  //       _projectListKey.currentContext?.findRenderObject() as RenderBox?;
  //   if (listBox == null) return;
  //
  //   // 1) 기존 오버레이 즉시 제거
  //   _projectDragOverlay?.remove();
  //   _projectDragOverlay = null;
  //
  //   // 2) 컨트롤러 정지/리셋 (이전 애니메이션 리스너 차단)
  //   if (_projectDropAnimController?.isAnimating == true) {
  //     _projectDropAnimController!.stop();
  //   }
  //   _projectDropAnimController?.reset();
  //   if (_dropAnim != null && _dropAnimListener != null) {
  //     _dropAnim!.removeListener(_dropAnimListener!);
  //   }
  //   _dropAnim = null;
  //   _dropAnimListener = null;
  //
  //   // 3) 새 드래그 상태 설정
  //   final globalPosition = details.globalPosition;
  //   final listGlobalLeft = listBox.localToGlobal(Offset.zero).dx;
  //
  //   _draggedProjectIndex = index;
  //   _dragTargetProjectIndex = index;
  //   _dragProjectPosition = Offset(listGlobalLeft, globalPosition.dy - 40);
  //   _dragProjectPositionNotifier.value = _dragProjectPosition;
  //
  //   // 4) 새 오버레이 삽입
  //   _projectDragOverlay = OverlayEntry(builder: (_) => _buildProjectDragOverlay());
  //   Overlay.of(context).insert(_projectDragOverlay!);
  //
  //   setState(() {
  //     _isDraggingProject = true;
  //     _isReordering = true;
  //   });
  // }
  //
  // void _onProjectDragMove(LongPressMoveUpdateDetails details) {
  //   final RenderBox? listBox =
  //       _projectListKey.currentContext?.findRenderObject() as RenderBox?;
  //   if (listBox == null) return;
  //
  //   final globalPosition = details.globalPosition;
  //   final localY = listBox.globalToLocal(globalPosition).dy;
  //   final listGlobalLeft = listBox.localToGlobal(Offset.zero).dx;
  //
  //   _dragProjectPosition = Offset(listGlobalLeft, globalPosition.dy - 40);
  //   _dragProjectPositionNotifier.value = _dragProjectPosition;
  //
  //   final newIndex = _getDragTargetProjectIndex(localY);
  //   if (newIndex != _dragTargetProjectIndex && newIndex >= 0 && newIndex < projects.length) {
  //     setState(() {
  //       _dragTargetProjectIndex = newIndex;
  //     });
  //   }
  // }
  //
  // void _onProjectDragEnd(LongPressEndDetails details) {
  //   final oldIndex = _draggedProjectIndex;
  //   final newIndex = _dragTargetProjectIndex;
  //
  //   if (oldIndex != null && newIndex != null && oldIndex != newIndex) {
  //     final RenderBox? listBox =
  //         _projectListKey.currentContext?.findRenderObject() as RenderBox?;
  //     final listGlobalTop = listBox?.localToGlobal(Offset.zero).dy ?? 0;
  //     final listGlobalLeft = listBox?.localToGlobal(Offset.zero).dx ?? 0;
  //     final targetY = listGlobalTop + newIndex * 80.0;
  //     final startOffset = _dragProjectPosition;
  //
  //     _projectDropAnimController?.forward(from: 0.0).then((_) {
  //       _removeProjectDragOverlay();
  //
  //       setState(() {
  //         _isDraggingProject = false;
  //         _draggedProjectIndex = null;
  //         _dragTargetProjectIndex = null;
  //       });
  //
  //       _reorderProjects(oldIndex, newIndex);
  //     });
  //
  //     _animateDrop(startOffset, Offset(listGlobalLeft, targetY));
  //   } else {
  //     _removeProjectDragOverlay();
  //     setState(() {
  //       _isDraggingProject = false;
  //       _draggedProjectIndex = null;
  //       _dragTargetProjectIndex = null;
  //       _isReordering = false;
  //     });
  //   }
  // }

  // void _animateDrop(Offset startOffset, Offset targetOffset) {
  //   if (_dropAnim != null && _dropAnimListener != null) {
  //     _dropAnim!.removeListener(_dropAnimListener!);
  //   }
  //   final animation = Tween<Offset>(
  //     begin: startOffset,
  //     end: targetOffset,
  //   ).animate(CurvedAnimation(
  //     parent: _projectDropAnimController!,
  //     curve: Curves.easeOut,
  //   ));
  //   _dropAnim = animation;
  //   _dropAnimListener = () {
  //     _dragProjectPositionNotifier.value = animation.value;
  //   };
  //   animation.addListener(_dropAnimListener!);
  // }

  // int _getDragTargetProjectIndex(double localY) {
  //   final index = (localY / 80).floor();
  //   return index.clamp(0, projects.length - 1);
  // }

  void _removeProjectDragOverlay() {
    _projectDragOverlay?.remove();
    _projectDragOverlay = null;
  }

  // Widget _buildProjectDragOverlay() {
  //   return ValueListenableBuilder<Offset>(
  //     valueListenable: _dragProjectPositionNotifier,
  //     builder: (context, position, _) {
  //       if (_draggedProjectIndex == null || _draggedProjectIndex! >= projects.length) {
  //         return const SizedBox.shrink();
  //       }
  //       final project = projects[_draggedProjectIndex!];
  //       return Positioned(
  //         left: position.dx,
  //         top: position.dy,
  //         child: Material(
  //           elevation: 8,
  //           color: Colors.transparent,
  //           borderRadius: BorderRadius.circular(8),
  //           child: Container(
  //             width: _leftProjectListPanelWidth - 16,
  //             decoration: BoxDecoration(
  //               color: Colors.blue[900],
  //               borderRadius: BorderRadius.circular(8),
  //             ),
  //             child: ListTile(
  //               leading: const Icon(Icons.movie, color: Colors.white),
  //               title: Text(
  //                 project.name,
  //                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
  //               ),
  //               subtitle: Text(
  //                 'Duration: ${(project.duration / 3600).toInt()} 시간',
  //                 style: TextStyle(color: Colors.grey[300], fontSize: 12),
  //               ),
  //             ),
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  //프로젝트 재생
  void sendProjectPlay(String projectId, double startTime){
    _actionSeq++;
    _pendingUserAction = true;
    Future.delayed(const Duration(seconds: 5), () {
      _pendingUserAction = false;
    });

    // 낙관적 업데이트: 서버 응답을 기다리지 않고 즉시 UI 변경
    final controller = _selectProjectControllerById(projectId);
    controller?.seekTo(startTime);
    controller?.play();

    socketService.sendPlay(projectId, startTime, (success) {
      _pendingUserAction = false;
      if(!success){
        // 서버에서 거절됨(이미 재생 중) → 로컬 상태 유지, 롤백하지 않음
        print('sendPlay: 서버에서 재생 거절 (이미 재생 중)');
      }
    });
  }

  //프로젝트 정지
  void sendProjectStop(String projectId){
    _actionSeq++;
    _lastUserPauseOrStopSeq = _actionSeq;
    _pendingUserAction = true;
    Future.delayed(const Duration(seconds: 5), () {
      _pendingUserAction = false;
    });

    // 낙관적 업데이트
    final controller = _selectProjectControllerById(projectId);
    controller?.stop();

    socketService.sendStop(projectId, (success) {
      _pendingUserAction = false;
      if(!success){
        print('sendStop: 서버에서 정지 거절');
      }
    });
  }

  //프로젝트 일시정지
  void sendProjectPause(String projectId, double pauseTime){
    _actionSeq++;
    _lastUserPauseOrStopSeq = _actionSeq;
    _pendingUserAction = true;
    Future.delayed(const Duration(seconds: 5), () {
      _pendingUserAction = false;
    });

    // 낙관적 업데이트
    final controller = _selectProjectControllerById(projectId);
    controller?.pause();
    controller?.seekTo(pauseTime);

    socketService.sendPause(projectId, pauseTime, (success) {
      _pendingUserAction = false;
      if(!success){
        print('sendPause: 서버에서 일시정지 거절 (이미 정지 상태)');
      }
    });
  }


  void onCueCreateRequest(String projectId, Track track, double startTime) {
    print("onCueCreateRequest : ${startTime.toInt()}");
    _updateTracks(projectId, track);
  }

  void onCueUpdateRequest(String projectId, Track track) {
    print("onCueUpdateRequest");
    _updateTracks(projectId, track);
  }

  void onCueDeleteRequest(String projectId, Track track) {
    print("onCueDeleteRequest");
    _updateTracks(projectId, track);
  }

  void onCueMoved(String projectId, Track track, {bool showSnackBar = true}) {
    print("onCueMoved");
    _updateTracks(projectId, track, showSnackBar: showSnackBar);
  }

  void onTrackUpdateRequest(String projectId, Track track) {
    print("onTrackUpdateRequest : ${projectId} , ${track.id}");
    _updateTracks(projectId, track);
  }

  void onTrackDeleteRequest(String projectId, Track track) {
    print("onTrackDeleteRequest : ${projectId} , ${track.id}");
    _deleteTracks(projectId, track);
  }

  void onCuesPasteRequest(String projectId, Track track) {
    print("onCuesPasteRequest : ${projectId}");
    _updateTracks(projectId, track);
  }

  // void _toggleRoomPanel() {
  //   setState(() {
  //     _isRoomPanelOpen = !_isRoomPanelOpen;
  //   });
  // }

  void _selectRoom(String roomId, int index) async {
    // print('방호출');

    if(_selectedRoomIndex == index) return;

    // ★ 이전 방 요청 무효화
    _roomSelectRequestId++;
    final thisRoomRequestId = _roomSelectRequestId;

    setState(() {
      _isRoomLoading = true;
    });

    // socketService.leaveRoom();
    socketService.leaveRoom();

    // 일반 사용자: 방 전환 시 이전 방 트랙 즉시 초기화 (잘못된 트랙 표시 방지)
    if (!_isAdminUser && _selectedProjectIndex != null) {
      final controller = projects[_selectedProjectIndex!].controller;
      final current = controller.timelineData;
      controller.loadFromMap({
        'duration': current?.duration ?? 0.0,
        'tracks': <dynamic>[],
        'id': projects[_selectedProjectIndex!].id,
        'created_at': (current?.createdAt ?? DateTime.now()).toIso8601String(),
      });
    }

    // 프레임 대기 (dispose 완료 보장)
    await Future.delayed(const Duration(milliseconds: 100));

    // ★ 대기 후에도 유효한지 확인
    if (thisRoomRequestId != _roomSelectRequestId) {
      print('⚠️ 방 선택 요청 무효화됨');
      return;
    }

    socketService.joinRoom(roomId, socketService.displayName, (success, members) {
      // ★ 콜백 도착 시 유효성 확인
      if (thisRoomRequestId != _roomSelectRequestId) {
        print('⚠️ 방 입장 콜백 무효화됨');
        return;
      }

      if (!mounted) return;

      if (success) {
        // _navigateToRoom(roomId, UserName, members);

        if(mounted){
          setState(() {
            // _selectedRoomId = roomId;
            _selectedRoomIndex = index;
            _members = members;
            // _messages = messages;

            _isRoomLoading = false;
            print('members = ${members} ');
            // _isRoomPanelOpen = false; // 방 선택 시 패널 자동 닫기
          });

          // 일반 사용자: 방 입장 후 해당 방 타임라인 로드
          if (!_isAdminUser) {
            _loadRoomTimelineForNonAdmin(roomId, index);
          }
        }
      }else{
        setState(() {
          _isRoomLoading = false;
        });
      }
    });

  }


  String _getTrackNameForRoom(TimelineProject project, String roomId){
    final tracks = project.controller.timelineData?.tracks?? [];
    try{
      final track = tracks.firstWhere((tracks) => tracks.room_id == roomId);
      return track.name;
    }catch(e){
      return '트랙없음';
    }
  }

  bool get _isAdminUser => socketService.isAdminUser;

  // 일반 사용자: 선택한 방의 타임라인(프로젝트 전체 트랙 + 해당 방 트랙) 로드
  void _loadRoomTimelineForNonAdmin(String roomId, int roomIndex) {
    socketService.getTimeLine(roomId, (timeline) {
      if (!mounted) return;
      if (_selectedProjectIndex == null) return;
      if (_selectedRoomIndex != roomIndex) return;
      if (timeline != null) {
        projects[_selectedProjectIndex!].controller.loadFromMap(timeline);
      }
    });
  }

  // 일반 사용자: 내가 편집 가능한 방(권한) 목록 갱신
  void _refreshMyRoomAuth() {
    // 서버가 일반 사용자 세션 기준으로 권한을 반환하므로 userId 미지원(자동로그인)도 동작
    socketService.getUserAuthList(socketService.userId, (success, roomList) {
      if (!success || !mounted) return;
      setState(() {
        _myAuthRoomIds.clear();
        _myAuthRoomIds.addAll(roomList
            .map((r) => r['room_id']?.toString() ?? '')
            .where((s) => s.isNotEmpty));
      });
    });
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const Icon(Icons.folder, color: Colors.white),
              const SizedBox(width: 12),
              const Text(
                '프로젝트',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 40),
              GestureDetector(
                key: _projectMenuKey,
                onTap: _showProjectPopupMenu,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu, size: 16, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          _selectedProjectIndex != null && _selectedProjectIndex! < projects.length
                              ? projects[_selectedProjectIndex!].name
                              : '목록',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (socketService.isAdminUser)
            IconButton(
              icon:  const Icon(Icons.add, color: Colors.white),
              onPressed: _addProject,
              tooltip: '프로젝트 생성',
            ),
        ],

        backgroundColor: Colors.grey[850],
      ),
      body: _isProjectLoading
      ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('프로젝트 로딩 중...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),),
          ],
        ),
      )
      : projects.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 16),
            Text('프로젝트가 없습니다',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),),
          ],
        ),
      )
          : _isProjectSwitching
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('프로젝트 로딩 중...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),),
                ],
              ),
            )
                : _selectedProjectIndex == null || _selectedProjectIndex! >= projects.length
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '위의 프로젝트 목록에서 프로젝트를 선택하세요',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                : _buildTimelineView(projects[_selectedProjectIndex!]),
      backgroundColor: Colors.grey[850],
    );
  }

  Widget _buildTimelineView(TimelineProject project) {
    return Column(
      children: [
        // 프로젝트 정보 헤더
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[850],
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showProjectContextMenu(details, _selectedProjectIndex!);
                      },
                      child: Row(
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          icon: Icons.timer,
                          label: '${(project.duration / 3600).toInt()} 시간',
                          color: Colors.blue,
                        ),
                        // const SizedBox(width: 8),
                        // _buildInfoChip(
                        //   icon: Icons.speed,
                        //   label: '${project.fps} FPS',
                        //   color: Colors.green,
                        // ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: _isProjectRefreshing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.refresh, color: Colors.white),
                          onPressed: _isProjectRefreshing ? null : _refreshCurrentProject,
                          tooltip: '새로고침',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // IconButton(
                                //   icon: const Icon(Icons.add, color: Colors.white),
                                //   onPressed: _addTracks,
                                //   tooltip: '타임라인 추가',
                                // ),
                                // const SizedBox(width: 8),
                                // IconButton(
                                //   icon: const Icon(Icons.settings, color: Colors.white),
                                //   onPressed: _updateProject,
                                //   tooltip: '프로젝트 수정',
                                // ),

                                PopupMenuButton(
                                    icon: const Icon(Icons.menu, color: Colors.white),
                                    color: Colors.grey[800],
                                    tooltip: '프로젝트 및 타임라인 설정',
                                    itemBuilder: (context) => <PopupMenuEntry> [
                                      PopupMenuItem(
                                        onTap: _addTracks,
                                        child: const ListTile(
                                          leading: const Icon(Icons.add, color: Colors.white),
                                          title: Text('타임라인 추가',style: TextStyle(color: Colors.white),),
                                        ),
                                      ),
                                      if (socketService.isAdminUser) ...[
                                        PopupMenuItem(
                                          onTap: _updateProject,
                                          child: const ListTile(
                                            leading:const Icon(Icons.mode, color: Colors.white),
                                            title: Text('프로젝트 수정',style: TextStyle(color: Colors.white),),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          onTap: _deleteProject,
                                          child: const ListTile(
                                            leading:const Icon(Icons.remove, color: Colors.white),
                                            title: Text('프로젝트 삭제',style: TextStyle(color: Colors.white),),
                                          ),
                                        ),
                                      ],
                                      PopupMenuItem(
                                        onTap: _sendWholeMessage,
                                        child: const ListTile(
                                          leading:const Icon(Icons.messenger, color: Colors.white),
                                          title: Text('프로젝트 전체 메시지',style: TextStyle(color: Colors.white),),
                                        ),
                                      ),

                                    ]
                                ),


                                // ✅ 방 목록 열기 버튼
                                // IconButton(
                                //   icon: Stack(
                                //     children: [
                                //       const Icon(Icons.meeting_room, color: Colors.white),
                                //       if (project.rooms.isNotEmpty)
                                //         Positioned(
                                //           right: 0,
                                //           top: 0,
                                //           child: Container(
                                //             padding: const EdgeInsets.all(4),
                                //             decoration: const BoxDecoration(
                                //               color: Colors.red,
                                //               shape: BoxShape.circle,
                                //             ),
                                //             child: Text(
                                //               '${project.rooms.length}',
                                //               style: const TextStyle(
                                //                 color: Colors.white,
                                //                 fontSize: 10,
                                //                 fontWeight: FontWeight.bold,
                                //               ),
                                //             ),
                                //           ),
                                //         ),
                                //     ],
                                //   ),
                                //   onPressed: _toggleRoomPanel,
                                //   tooltip: '방 목록',
                                // ),


                               ],
                            ),

                        ),


                      ],
                      ),
                    ),

                    // const SizedBox(height: 8),
                    // Row(
                    //   children: [
                    //     _buildInfoChip(
                    //       icon: Icons.timer,
                    //       label: '${project.duration}s',
                    //       color: Colors.blue,
                    //     ),
                    //     const SizedBox(width: 8),
                    //     _buildInfoChip(
                    //       icon: Icons.speed,
                    //       label: '${project.fps} FPS',
                    //       color: Colors.green,
                    //     ),
                    //     const SizedBox(width: 8),
                    //
                    //   ],
                    // ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxPanelWidth = (constraints.maxWidth - _minTimelineWidth) < _minRoomPanelWidth
                    ? _minRoomPanelWidth
                    : (constraints.maxWidth - _minTimelineWidth);
                return Row(
                  children: [
                SizedBox(
                  width: _isRoomInfoPanelOpen ? _roomPanelWidth : _roomListWidth,
                  child: _buildRoomSlidePanel(project),
                ),
                if (_isRoomInfoPanelOpen)
                  _buildPanelResizeHandle(maxPanelWidth),

                Expanded(
                    // flex: 7,
                    child: (!_isAdminUser && _selectedRoomIndex == null)
                        ? _buildNonAdminRoomEntryPlaceholder(project)
                        : TimelineWidget(controller: project.controller, sendPlay: (startTime) => sendProjectPlay(project.id, startTime), sendStop: () => sendProjectStop(project.id), sendPause: (pauseTime) => sendProjectPause(project.id,pauseTime),
                      onCueCreateRequest: onCueCreateRequest, onCueUpdateRequest: onCueUpdateRequest , onCueDeleteRequest: onCueDeleteRequest ,onCueMoved: onCueMoved, onTrackUpdateRequest: onTrackUpdateRequest, onTrackDeleteRequest: onTrackDeleteRequest, onTrackAddRequest: _addTracks, onCuesPasteRequest: onCuesPasteRequest, commentOffset: hiveService.readCommentOffset(), roomsWithoutTrack: project.roomsWithoutTrack, roomsAll: project.roomsAll, isAdminUser: socketService.isAdminUser, canControl: socketService.isAdminUser ||
                          (_selectedRoomIndex != null &&
                              _selectedRoomIndex! < project.roomsAll.length &&
                              _myAuthRoomIds.contains(project.roomsAll[_selectedRoomIndex!].id)),),
                ),
                  ],
                );
              },
            )
        ),



        // Expanded(
        //   child: TimelineWidget(controller: project.controller, sendPlay: () => sendProjectPlay(project.id), sendStop: () => sendProjectStop(project.id), sendPause: () => sendProjectPause(project.id),),
        // ),
        // 타임라인 위젯


        // 컨트롤 버튼

      ],
    );
  }

  Widget _buildPanelResizeHandle(double maxPanelWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _roomPanelWidth = (_roomPanelWidth + details.delta.dx)
                .clamp(_minRoomPanelWidth, maxPanelWidth);
            hiveService.saveRoomPanelWidth(_roomPanelWidth);
          });
        },
        child: Container(
          width: 6,
          color: Colors.transparent,
        ),
      ),
    );
  }

  // 일반 사용자: 방에 입장하지 않으면 트랙 대신 안내 표시
  Widget _buildNonAdminRoomEntryPlaceholder(TimelineProject project) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.meeting_room_outlined, size: 72, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              '방에 입장하면 타임라인이 표시됩니다',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '좌측 방 목록에서 입장할 방을 선택하세요',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomSlidePanel(TimelineProject project) {



    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          right: BorderSide(color: Colors.grey[800]!),
        )
      ),
      child: Column(
        children: [
          // ✅ 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              // border: Border(
              //   bottom: BorderSide(color: Colors.grey[800]!),
              // ),
            ),
            child: Row(
              children: [
                // const Icon(
                //   Icons.meeting_room,
                //   color: Colors.white,
                //   size: 20,
                // ),
                // const SizedBox(width: 12),
                // Expanded(
                //
                //   child: Text(
                //     '방 목록 (${project.roomsAll.length}개)',
                //     style: const TextStyle(
                //       color: Colors.white,
                //       fontSize: 16,
                //       fontWeight: FontWeight.bold,
                //     ),
                //   ),
                // ),
                // // IconButton(
                // //   icon: const Icon(Icons.close, color: Colors.white),
                // //   onPressed: _toggleRoomPanel,
                // //   tooltip: '닫기',
                // // ),

                const Spacer(),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      tooltip: '더보기',
                      onSelected: (value) {
                        if (value == 'participants') {
                          _showRoomParticipants(project);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'participants',
                          child: Row(
                            children: [
                              Icon(Icons.people_outline, size: 18),
                              SizedBox(width: 8),
                              Text('참여인원보기'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_isAdminUser)
                      IconButton(
                        icon:  const Icon(Icons.add, color: Colors.white),
                        onPressed: _addRoom,
                        tooltip: '방 생성',
                      ),
                    IconButton(
                      icon: Icon(
                        _isRoomInfoPanelOpen
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                        color: Colors.white,
                      ),
                      onPressed: () => setState(() {
                        _isRoomInfoPanelOpen = !_isRoomInfoPanelOpen;
                        hiveService.saveRoomInfoPanelOpen(_isRoomInfoPanelOpen);
                      }),
                      tooltip: _isRoomInfoPanelOpen
                          ? '방 채팅 패널 닫기'
                          : '방 채팅 패널 열기',
                    ),
                  ],
                ),


              ],
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: _isRoomInfoPanelOpen ? _infoPanelWidth : 0,
                  child: GestureDetector(
                    onSecondaryTapUp: _showRoomContextMenuEmpty,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        border: Border(
                          left: BorderSide(color: Colors.grey[800]!),
                        ),
                      ),
                      child: project.roomsAll.isEmpty
                            ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox,
                                size: 60,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '방이 없습니다',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_isAdminUser)
                                IconButton(
                                  onPressed: _addRoom,
                                  icon: Icon(Icons.add, size: 32, color: Colors.grey.shade400),
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.all(12),
                                    backgroundColor: Colors.grey.withValues(alpha: 0.15),
                                    shape: CircleBorder(),
                                  ),
                                ),
                            ],
                          ),
                        )
                            : ListView.builder(
                          itemCount: project.roomsAll.length,
                          padding: const EdgeInsets.all(8),
                          itemBuilder: (context, index) {
                            final room = project.roomsAll[index];
                            // final isRoomSelected = _selectedRoomId == room.id;
                            final isRoomSelectedIndex = _selectedRoomIndex == index;

                            return GestureDetector(
                              // onTap: () => {print('tap')},
                              onSecondaryTapUp: (details) => _showRoomContextMenu(details, index),
                              child: Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                color: isRoomSelectedIndex
                                    ? Colors.green.shade700
                                    : Colors.grey[850],
                                child: ListTile(
                                  // leading: Icon(
                                  //   Icons.meeting_room,
                                  //   color: isRoomSelectedIndex
                                  //       ? Colors.white
                                  //       : Colors.green.shade300,
                                  // ),
                                  title: Text(
                                    room.name,
                                    style: TextStyle(
                                      color: isRoomSelectedIndex
                                          ? Colors.white
                                          : Colors.grey[300],
                                      fontWeight: isRoomSelectedIndex
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _isAdminUser
                                        ? _getTrackNameForRoom(project, room.id)
                                        : (_myAuthRoomIds.contains(room.id)
                                            ? '권한 있음'
                                            : '권한 없음'),
                                    style: TextStyle(
                                      color: _isAdminUser
                                          ? Colors.grey[600]
                                          : (_myAuthRoomIds.contains(room.id)
                                              ? Colors.green.shade300
                                              : Colors.grey[600]),
                                      fontSize: 11,
                                    ),
                                  ),
                                  trailing: isRoomSelectedIndex
                                      ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                  )
                                      : const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                                  onTap: () => _selectRoom(room.id, index),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _infoPanelWidth,
                  child: Offstage(
                    offstage: !_isRoomInfoPanelOpen,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        border: Border(
                          left: BorderSide(color: Colors.grey[800]!),
                        ),
                      ),
                      child: _buildRoomSlideInfoPanel(project),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );

  }


  Widget _buildRoomSlideInfoPanel(TimelineProject project){
    // 선택된 방 찾기
    // final selectedRoom = _selectedRoomId != null
    //     ? project.roomsAll.firstWhere(
    //       (room) => room.id == _selectedRoomId,
    //   orElse: () => Room(id: '', name: '', createdAt: DateTime.now()),
    // )
    //     : null;

    final selectedRoom = _selectedRoomIndex != null
        ? project.roomsAll[_selectedRoomIndex!]
        : null;

    // if (selectedRoom == null || selectedRoom.id.isEmpty) {
    if (selectedRoom == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app,
              size: 60,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              '방을 선택하세요',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if(_isRoomLoading){
      return
        // const Expanded(
        // child:
        const Center(
          child: CircularProgressIndicator(),
        );
      // );
    }

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 방 이름
          Row(
            children: [
              Icon(
                Icons.meeting_room,
                color: Colors.green.shade300,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedRoom.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),


              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [

                  if (_isAdminUser || _myAuthRoomIds.contains(selectedRoom.id))
                    IconButton(
                      icon:  const Icon(Icons.mode, color: Colors.white),
                      onPressed: _updateRoom,
                      tooltip: '방 수정',
                    ),
                  const SizedBox(width: 8),
                  if (_isAdminUser)
                    IconButton(
                      icon:  const Icon(Icons.delete, color: Colors.white),
                      onPressed: _deleteRoom,
                      tooltip: '방 삭제',
                    ),

                ],
              )
            ],
          ),
          const SizedBox(height: 16),

          // 방 ID
          _buildInfoRow(
            icon: Icons.fingerprint,
            label: 'Room ID',
            // value: selectedRoom.id,
            value: '${selectedRoom.id.substring(0, 8)}...',
            color: Colors.blue,
          ),

          const SizedBox(height: 12),

          // 트랙/권한 (일반 사용자는 권한 표시)
          _buildInfoRow(
            icon: Icons.playlist_play,
            label: _isAdminUser ? '해당 방 트랙' : '방 편집 권한',
            value: _isAdminUser
                ? _getTrackNameForRoom(project, selectedRoom.id)
                : (_myAuthRoomIds.contains(selectedRoom.id) ? '권한 있음' : '권한 없음'),
            color: _isAdminUser
                ? Colors.orange
                : (_myAuthRoomIds.contains(selectedRoom.id) ? Colors.green : Colors.redAccent),
          ),

          const SizedBox(height: 12),

          // 생성일 (예시, Room 모델에 createdAt이 있다면)
          _buildInfoRow(
            icon: Icons.calendar_today,
            label: '생성일',
            value: DateFormat('yyyy-MM-dd').format(selectedRoom.createdAt),
            color: Colors.purple,
          ),

          const SizedBox(height: 16),


          Expanded(
              child: RoomSlideChatWidget(
                roomId: project.roomsAll[_selectedRoomIndex!].id,
                username: 'Admin',
                joinedMembers: _members,
                key: ValueKey(project.roomsAll[_selectedRoomIndex!].id),
                // initMessages: _messages,
              )
          )




        ],
      ),
    );
  }

  // ✅ 정보 행 위젯
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ★★★ 추가: 이벤트 리스너 정리 메서드 ★★★
  void _disposeEventListener() {
    print('🧹 _disposeEventListener 호출됨, 정리할 _subs: ${_subs.length}개');

    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    print('🧹 이벤트 리스너 ${_subs.length}개 정리 완료');
  }

  @override
  void dispose() {
    _removeProjectContextMenu();
    _removeProjectDragOverlay();
    if (_dropAnim != null && _dropAnimListener != null) {
      _dropAnim!.removeListener(_dropAnimListener!);
    }
    _projectDropAnimController?.dispose();
    _dragProjectPositionNotifier.dispose();
    // 모든 컨트롤러 dispose
    for (var project in projects) {
      project.controller.dispose();
    }

    socketService.leaveRoom();

    _disposeEventListener();

    super.dispose();
  }

}