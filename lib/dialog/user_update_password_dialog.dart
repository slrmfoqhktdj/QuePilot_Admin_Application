import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';

class UpdateUserPasswordDialog extends StatefulWidget {
  final User user;

  const UpdateUserPasswordDialog({
    Key? key,
    required this.user,
  }) : super(key: key);

  @override
  State<UpdateUserPasswordDialog> createState() => _UpdateUserPasswordDialogState();
}

class _UpdateUserPasswordDialogState extends State<UpdateUserPasswordDialog> {
  final socketService = SocketService();

  bool _isPasswordUpdating = false;
  String? _updatedPassword;


  @override
  void dispose() {

    super.dispose();
  }

  void _updateUserPassword() async {

    setState(() {
      _isPasswordUpdating = true;
    });

    socketService.updateUserPassword(widget.user.id, (success, updatedPassword) {
      if (mounted) {
        setState(() {
          _isPasswordUpdating = false;
        });

        if (success) {
          Navigator.pop(context);
          setState(() {
            _updatedPassword = updatedPassword;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User의 비밀번호가 재발급되었습니다')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자 비밀번호 재발급 실패')),
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
          Text('사용자 비밀번호 재발급'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.user.name} 유저의 비밀번호를 재발급하시겠습니까?'),
          const SizedBox(height: 12),
          _updatedPassword != null ? Text('재발급된 비밀번호 : $_updatedPassword') : Container(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isPasswordUpdating ? null : () => Navigator.pop(context),
          child: Text(_updatedPassword != null ? '확인': '취소' ),
        ),
        ElevatedButton.icon(
          onPressed: _isPasswordUpdating ? null :_updateUserPassword,
          icon: _isPasswordUpdating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.delete),
          label: Text(_isPasswordUpdating ? '재발급 중...' : '재발급'),
        ),

      ],
    );
  }
}