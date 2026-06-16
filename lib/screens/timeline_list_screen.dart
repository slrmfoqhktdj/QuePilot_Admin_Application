import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:que_pilot_admin_01/dialog/room_add_dialog.dart';
import 'package:que_pilot_admin_01/models/timeline_project_list_model.dart';
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
import '../widgets/room_slide_call_widget.dart';
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

class _TimelineListScreenState extends State<TimelineListScreen> {
  final socketService = SocketService();
  final List<StreamSubscription> _subs = [];
  List<TimelineProject> projects = [];

  final double _leftProjectListPanelWidth = 280;      // 왼쪽 프로젝트 리스트 칸 넓이
  final double _rightRoomSlidePanelWidth = 600;       // 오른쪽 채팅 및 룸 목록 칸 넓이

  int? _selectedProjectIndex;
  final hiveService = HiveService();

  int? _selectedRoomIndex;

  // List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];

  bool _isReordering = false; //드래그 여부
  bool _isProjectLoading = true;  //프로젝트 로딩
  bool _isRoomLoading = false;     // 방 로딩

  String UserName = "Admin";


  // ★ 추가: 요청 무효화용 변수
  int _projectSelectRequestId = 0;       // 프로젝트 선택 요청 ID
  bool _isProjectSwitching = false;       // 프로젝트 전환 중 플래그
  int _roomSelectRequestId = 0;           // 방 선택 요청 ID
  bool _isRoomSwitching = false;          // 방 전환 중 플래그

  @override
  void initState()  {
    super.initState();
    // _setupEventListeners();

    _loadProjectList((){
      setState(() { _isProjectLoading = false; });
    });






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

    _subs.add(socketService.trackAdded.listen((data) {
      print('📥 Track 업데이트 수신: ${data}');

      if (mounted) {
        setState(() {
          _selectProjectControllerById(data.projectId)?.addTrack(Track.fromJson(data.track));
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
      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.seekTo(data.currentTime);
        _controller.play();
      }
    }));

    _subs.add(socketService.onPauseStream.listen((data) {
      print('onPause');
      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.pause();
        _controller.seekTo(data.currentTime);
      }
    }));

    _subs.add(socketService.onStopStream.listen((data) {
      print('onStop');
      TimelineController? _controller = _selectProjectControllerById(data.projectId);

      if(_controller != null){
        _controller.stop();
      }
    }));

    _subs.add(socketService.timelineHeartbeat.listen((data) {
      print('onTimelineHeartBeat');
      if(data.isPlaying){
        // 진행 시간 조절
        TimelineController? _controller = _selectProjectControllerById(data.projectId);

        if(_controller != null){
          _controller.seekTo(data.currentTime);

          //만약  플레이가 되지 않는 상태라면. 플레이를 눌러놓고 다른 창을 갔다 온경우
          if(!_controller.isPlaying){
            _controller.play();
          }
        }
      }
    }));

    _subs.add(socketService.roomCreated.listen((data) {
      setState(() {
        projects[_selectedProjectIndex!].roomsAll.add(Room(id: data.roomId, name: data.roomName, createdAt: data.createdAt));
        projects[_selectedProjectIndex!].roomsWithoutTrack.add(Room(id: data.roomId, name: data.roomName, createdAt: data.createdAt));
      });
    }));

    _subs.add(socketService.roomUpdated.listen((data) {
      setState(() {
        projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!] = Room(id: data.roomId, name: data.roomName, createdAt: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].createdAt);
      });
    }));

    _subs.add(socketService.roomDeleted.listen((data) {
      setState(() {
        if(projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id == data.roomId) _selectedRoomIndex = null; socketService.leaveRoom();
        projects[_selectedProjectIndex!].roomsAll.removeWhere((room) => room.id == data.roomId);
        projects[_selectedProjectIndex!].roomsWithoutTrack.removeWhere((room) => room.id == data.roomId);
      });
    }));

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
    if (_isReordering) return;// 드래그중 선택 방지
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

    setState(() {_isProjectSwitching = true; _selectedProjectIndex = null;});

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

