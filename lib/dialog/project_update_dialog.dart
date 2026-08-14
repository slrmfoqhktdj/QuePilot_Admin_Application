import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';
import '../utils/text_formatters.dart';

class UpdateProjectDialog extends StatefulWidget {
  final String projectId;
  final String projectName;
  final int duration;
  // final int fps;

  final Function(String, int) onProjectUpdated;

  const UpdateProjectDialog({
    Key? key,
    required this.projectId,
    required this.projectName,
    required this.duration,
    // required this.fps,
    required this.onProjectUpdated,
  }) : super(key: key);

  static Future<void> showDraggable(
    BuildContext context, {
    required String projectId,
    required String projectName,
    required int duration,
    required Function(String, int) onProjectUpdated,
  }) {
    return _showDraggableDialog(
      context,
      UpdateProjectDialog(
        projectId: projectId,
        projectName: projectName,
        duration: duration,
        onProjectUpdated: onProjectUpdated,
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
  State<UpdateProjectDialog> createState() => _UpdateProjectDialogState();
}

class _UpdateProjectDialogState extends State<UpdateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  // final TextEditingController _fpsController = TextEditingController();


  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.projectName;
    _durationController.text = (widget.duration / 3600).toInt().toString();
    // _fpsController.text = widget.fps.toString();
  }


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
      _isUpdating = true;
    });

    socketService.updateProject(widget.projectId, _nameController.text.trim(),int.parse(_durationController.text) * 3600, (success , projectList) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onProjectUpdated(_nameController.text.trim(),int.parse(_durationController.text));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트 업데이트 실패')),
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
          Text('프로젝트 수정'),
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
                inputFormatters: noOuterWhitespace,
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
                  labelText: 'Duration (시간)',
                  hintText: '5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer),
                  suffixText: '시간',
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
                  if (duration > 8) {
                    return 'Duration은 8시간을 초과할 수 없습니다';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // FPS
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