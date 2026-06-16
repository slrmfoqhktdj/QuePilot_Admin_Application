import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';

class AddProjectDialog extends StatefulWidget {
  final Function(Map<String, dynamic> projectList) onProjectAdded;

  const AddProjectDialog({
    Key? key,
    required this.onProjectAdded,
  }) : super(key: key);

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _durationController = TextEditingController(text: '120');
  // final TextEditingController _fpsController = TextEditingController(text: '30');

  bool _isCreating = false;
  // bool _createDefaultTracks = true;


  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    // _fpsController.dispose();
    super.dispose();
  }

  void _createTimeline() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    socketService.createProject(_nameController.text.trim(),int.parse(_durationController.text), (success , projectList) {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onProjectAdded(projectList);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트 생성 실패')),
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
          Text('새 프로젝트 추가'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 프로젝트 이름
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '프로젝트 이름',
                  hintText: '예: Main Timeline',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '프로젝트 이름을 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Duration
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(
                  labelText: 'Duration (초)',
                  hintText: '120',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer),
                  suffixText: '초',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Duration을 입력하세요';
                  }
                  final duration = int.tryParse(value);
                  if (duration == null || duration <= 0) {
                    return '유효한 숫자를 입력하세요 (1 이상)';
                  }
                  if (duration > 3600) {
                    return 'Duration은 3600초를 초과할 수 없습니다';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // // FPS
              // TextFormField(
              //   controller: _fpsController,
              //   decoration: const InputDecoration(
              //     labelText: 'FPS',
              //     hintText: '30',
              //     border: OutlineInputBorder(),
              //     prefixIcon: Icon(Icons.speed),
              //     suffixText: 'fps',
              //   ),
              //   keyboardType: TextInputType.number,
              //   inputFormatters: [
              //     FilteringTextInputFormatter.digitsOnly,
              //   ],
              //   validator: (value) {
              //     if (value == null || value.isEmpty) {
              //       return 'FPS를 입력하세요';
              //     }
              //     final fps = int.tryParse(value);
              //     if (fps == null || fps <= 0) {
              //       return '유효한 숫자를 입력하세요 (1 이상)';
              //     }
              //     if (fps > 120) {
              //       return 'FPS는 120을 초과할 수 없습니다';
              //     }
              //     return null;
              //   },
              // ),
              // const SizedBox(height: 16),

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
          onPressed: _isCreating ? null : _createTimeline,
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
          label: Text(_isCreating ? '생성 중...' : '생성'),
        ),
      ],
    );
  }
}