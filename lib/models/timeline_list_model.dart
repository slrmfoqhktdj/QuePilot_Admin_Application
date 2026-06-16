// 프로젝트 모델 클래스
import 'package:que_pilot_admin_01/db/hive_service.dart';
import 'package:que_pilot_admin_01/models/timeline_track_model.dart';

import '../controllers/timeline_controller.dart';
import './timeline_room_model.dart';

class TimelineProject {
  final String id;
  String _name;
  int _duration;
  // int _fps;
  final int? index;
  final DateTime createdAt;
  List<Room>? _roomsWithoutTrack;
  List<Room>? _roomsAll;
  TimelineController? _controller;

  TimelineProject({
    required this.id,
    required String name,
    required int duration,
    // required int fps,
    this.index,
    required this.createdAt,
    List<Room>? roomsWithoutTrack,
    List<Room>? roomsAll,
    TimelineController? controller,
  }): _name = name, _duration = duration, _roomsWithoutTrack = roomsWithoutTrack, _roomsAll = roomsAll, _controller = controller;

  String get name => _name;
  set name(String value){
    _name = value;
  }

  int get duration => _duration;
  set duration(int value){
    _duration = value;
  }

  // int get fps => _fps;
  // set fps(int value){
  //   _fps = value;
  // }

  List<Room> get roomsWithoutTrack => _roomsWithoutTrack ?? [];
  set roomsWithoutTrack(List<Room> value) {
    _roomsWithoutTrack = value;
  }

  List<Room> get roomsAll => _roomsAll ?? [];
  set roomsAll(List<Room> value) {
    _roomsAll = value;
  }

  TimelineController get controller => _controller ?? TimelineController() ;
  set controller(TimelineController value) {
    _controller = value;
  }

  factory TimelineProject.fromJson(Map<String, dynamic> json) {
    final controller = TimelineController();
    final hiveservice = HiveService();

    // 타임라인 데이터를 컨트롤러에 로드
    final timelineData = {
      'duration': (json['duration'] as num).toDouble(),
      // 'fps': json['fps'] as int,
      'tracks': json['tracks'] as List<dynamic>? ?? [],
      'id':json['id'] as String,
      'created_at':json['created_at'] as String,
      // 'room_id':json['room_id'] as String,
    };

    // print('timelines');
    // print(timelineData);

    controller.loadFromMap(timelineData);

    //rooms 파싱

    List<Room> roomsList = [];



    if(json['rooms'] != null){
      final roomsJson = json['rooms'] as List<dynamic>;
      // print(roomsJson);
      roomsList = roomsJson.where((room) => room['id'] != timelineData['id']).map((room) => Room.fromJson(room as Map<String, dynamic>)).toList();

    }

    List<Room> roomsListForWithoutTrack = List.from(roomsList);
    roomsListForWithoutTrack.add(new Room(id: json['id'] as String, name: "프로젝트 트랙", createdAt: DateTime.parse(json['created_at'] as String)));


    List<Track> tracksList = [];
    if(json['tracks'] != null){
      final tracksJson = json['tracks'] as List<dynamic>;
      tracksList = tracksJson.map((track) => Track.fromJson(track as Map<String, dynamic>)).toList();
    }

    Set<String> trackIds = tracksList.map((item) => item.room_id).toSet();

    List<Room> returnRoomList = roomsListForWithoutTrack.where((item) => !trackIds.contains(item.id)).toList();

    // print("getProjectList : ${json['name'] as String} : ${hiveservice.projectIndexRead(json['id'], -1)}");


    return TimelineProject(
      id: json['id'] as String,
      name: json['name'] as String,
      duration: json['duration'] as int,
      // fps: json['fps'] as int,
      index: hiveservice.projectIndexRead(json['id'], -1),
      createdAt: DateTime.parse(json['created_at'] as String),
      roomsWithoutTrack: returnRoomList,
      roomsAll: roomsList,
      controller: controller,
    );
  }
}