import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:que_pilot_admin_01/db/model/hive_key_model.dart';

class HiveService {
  static final HiveService _singleton = HiveService._internal();

  HiveService._internal();

  Box? _projectIndexBox;
  Box? _trackIndexBox;
  Box? _sessionBox;
  Box? _optionBox;

  factory HiveService() {
    return _singleton;
  }

  initHiveManager() async {
    await Hive.initFlutter();

    await openProjectIndex();
    await openTrackIndex();
    await openSession();
    await openOption();
  }

  // Map<dynamic, dynamic>? getProjectAllIndex() {
  //   final orders = <String, int>{};
  //
  //   for (var order in _projectIndexBox!.){
  //     orders[o] = order.
  //   }
  //
  //   return _projectIndexBox?.toMap();
  // }

  Future openProjectIndex() async {
    _projectIndexBox = await Hive.openBox(HiveKeyModel().projectIndexBoxKey);
  }

  Future openTrackIndex() async {
    _trackIndexBox = await Hive.openBox(HiveKeyModel().trackIndexBoxKey);
  }

  Future openSession() async {
    _sessionBox = await Hive.openBox(HiveKeyModel().sessionBoxKey);
  }

  Future openOption() async {
    _optionBox = await Hive.openBox(HiveKeyModel().optionBoxKey);
  }

  Future projectIndexSave(String key, int value) async {
    return _projectIndexBox?.put(key, value);
  }

  Future trackIndexSave(String key, int value) async {
    return _trackIndexBox?.put(key, value);
  }

  Future sessionSave(String key, String value) async {
    return _sessionBox?.put(key, value);
  }

  Future sessionDelete(String key) async {
    return _sessionBox?.delete(key);
  }

  int? projectIndexRead(String key, int? defaultValue) {
    return _projectIndexBox?.get(key, defaultValue: defaultValue);
  }

  int? trackIndexRead(String key, int? defaultValue) {
    return _trackIndexBox?.get(key, defaultValue: defaultValue);
  }

  String? sessionRead(String key, String? defaultValue) {
    return _sessionBox?.get(key, defaultValue: defaultValue);
  }

  Future projectIndexClear() async {
    return _projectIndexBox?.clear();
  }

  Future trackIndexClear() async {
    return _trackIndexBox?.clear();
  }

  // 트랙 순서 전체 읽기 (trackId -> order)
  Map<String, int> getAllTrackOrders() {
    final map = <String, int>{};
    if (_trackIndexBox == null) return map;
    for (var key in _trackIndexBox!.keys) {
      final value = _trackIndexBox!.get(key);
      if (value is int) {
        map[key.toString()] = value;
      }
    }
    return map;
  }

  // 트랙 순서 여러 개 저장
  Future saveTrackOrders(Map<String, int> orders) async {
    if (_trackIndexBox == null) return;
    for (var entry in orders.entries) {
      await _trackIndexBox!.put(entry.key, entry.value);
    }
  }

  // 트랙 순서 하나 저장
  Future trackOrderSave(String trackId, int order) async {
    return _trackIndexBox?.put(trackId, order);
  }

  // 트랙 순서 하나 삭제
  Future trackOrderRemove(String trackId) async {
    return _trackIndexBox?.delete(trackId);
  }

  Future sessionClear() async {
    return _sessionBox?.clear();
  }

  // 코멘트 오프셋 (큐 시작 전 코멘트 표시 시간)
  Future saveCommentOffset(double value) async {
    return _optionBox?.put(HiveKeyModel().commentOffsetKey, value.toString());
  }

  double readCommentOffset() {
    final value = _optionBox?.get(HiveKeyModel().commentOffsetKey);
    if (value != null) {
      return double.tryParse(value.toString()) ?? 2.0;
    }
    return 2.0;
  }

  // 타임라인 줌
  Future saveTimelineZoom(double value) async {
    return _optionBox?.put(HiveKeyModel().timelineZoomKey, value.toString());
  }

  double readTimelineZoom() {
    final value = _optionBox?.get(HiveKeyModel().timelineZoomKey);
    if (value != null) {
      return double.tryParse(value.toString()) ?? 1.0;
    }
    return 1.0;
  }

  // 방 정보 패널 열림/닫힘
  Future saveRoomInfoPanelOpen(bool value) async {
    return _optionBox?.put(HiveKeyModel().roomInfoPanelOpenKey, value.toString());
  }

  bool readRoomInfoPanelOpen() {
    final value = _optionBox?.get(HiveKeyModel().roomInfoPanelOpenKey);
    if (value != null) {
      return value.toString() == 'true';
    }
    return true;
  }

  // 방 패널(방목록+채팅) 폭
  Future saveRoomPanelWidth(double value) async {
    return _optionBox?.put(HiveKeyModel().roomPanelWidthKey, value.toString());
  }

  double readRoomPanelWidth() {
    final value = _optionBox?.get(HiveKeyModel().roomPanelWidthKey);
    if (value != null) {
      return double.tryParse(value.toString()) ?? 600.0;
    }
    return 600.0;
  }

  // 코멘트 패널(확장 시) 높이
  Future saveCommentPanelHeight(double value) async {
    return _optionBox?.put(HiveKeyModel().commentPanelHeightKey, value.toString());
  }

  double readCommentPanelHeight() {
    final value = _optionBox?.get(HiveKeyModel().commentPanelHeightKey);
    if (value != null) {
      return double.tryParse(value.toString()) ?? 360.0;
    }
    return 360.0;
  }

  // 코멘트 패널 확장/축소 상태
  Future saveCommentPanelExpanded(bool value) async {
    return _optionBox?.put(HiveKeyModel().commentPanelExpandedKey, value.toString());
  }

  bool readCommentPanelExpanded() {
    final value = _optionBox?.get(HiveKeyModel().commentPanelExpandedKey);
    if (value != null) {
      return value.toString() == 'true';
    }
    return false;
  }

  // 관리자 표시 이름 (방/채팅에서 보여지는 이름)
  Future saveDisplayName(String value) {
    return _optionBox?.put(HiveKeyModel().displayNameKey, value) ?? Future.value();
  }

  String readDisplayName() {
    final value = _optionBox?.get(HiveKeyModel().displayNameKey);
    return value?.toString() ?? '';
  }
}