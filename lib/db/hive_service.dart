import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:que_pilot_admin_01/db/model/hive_key_model.dart';

class HiveService {
  static final HiveService _singleton = HiveService._internal();

  HiveService._internal();

  Box? _projectIndexBox;
  Box? _trackIndexBox;
  Box? _sessionBox;

  factory HiveService() {
    return _singleton;
  }

  initHiveManager() async {
    await Hive.initFlutter();

    await openProjectIndex();
    await openTrackIndex();
    await openSession();
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

  Future projectIndexSave(String key, int value) async {
    return _projectIndexBox?.put(key, value);
  }

  Future trackIndexSave(String key, int value) async {
    return _trackIndexBox?.put(key, value);
  }

  Future sessionSave(String key, String value) async {
    return _sessionBox?.put(key, value);
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

  Future sessionClear() async {
    return _sessionBox?.clear();
  }
}