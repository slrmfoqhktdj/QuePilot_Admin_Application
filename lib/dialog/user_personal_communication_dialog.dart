import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';
import 'dart:async';

class UserPersonalCommunicationDialog extends StatefulWidget {
  final User targetUser;
  final VoidCallback onClose;

  const UserPersonalCommunicationDialog({
    required this.targetUser,
    required this.onClose,
    Key? key,
  }) : super(key: key);

  @override
  State<UserPersonalCommunicationDialog> createState() => _UserPersonalCommunicationDialogState();
}

class _UserPersonalCommunicationDialogState extends State<UserPersonalCommunicationDialog> {
  final SocketService socketService = SocketService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<StreamSubscription> _subs = [];
  final List<MessageData> _messages = [];

  bool _isMinimized = false;
  bool _isTyping = false;
  Timer? _typingTimer;

  Offset _position = const Offset(50, 50);

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _loadMessageHistory();
  }

  void _setupListeners() {
    // 메시지 수신
    _subs.add(socketService.receivePersonalMessage.listen((messageData) {
      if (!mounted) return;

      setState(() {
        _messages.add(messageData);
      });

      _scrollToBottom();
    }));

    // 읽음 확인 수신
    // widget.socketService.onMessageReadReceipt((messageId, readBy, readAt) {
    //   if (!mounted) return;
    //
    //   setState(() {
    //     final index = _messages.indexWhere((m) => m.messageId == messageId);
    //     if (index != -1) {
    //       _messages[index] = _messages[index].copyWith(
    //         isRead: true,
    //         readAt: DateTime.parse(readAt),
    //       );
    //     }
    //   });
    // });

    // 타이핑 중 표시
    // widget.socketService.onUserTyping((userId, userName, isTyping) {
    //   if (!mounted) return;
    //
    //   if (userId == widget.targetUser.id) {
    //     setState(() {
    //       _isTyping = isTyping;
    //       _typingUserName = userName;
    //     });
    //   }
    // });
  }

  void _loadMessageHistory(){
    socketService.getPersonalMessages(widget.targetUser.id, (list) {

      if(mounted){
        List<MessageData> m = list.map((e) => MessageData.fromJson({...e,'fromUsername':e['fromUserId'] == widget.targetUser.id ? widget.targetUser.name : socketService.name})).toList();

        setState(() {
          _messages.addAll(m);
        });

        _scrollToBottom();
      }
    });
  }

  // void _loadMessageHistory() {
  //   widget.socketService.getMessageHistory(
  //     widget.targetUser.id,
  //     callback: (success, messages, hasMore) {
  //       if (success && mounted) {
  //         setState(() {
  //           _messages.clear();
  //           _messages.addAll(
  //             messages.map((m) => MessageData.fromJson(m)).toList(),
  //           );
  //         });
  //
  //         _scrollToBottom();
  //       }
  //     },
  //   );
  // }

  void _sendPersonalMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    socketService.sendPersonalMessage(
      widget.targetUser.id,
      message,
      (success, data) {
        if (mounted) {
          final sentMessage = MessageData.fromJson(data);

          setState(() {
            _messages.add(sentMessage);
          });

          _messageController.clear();
          _scrollToBottom();

          // widget.socketService.sendTypingIndicator(widget.targetUser.id, false);
        }
      },
    );
  }

  // void _onTextChanged(String text) {
  //   if (text.isNotEmpty) {
  //     widget.socketService.sendTypingIndicator(widget.targetUser.id, true);
  //
  //     _typingTimer?.cancel();
  //     _typingTimer = Timer(const Duration(seconds: 3), () {
  //       widget.socketService.sendTypingIndicator(widget.targetUser.id, false);
  //     });
  //   } else {
  //     widget.socketService.sendTypingIndicator(widget.targetUser.id, false);
  //     _typingTimer?.cancel();
  //   }
  // }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    for(final sub in _subs){
      sub.cancel();
    }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              _position.dx + details.delta.dx,
              _position.dy + details.delta.dy,
            );
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 320,
            height: _isMinimized ? 60 : 400,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade300, width: 2),
            ),
            child: Column(
              children: [
                _buildHeader(),
                if (!_isMinimized) ...[
                  Expanded(child: _buildMessageList()),
                  if (_isTyping) _buildTypingIndicator(),
                  _buildInputField(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white,
            child: Text(
              widget.targetUser.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.targetUser.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isMinimized ? Icons.expand_less : Icons.expand_more,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _isMinimized = !_isMinimized;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return Container(
      color: Colors.grey.shade50,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isMine = msg.fromUserId == socketService.userId;
          return _buildMessageBubble(msg, isMine);
        },
      ),
    );
  }

  Widget _buildMessageBubble(MessageData msg, bool isMine) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.message, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(msg.timestamp),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
                // if (isMine) ...[
                //   const SizedBox(width: 4),
                //   Icon(
                //     Icons.done_all,
                //     size: 12,
                //     color: msg.isRead ? Colors.blue : Colors.grey,
                //   ),
                // ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Text(
            '${widget.targetUser.name}님이 입력 중...',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              // onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: '메시지 입력...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _sendPersonalMessage(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendPersonalMessage,
          ),
        ],
      ),
    );
  }
}