import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/socket_service.dart';

class UserAuthDialog extends StatefulWidget {
  final User user;
  final VoidCallback onPermissionUpdated;

  const UserAuthDialog({
    Key? key,
    required this.user,
    required this.onPermissionUpdated,
  }) : super(key: key);

  @override
  State<UserAuthDialog> createState() =>
      _UserAuthDialogState();
}

class _UserAuthDialogState extends State<UserAuthDialog> {
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> auth_rooms = [];
  // Map<String, List<Map<String, dynamic>>> projectRooms = {};
  Map<String, Set<String>> userPermissions = {}; // {projectId: {roomId1, roomId2, ...}}
  // Map<String, dynamic> userPermissions = {};

  // 초기 권한 상태를 저장 (변경사항 추적용)
  Map<String, Set<String>> initialPermissions = {};

  Set<String> updateRoomIds = {};
  Set<String> deleteRoomIds = {};
  bool isLoading = true;

  final socketService = SocketService();

  @override
  void initState() {
    super.initState();
    _loadProjectsAndPermissions();
  }

  // 프로젝트 목록과 현재 유저의 권한 로드
  Future<void> _loadProjectsAndPermissions() async {
    setState(() => isLoading = true);

    // 1. 전체 프로젝트 목록 가져오기
    socketService.getRoomListUserAuth((success , RoomList) async {
      if (success) {
        setState(() {
          projects = RoomList;
        });

        //현재 유저의 권한 정보 가져오기
        await _loadUserPermissions();

        setState(() => isLoading = false);

      }else{
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버에서 방 목록을 가져오는데 실패했습니다.')),
        );

        setState(() => isLoading = false);
      }
    });

  }

  // 유저의 현재 권한 정보 가져오기
  Future<void> _loadUserPermissions() async {
    // socketService.getUserAuthList(widget.user['id'], (permissions) {
    //   setState(() {
    //     userPermissions = {};
    //     for (var perm in permissions) {
    //       final projectId = perm['project_id'];
    //       final roomId = perm['room_id'];
    //       if (!userPermissions.containsKey(projectId)) {
    //         userPermissions[projectId] = {};
    //       }
    //       userPermissions[projectId]!.add(roomId);
    //     }
    //   });
    // });

    socketService.getUserAuthList(widget.user.id, ((success , roomList) async {
        if (success) {
          setState(() {
            auth_rooms = roomList;

            projects.forEach((project){
              if (!userPermissions.containsKey(project['id'])) {
                userPermissions[project['id']] = {};
              }
              project['rooms']!.forEach((roomId){
                roomList.forEach((auth_room){
                  if(roomId['id'] == auth_room['room_id']){
                    userPermissions[project['id']]!.add(roomId['id']);
                  }
                });
              });
            });

            // 초기 권한 상태를 복사해서 저장 (딥 카피)
            initialPermissions = {};
            userPermissions.forEach((projectId, roomIds) {
              initialPermissions[projectId] = Set.from(roomIds);
            });

          });

        }else{
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('서버에서 방 목록을 가져오는데 실패했습니다.')),
          );
        }
      })
    );
  }

  // 권한 토글
  void _togglePermission(String projectId, String roomId) {
    setState(() {

      // if (userPermissions[projectId]!.contains(roomId)) {
      //   userPermissions[projectId]!.remove(roomId);
      //
      // } else {
      //   userPermissions[projectId]!.add(roomId);
      // }

      final hadPermission = userPermissions[projectId]!.contains(roomId);

      if (hadPermission) {
        // 권한 제거
        userPermissions[projectId]!.remove(roomId);

        // 초기에 권한이 있었다면 deleteRoomIds에 추가
        if (initialPermissions[projectId]?.contains(roomId) ?? false) {
          deleteRoomIds.add(roomId);
          // updateRoomIds에서는 제거 (이전에 추가했다가 다시 제거한 경우)
          updateRoomIds.remove(roomId);
        } else {
          // 초기에 권한이 없었는데 추가했다가 다시 제거 → 둘 다에서 제거
          updateRoomIds.remove(roomId);
        }
      } else {
        // 권한 추가
        userPermissions[projectId]!.add(roomId);

        // 초기에 권한이 없었다면 updateRoomIds에 추가
        if (!(initialPermissions[projectId]?.contains(roomId) ?? false)) {
          updateRoomIds.add(roomId);
          // deleteRoomIds에서는 제거 (이전에 삭제했다가 다시 추가한 경우)
          deleteRoomIds.remove(roomId);
        } else {
          // 초기에 권한이 있었는데 삭제했다가 다시 추가 → 원래 상태로 복원
          deleteRoomIds.remove(roomId);
        }
      }

      // 디버그 출력
      // print('=== 권한 변경사항 ===');
      // print('추가될 Room IDs: ${updateRoomIds.toList()}');
      // print('삭제될 Room IDs: ${deleteRoomIds.toList()}');
      // print('====================');


    });
  }

  // 권한 저장
  void _savePermissions() {
    // 권한 데이터를 서버에 전송
    final permissionData = <Map<String, String>>[];
    userPermissions.forEach((projectId, roomIds) {
      for (var roomId in roomIds) {
        permissionData.add({
          'project_id': projectId,
          'room_id': roomId,
        });
      }
    });

    socketService.updateUserAuth(
      widget.user.id,
      updateRoomIds.toList(),
      deleteRoomIds.toList(),
            (success) {
              if(success){
                widget.onPermissionUpdated();
                Navigator.pop(context);
              }else{
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('권한 업데이트 실패')),
                );
              }
            }
    );

    // socketService.updateUserPermissions(
    //   widget.user['id'],
    //   permissionData,
    //       (success) {
    //     if (success) {
    //       widget.onPermissionUpdated();
    //       Navigator.pop(context);
    //     } else {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(content: Text('권한 업데이트 실패')),
    //       );
    //     }
    //   },
    // );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text(
                    widget.user.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.user.name} 권한 관리',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID: ${widget.user.id}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),

            // 안내 텍스트
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '프로젝트별 룸에 대한 접근 권한을 설정하세요',
                      style: TextStyle(color: Colors.grey[300], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 프로젝트/룸 목록
            Expanded(
              child: isLoading
                  ? const Center(
                child: CircularProgressIndicator(),
              )
                  : projects.isEmpty
                  ? Center(
                child: Text(
                  '프로젝트가 없습니다',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              )
                  : ListView.builder(
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final projectId = project['id'];
                  final rooms = projects[index]['rooms'] ?? [];

                  return _buildProjectCard(project, List<Map<String, dynamic>>.from(rooms));
                },
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),

            // 하단 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '취소',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _savePermissions,
                  icon: const Icon(Icons.save),
                  label: const Text('저장'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project, List<Map<String, dynamic>> rooms) {
    final projectId = project['id'];
    final projectName = project['name'] ?? 'Unknown';
    final hasRooms = rooms.isNotEmpty;

    // 전체 선택 여부
    // final allSelected = hasRooms &&
    //     rooms.every((room) =>
    //     userPermissions[projectId]?.contains(room['id']) ?? false);
    final someSelected = hasRooms &&
        rooms.any((room) =>
        userPermissions[projectId]?.contains(room['id']) ?? false);

    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          Icons.folder,
          color: someSelected ? Colors.blue : Colors.grey,
        ),
        title: Text(
          projectName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          '${rooms.length}개의 룸',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        // trailing: hasRooms
        //     ? Checkbox(
        //   value: allSelected,
        //   tristate: true,
        //   onChanged: (value) {
        //     setState(() {
        //       if (value == true) {
        //         // 전체 선택
        //         userPermissions[projectId] =
        //             rooms.map((room) => room['id'] as String).toSet();
        //       } else {
        //         // 전체 해제
        //         userPermissions[projectId] = {};
        //       }
        //     });
        //   },
        // )
        //     : null,
        children: hasRooms
            ? rooms.map((room) => _buildRoomItem(projectId, room)).toList()
            : [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '이 프로젝트에는 룸이 없습니다',
              style: TextStyle(color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomItem(String projectId, Map<String, dynamic> room) {
    final roomId = room['id'];
    final roomName = room['name'] ?? 'Unknown';
    final hasPermission = userPermissions[projectId]?.contains(roomId) ?? false;

    // 초기 상태와 비교하여 변경사항 표시
    final initiallyHadPermission =
        initialPermissions[projectId]?.contains(roomId) ?? false;
    final isAdded = !initiallyHadPermission && hasPermission;
    final isRemoved = initiallyHadPermission && !hasPermission;

    return Container(
      color: Colors.grey[800],
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.only(left: 72, right: 16),
        title: Row(
          children: [
            Expanded(
              child: Text(
                roomName,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            // 변경 상태 표시
            if (isAdded)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green, width: 1),
                ),
                child: const Text(
                  '추가됨',
                  style: TextStyle(color: Colors.green, fontSize: 10),
                ),
              ),
            if (isRemoved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red, width: 1),
                ),
                child: const Text(
                  '삭제됨',
                  style: TextStyle(color: Colors.red, fontSize: 10),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Room ID: $roomId',
          style: TextStyle(color: Colors.grey[500], fontSize: 11),
        ),
        value: hasPermission,
        onChanged: (value) => _togglePermission(projectId, roomId),
        activeColor: Colors.blue,
        secondary: Icon(
          Icons.meeting_room,
          color: hasPermission ? Colors.blue : Colors.grey,
          size: 20,
        ),
      ),
    );
  }
}