          _setupEventListener();
          print('onConnected');
          setState(() {
            _isProjectSwitching = false;
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

    });
  }



  void _addTracks() {

    if(projects[_selectedProjectIndex!].roomsWithoutTrack.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('타임라인을 추가할 그룹이 없습니다.')),
      );

      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddTrackDialog(
        projectId: projects[_selectedProjectIndex!].id,
        roomList: projects[_selectedProjectIndex!].roomsWithoutTrack,
        onTimelineAdded: (data) {
          // _loadTimeLine();

          projects[_selectedProjectIndex!].controller.addTrack(Track.fromJson(data));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('타임라인이 추가되었습니다')),
          );
        },
      ),
    );

  }

  void _updateProject() {

    showDialog(
      context: context,
      builder: (context) => UpdateProjectDialog(
        projectId: projects[_selectedProjectIndex!].id,
        projectName: projects[_selectedProjectIndex!].name,
        duration: projects[_selectedProjectIndex!].duration,
        // fps: projects[_selectedProjectIndex!].fps,
        onProjectUpdated: (name, duration) {
          // _loadTimeLine();
          setState(() {

            projects[_selectedProjectIndex!].name = name;
            projects[_selectedProjectIndex!].duration = duration;
            // projects[_selectedProjectIndex!].fps = fps;
            projects[_selectedProjectIndex!].controller.updateProjectInfo(name, duration.toDouble());

          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트가 수정되었습니다')),
          );

        },
      ),
    );

  }

  void _deleteProject() {

    showDialog(
      context: context,
      builder: (context) => DeleteProjectDialog(
        projectId: projects[_selectedProjectIndex!].id,
        projectName: projects[_selectedProjectIndex!].name,
        onProjectDeleted: (data) {
          // _loadTimeLine(null);

          setState(() {
            // if (_selectedRoomIndex != null) _selectedRoomIndex = null;

            projects.removeAt(_selectedProjectIndex!);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트가 삭제되었습니다')),
          );
        },
      ),
    );

  }

  void _addProject() {

    showDialog(
      context: context,
      builder: (context) => AddProjectDialog(
        onProjectAdded: (data) {
          // _loadTimeLine(null);
          setState(() {
            projects.add(TimelineProject.fromJson(data));
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트가 생성되었습니다')),
          );
        },
      ),
    );
  }

  void _sendWholeMessage() {

    showDialog(
      context: context,
      builder: (context) => MessageWholeDialog(
        onMessageSended: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('메시지가 전송되었습니다')),
          );
        },
      ),
    );
  }


  // void _leaveRoom() {
  //   socketService.leaveRoom();
  //   Navigator.of(context).pop();
  // }


  void _addRoom(){
    showDialog(
      context: context,
      builder: (context) => AddRoomDialog(
        onRoomAdded: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방이 생성되었습니다')),
          );
        },
      ),
    );
  }

  void _updateRoom(){
    showDialog(
      context: context,
      builder: (context) => UpdateRoomDialog(
        roomId: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id,
        roomName: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].name,
        onRoomUpdated: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방이 수정되었습니다')),
          );
        },
      ),
    );
  }

  void _deleteRoom(){
    showDialog(
      context: context,
      builder: (context) => DeleteRoomDialog(
        roomId: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].id,
        roomName: projects[_selectedProjectIndex!].roomsAll[_selectedRoomIndex!].name,
        onRoomDeleted: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방이 삭제되었습니다')),
          );
        },
      ),
    );
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
  void _reorderProjects(int oldIndex, int newIndex) {
    setState(() {
      _isReordering = true;

      // ReorderableListView의 newIndex 조정
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }

      // 리스트에서 아이템 이동
      final project = projects.removeAt(oldIndex);
      projects.insert(newIndex, project);

      hiveService.projectIndexSave(project.id, newIndex);


      // 선택된 인덱스 업데이트
      if (_selectedProjectIndex != null) {
        if (_selectedProjectIndex == oldIndex) {
          _selectedProjectIndex = newIndex;
        } else if (oldIndex < _selectedProjectIndex! && newIndex >= _selectedProjectIndex!) {
          _selectedProjectIndex = _selectedProjectIndex! - 1;
        } else if (oldIndex > _selectedProjectIndex! && newIndex <= _selectedProjectIndex!) {
          _selectedProjectIndex = _selectedProjectIndex! + 1;
        }
      }
    });



    // 드래그 완료 후 잠시 후 플래그 해제
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isReordering = false;
        });
      }
    });
  }



  //프로젝트 시작
  void sendProjectPlay(String projectId){
    socketService.sendPlay(projectId, (success)=>{
      if(!success){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재생명령에 실패했습니다. 서버와 연결이 되었는지 확인해주세요.')),
        )
      }
    });
  }

  //프로젝트 정지
  void sendProjectStop(String projectId){
    socketService.sendStop(projectId, (success)=>{
      if(!success){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재생명령에 실패했습니다. 서버와 연결이 되었는지 확인해주세요.')),
        )
      }
    });
  }

  //프로젝트 일시정시
  void sendProjectPause(String projectId){
    socketService.sendPause(projectId, (success)=>{
      if(!success){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재생명령에 실패했습니다. 서버와 연결이 되었는지 확인해주세요.')),
        )
      }
    });
  }


  // void _toggleRoomPanel() {
  //   setState(() {
  //     _isRoomPanelOpen = !_isRoomPanelOpen;
  //   });
  // }

  void _selectRoom(String roomId, int index) async {

    if(_selectedRoomIndex == index) return;

    // ★ 이전 방 요청 무효화
    _roomSelectRequestId++;
    final thisRoomRequestId = _roomSelectRequestId;

    setState(() {
      _isRoomLoading = true;
    });

    // socketService.leaveRoom();
    socketService.leaveRoom();

    // 프레임 대기 (dispose 완료 보장)
    await Future.delayed(const Duration(milliseconds: 100));

    // ★ 대기 후에도 유효한지 확인
    if (thisRoomRequestId != _roomSelectRequestId) {
      print('⚠️ 방 선택 요청 무효화됨');
      return;
    }

    socketService.joinRoom(roomId, UserName, (success, members) {
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: const Row(
            children: [
              Icon(Icons.folder, color: Colors.white),
              SizedBox(width: 12),
              Text(
                '프로젝트 목록',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
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
            // CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('프로젝트가 없습니다',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),),
          ],
        ),
      )
          : Row(
        children: [
          // 왼쪽: 프로젝트 리스트
          Container(
            width: _leftProjectListPanelWidth,
            color: Colors.grey[900],
            child: Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: projects.length,
                    onReorder: _reorderProjects,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      //드래그 중인 아이템 스타일
                      return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child){
                            return Material(
                              elevation: 8,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              child: child,
                            );
                          },
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final isSelected = _selectedProjectIndex == index;
                
                      return ReorderableDragStartListener(
                        key: ValueKey(project.id),
                        index: index,
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: isSelected
                              ? Colors.blue.shade700
                              : Colors.grey[850],
                          child: ListTile(
                            leading: Icon(
                              Icons.movie,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.blue.shade300,
                            ),

                            title: Text(
                              project.name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[300],
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: ${project.duration}s',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey[600],
                            ),
                            onTap: () => _selectProjectList(index),
                          ),
                        ),
                      );
                    }
                  ),
                ),
              ],
            ),
          ),

          // 구분선
          Container(
            width: 1,
            color: Colors.grey[800],
          ),

          // 오른쪽: 타임라인 뷰

          _isProjectLoading?
              const Expanded(
                child: Center(
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
                ),
              )
              : Expanded(
            child: _isProjectSwitching
                ? const Center(             // ✅ 프로젝트 전환 중 로딩
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
                    '왼쪽에서 프로젝트를 선택하세요',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
                :
            // Stack(
            //   children: [
            //     _buildTimelineView(projects[_selectedProjectIndex!]),
            //
            //     // ✅ 오버레이 (패널 열릴 때만 표시)
            //     if (_isRoomPanelOpen)
            //       Positioned.fill(
            //         child: GestureDetector(
            //           onTap: _toggleRoomPanel,
            //           child: Container(
            //             color: Colors.black.withValues(alpha: 0.5),
            //           ),
            //         ),
            //       ),
            //
            //     // ✅ 방 슬라이드 패널
            //     _buildRoomSlidePanel(projects[_selectedProjectIndex!]),
            //   ],
            // )




            // LayoutBuilder(builder: (context, Constraints){
            //   return SizedBox(
            //     width: Constraints.maxWidth,
            //     height: Constraints.maxHeight,
            //     child: Stack(
            //       clipBehavior: Clip.none,
            //       children: [
            //         _buildTimelineView(projects[_selectedProjectIndex!]),
            //       ],
            //     ),
            //   );
            // })
              _buildTimelineView(projects[_selectedProjectIndex!]),

          ),

          // ✅ 오른쪽 슬라이드 패널 (방 목록)
          // if (_selectedProjectIndex != null)
          //   _buildRoomSlidePanel(projects[_selectedProjectIndex!]),
        ],
      ),
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
                    Row(
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
                          label: '${project.duration}s',
                          color: Colors.blue,
                        ),
                        // const SizedBox(width: 8),
                        // _buildInfoChip(
                        //   icon: Icons.speed,
                        //   label: '${project.fps} FPS',
                        //   color: Colors.green,
                        // ),
                        const SizedBox(width: 8),
                        // IconButton(
                        //   icon: const Icon(Icons.refresh, color:Colors.white ,),
                        //   onPressed: () => _selectProjectList(_selectedProjectIndex!),
                        //   tooltip: '새로고침',
                        // ),
                        // const SizedBox(width: 8,),
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

                        )

                        ,

                      ],
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
            child: Row(
              children: [
                Expanded(
                    // flex: 7,
                    child: TimelineWidget(controller: project.controller, sendPlay: () => sendProjectPlay(project.id), sendStop: () => sendProjectStop(project.id), sendPause: () => sendProjectPause(project.id),),
                ),

                SizedBox(
                  width: _rightRoomSlidePanelWidth,
                  child: _buildRoomSlidePanel(project),
                )
              ],
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

  Widget _buildRoomSlidePanel(TimelineProject project) {



    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(
          left: BorderSide(color: Colors.grey[800]!),
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
                const Icon(
                  Icons.meeting_room,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(

                  child: Text(
                    '방 목록 (${project.roomsAll.length}개)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // IconButton(
                //   icon: const Icon(Icons.close, color: Colors.white),
                //   onPressed: _toggleRoomPanel,
                //   tooltip: '닫기',
                // ),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon:  const Icon(Icons.add, color: Colors.white),
                      onPressed: _addRoom,
                      tooltip: '방 생성',
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      border: Border(
                        left: BorderSide(color: Colors.grey[800]!),
                      ),
                      // boxShadow: [
                      //   BoxShadow(
                      //     color: Colors.black.withValues(alpha: 0.5),
                      //     blurRadius: 10,
                      //     offset: const Offset(-5, 0),
                      //   ),
                      // ],
                    ),
                    child: Column(
                      children: [
                        // ✅ 방 목록
                        Expanded(
                          flex: 5,
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

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                color: isRoomSelectedIndex
                                    ? Colors.green.shade700
                                    : Colors.grey[850],
                                child: ListTile(
                                  leading: Icon(
                                    Icons.meeting_room,
                                    color: isRoomSelectedIndex
                                        ? Colors.white
                                        : Colors.green.shade300,
                                  ),
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
                                    'ID: ${room.id.substring(0, 8)}...',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                  )
                                  ,
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
                              );
                            },
                          ),
                        ),
                        Expanded(
                            flex: 5,
                            child: _buildRoomSlideCallPanel(project),
                        )

                      ],
                    ),
                  ),
                ),

                Expanded(
                    flex:6,
                    child: _buildRoomSlideInfoPanel(project),
                ),
              ],
            ),
          )
        ],
      ),
    );

  }


  Widget _buildRoomSlideCallPanel(TimelineProject project){
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
      child: RoomSlideCallWidget(
        roomId: project.roomsAll[_selectedRoomIndex!].id,
        username: 'Admin',
        joinedMembers: _members,
        key: ValueKey(project.roomsAll[_selectedRoomIndex!].id),
        // initMessages: _messages,
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

                  IconButton(
                    icon:  const Icon(Icons.mode, color: Colors.white),
                    onPressed: _updateRoom,
                    tooltip: '방 편집',
                  ),
                  const SizedBox(width: 8),
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

          // 트랙 개수 (예시)
          _buildInfoRow(
            icon: Icons.playlist_play,
            label: '해당 방 트랙',
            value: _getTrackNameForRoom(project, selectedRoom.id),
            color: Colors.orange,
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
                // joinedMembers: _members,
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

  @override
  void dispose() {
    // 모든 컨트롤러 dispose
    for (var project in projects) {
      project.controller.dispose();
    }

    socketService.leaveRoom();

    for(final sub in _subs){
      sub.cancel();
    }

    super.dispose();
  }

}