import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';

class MessageWholeDialog extends StatefulWidget {
  final Function() onMessageSended;

  const MessageWholeDialog({
    Key? key,
    required this.onMessageSended,
  }) : super(key: key);

  @override
  State<MessageWholeDialog> createState() => _MessageWholeDialogState();
}

class _MessageWholeDialogState extends State<MessageWholeDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _messageController = TextEditingController();

  bool _isSending = false;
  // bool _createDefaultTracks = true;


  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _createTimeline() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    socketService.sendMessageWhole(_messageController.text.trim(), (success) {
      if (mounted) {
        setState(() {
          _isSending = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onMessageSended();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('메시지 생성 실패')),
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
          Icon(Icons.messenger, color: Colors.blue),
          SizedBox(width: 12),
          Text('프로젝트 전체 메시지'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //  메시지 이름
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: '전송할 메세지',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return ' 메시지를 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isSending ? null : _createTimeline,
          icon: _isSending
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.send),
          label: Text(_isSending ? '전송 중...' : '전송'),
        ),
      ],
    );
  }
}