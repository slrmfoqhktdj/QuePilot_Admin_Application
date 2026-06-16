import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/socket_service.dart';

class AddUserDialog extends StatefulWidget {
  final Function(User user) onUserAdded;

  const AddUserDialog({
    Key? key,
    required this.onUserAdded,
  }) : super(key: key);

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController(text: '0000');

  bool _isCreating = false;
  // bool _createDefaultTracks = true;


  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _addUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    socketService.createUser(_idController.text.trim(),_nameController.text.trim(),_passwordController.text.trim(), (success , user) {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onUserAdded(User.fromJson(user!));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자 등록 실패')),
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
          Text('새 사용자 등록'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사용자 아이디
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: '사용자 ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.sort_by_alpha),
                ),
                inputFormatters: [
                  // ✅ 공백 제거
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '사용자 아이디를 입력하세요';
                  }
                  // ✅ 공백 포함 여부 체크
                  if (value.contains(' ')) {
                    return '공백을 포함할 수 없습니다';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 사용자 이름
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '사용자 이름',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.perm_identity),
                ),
                inputFormatters: [
                  // ✅ 공백 제거
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '사용자 이름을 입력하세요';
                  }
                  // ✅ 공백 포함 여부 체크
                  if (value.contains(' ')) {
                    return '공백을 포함할 수 없습니다';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 비밀번호
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '사용자 비밀번호',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                ),
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [
                  // ✅ 공백 제거
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  // ✅ 영문(대소문자), 숫자, 특수문자만 허용
                  // FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9!@#$%^&*()_+\-=\[\]{};:\'"\\|,.<>?/`~]'),),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력하세요';
                  }
                  // ✅ 공백 포함 여부 체크
                  if (value.contains(' ')) {
                    return '공백을 포함할 수 없습니다';
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
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isCreating ? null : _addUser,
          icon: _isCreating
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(Icons.add),
          label: Text(_isCreating ? '등록 중...' : '등록'),
        ),
      ],
    );
  }
}