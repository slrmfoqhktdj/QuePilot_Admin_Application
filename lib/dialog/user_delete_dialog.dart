import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';

class DeleteUserDialog extends StatefulWidget {
  final User user;
  final Function() onUserDeleted;

  const DeleteUserDialog({
    Key? key,
    required this.user,
    required this.onUserDeleted,
  }) : super(key: key);

  @override
  State<DeleteUserDialog> createState() => _DeleteUserDialogState();
}

class _DeleteUserDialogState extends State<DeleteUserDialog> {
  final socketService = SocketService();

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController(text: '0000');

  bool _isDeleting = false;
  // bool _createDefaultTracks = true;


  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _deleteUser() async {

    setState(() {
      _isDeleting = true;
    });

    socketService.deleteUser(widget.user.id, (success) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onUserDeleted();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자 삭제 실패')),
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
          Text('사용자 삭제'),
        ],
      ),
      content: Text('${widget.user.name} 유저를 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isDeleting ? null : _deleteUser,
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