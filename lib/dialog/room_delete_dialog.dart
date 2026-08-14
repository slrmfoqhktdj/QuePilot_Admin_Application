import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class DeleteRoomDialog extends StatefulWidget {
  final String roomId;
  final String roomName;
  final Function() onRoomDeleted;

  const DeleteRoomDialog({
    Key? key,
    required this.roomId,
    required this.roomName,
    required this.onRoomDeleted,
  }) : super(key: key);

  @override
  State<DeleteRoomDialog> createState() => _DeleteRoomDialogState();
}

class _DeleteRoomDialogState extends State<DeleteRoomDialog> {
  final socketService = SocketService();

  bool _isDeleting = false;
  // bool _createDefaultTracks = true;


  @override
  void dispose() {

    super.dispose();
  }

  void _createTimeline() async {

    setState(() {
      _isDeleting = true;
    });

    socketService.deleteRoom(widget.roomId.trim(), (success) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onRoomDeleted();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방 삭제 실패')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delete, color: Colors.blue),
          SizedBox(width: 12),
          Text('방 삭제'),
        ],
      ),
      content: Text('방 ${widget.roomName}를 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isDeleting ? null : _createTimeline,
          icon: _isDeleting
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.delete),
          label: Text(_isDeleting ? '삭제 중...' : '삭제'),
        ),
      ],
    );
  }
}