import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';

class UpdateUserDialog extends StatefulWidget {
  final User user;
  final Function(User) onUserUpdated;

  const UpdateUserDialog({
    Key? key,
    required this.user,
    required this.onUserUpdated,
    
  }) : super(key: key);

  @override
  State<UpdateUserDialog> createState() => _UpdateUserDialogState();
}

class _UpdateUserDialogState extends State<UpdateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();
  bool _isUpdating = false;

  final TextEditingController _loginIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();


  @override
  void initState() {
    super.initState();

    _loginIdController.text = widget.user.login_id;
    _nameController.text = widget.user.name;
  }


  @override
  void dispose() {
    _loginIdController.dispose();
    _nameController.dispose();

    super.dispose();
  }


  void _updateUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    socketService.updateUser(
      widget.user.id,
      _loginIdController.text.trim(),
      _nameController.text.trim(),
          (success, data) {
        if (mounted) {
          setState(() {
            _isUpdating = false;
          });

          if (success) {
            Navigator.pop(context);
            widget.onUserUpdated(User.fromJson(data!));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('유저 정보 수정 실패')),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_circle, color: Colors.blue),
          SizedBox(width: 12),
          Text('유저 정보 수정'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 유저 이름
              TextFormField(
                controller: _loginIdController,
                decoration: const InputDecoration(
                  labelText: '유저 로그인 ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '로그인 ID를 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '유저 닉네임',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '닉네임을 입력하세요';
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
          onPressed: _isUpdating ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isUpdating ? null : _updateUser,
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
