import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';

class UpdateRoomDialog extends StatefulWidget {
  final String roomId;
  final String roomName;

  final Function() onRoomUpdated;

  const UpdateRoomDialog({
    Key? key,
    required this.roomId,
    required this.roomName,
    required this.onRoomUpdated,
  }) : super(key: key);

  static Future<void> showDraggable(
    BuildContext context, {
    required String roomId,
    required String roomName,
    required Function() onRoomUpdated,
  }) {
    return _showDraggableDialog(
      context,
      UpdateRoomDialog(
        roomId: roomId,
        roomName: roomName,
        onRoomUpdated: onRoomUpdated,
      ),
    );
  }

  static Future<void> _showDraggableDialog(BuildContext context, Widget dialog) {
    Offset dialogOffset = Offset.zero;

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dialog',
      barrierColor: Colors.black54,
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: dialogOffset,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setDialogState(() {
                          dialogOffset += details.delta;
                        });
                      },
                      child: dialog,
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

  @override
  State<UpdateRoomDialog> createState() => _UpdateRoomDialogState();
}

class _UpdateRoomDialogState extends State<UpdateRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _nameController = TextEditingController();

  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.roomName;
  }


  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _createTimeline() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    socketService.updateRoom(widget.roomId, _nameController.text.trim(), (success ) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onRoomUpdated();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('방 수정 실패')),
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
          Icon(Icons.add_circle, color: Colors.blue),
          SizedBox(width: 12),
          Text('방 수정'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 방 이름
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '방 이름',
                  hintText: '예: Main Timeline',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '방 이름을 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 기본 트랙 생성 옵션
              // CheckboxListTile(
              //   title: const Text('기본 트랙 생성'),
              //   subtitle: const Text('카메라, BGM 트랙을 자동으로 생성합니다'),
              //   value: _createDefaultTracks,
              //   onChanged: (value) {
              //     setState(() {
              //       _createDefaultTracks = value ?? true;
              //     });
              //   },
              //   controlAffinity: ListTileControlAffinity.leading,
              // ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUpdating ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isUpdating ? null : _createTimeline,
          icon: _isUpdating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.add),
          label: Text(_isUpdating ? '수정 중...' : '수정'),
        ),
      ],
    );
  }
}