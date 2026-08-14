import 'dart:async';

import 'package:flutter/material.dart';
import 'package:que_pilot_admin_01/models/message_model.dart';
import '../services/socket_service.dart';
import 'room_slide_call_widget.dart';

class RoomSlideChatWidget extends StatefulWidget {
  final String roomId;
  final String username;
  final List<Map<String, dynamic>> joinedMembers;
  // final List<Map<String, dynamic>> initMessages;

  const RoomSlideChatWidget({
    Key? key,
    required this.roomId,
    required this.username,
    required this.joinedMembers,
    // required this.initMessages,
  }) : super(key: key);

  @override
  State<RoomSlideChatWidget> createState() => _RoomSlideChatWidgetState();
}

class _RoomSlideChatWidgetState extends State<RoomSlideChatWidget> {
  final socketService = SocketService();
  final List<StreamSubscription> _subs = [];
  List<MessageData> messages = [];
  // List<String> members = [];
  final TextEditingController messageController = TextEditingController();


  @override
  void initState() {
    super.initState();
    print('RoomSlideChatWidget initState');
    _setupEventListeners();

    // _loadRoomMembers();


    // _loadRoomInfo();
    // _loadTimeLine();

    _loadMessageHistory();
  }

  void _setupEventListeners() {

    _subs.add(socketService.userJoined.listen((data) {
      _addMessage(MessageData(fromUserId: data.userId, fromUsername: '[알림]', message: '${data.userName}이 입장했습니다.', timestamp: data.timestamp));
    }));

    _subs.add(socketService.userLeft.listen((data) {
      _addMessage(MessageData(fromUserId: data.userId, fromUsername: '[알림]', message: '${data.userName}이 나갔습니다.', timestamp: data.timestamp));
    }));

    _subs.add(socketService.receiveMessage.listen((data) {
      _addMessage(data);
    }));

    _subs.add(socketService.receiveMessageProjectWhole.listen((data) {
      _addMessage(MessageData(fromUserId: data.fromUserId, fromUsername: '[전체 메시지]', message: data.message, timestamp: data.timestamp));
    }));




  }

  void _loadMessageHistory(){
    socketService.getRoomMessages(widget.roomId, (list) {

      List<MessageData> m = list.map((e) => MessageData.fromJson(e)).toList();

      setState(() {
        messages.addAll(m);
      });
    });
  }

  // void _loadRoomInfo() {
  //   socketService.getRoomInfo(widget.roomId, (roomInfo) {
  //     if (roomInfo != null) {
  //       if(this.mounted) {
  //
  //         print("room info : ${roomInfo['members']}");
  //
  //         setState(() {
  //           members = (roomInfo['members'] as List)
  //               .map((m) => m['userName'].toString())
  //               .toList();
  //
  //
  //         });
  //       }
  //     }
  //   });
  // }


  // void _loadRoomMembers() {
  //   if(this.mounted) {
  //     setState(() {
  //       members = widget.joinedMembers
  //           .map((m) => m['userName'].toString())
  //           .toList();
  //     });
  //   }
  // }

  // void _loadTimeLine() {
  //   socketService.getTimeLine(widget.roomId, (timeline){
  //     if(timeline == null){
  //       print('타임라인을 로드할 수 없습니다.');
  //     }else{
  //       print('타임라인 로드.');
  //       // print(timeline);
  //
  //       timelineController.loadFromMap(timeline);
  //     }
  //   });
  // }

  void _addMessage(MessageData msg) {
    if(this.mounted) {
      setState(() {

        // widget.initMessages.add(message);

        messages.add(msg);
      });
    }
  }

  void _sendMessage() {
    if (messageController.text.isEmpty) return;

    socketService.sendMessage(messageController.text);
    messageController.clear();
  }


  // void _leaveRoom() {
  //   socketService.leaveRoom();
  //   // Navigator.of(context).pop();
  // }



  @override
  Widget build(BuildContext context) {
    return Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 멤버 목록
            // Padding(
            //   padding: const EdgeInsets.all(8.0),
            //   child: Wrap(
            //     children: widget.joinedMembers
            //         .map((member) => Chip(label: Text(member['userName'])))
            //         .toList(),
            //   ),
            // ),
            // 메시지 표시
            Expanded(
              child:
              // 채팅창
              ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text('${messages[index].fromUsername} : ${messages[index].message} - ${messages[index].timestamp.toString()}', style: const TextStyle(color: Colors.white),),
                  );
                },
              ),
            ),

            // 통화 버튼 + 통화중 칩 (메시지 목록과 입력창 사이)
            RoomSlideCallWidget(
              roomId: widget.roomId,
              username: widget.username,
              joinedMembers: widget.joinedMembers,
              key: ValueKey(widget.roomId),
            ),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        hoverColor: Colors.white.withValues(alpha: 0.08),
                      ),
                      child: TextField(
                        controller: messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '메시지 입력',
                          hintStyle: const TextStyle(color: Colors.white54),
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.circular(8)
                    ),

                    child: IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send,color: Colors.white,),
                      tooltip: '전송',
                    ),
                  )

                ],
              ),
            ),


          ],
        )
    );
  }

  @override
  void dispose() {
    print('RoomSlideChatWidget dispose');
    messageController.dispose();
    // _leaveRoom();

    for(final sub in _subs){
      sub.cancel();
    }

    // socketService.offUserJoined();
    //
    // socketService.offUserLeft();
    //
    // socketService.offReceiveMessage();
    //
    // socketService.offReceiveCommand();
    //
    // socketService.offRoomDeleted();
    //
    // socketService.leaveRoom();

    super.dispose();
  }
}
