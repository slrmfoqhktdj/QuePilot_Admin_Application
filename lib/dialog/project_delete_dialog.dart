import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/socket_service.dart';

class DeleteProjectDialog extends StatefulWidget {
  final String projectId;
  final String projectName;
  final Function(List<Map<String, dynamic>> projectList) onProjectDeleted;

  const DeleteProjectDialog({
    Key? key,
    required this.projectId,
    required this.projectName,
    required this.onProjectDeleted,
  }) : super(key: key);

  @override
  State<DeleteProjectDialog> createState() => _DeleteProjectDialogState();
}

class _DeleteProjectDialogState extends State<DeleteProjectDialog> {
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

    socketService.deleteProject(widget.projectId.trim(), (success , projectList) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });

        if (success) {
          Navigator.pop(context);
          widget.onProjectDeleted(projectList);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('프로젝트 삭제 실패')),
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
          Text('프로젝트 삭제'),
        ],
      ),
      content:  Text('프로젝트 ${widget.projectName}를 삭제하시겠습니까?'),
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
              : const Icon(Icons.add),
          label: Text(_isDeleting ? '삭제 중...' : '삭제'),
        ),
      ],
    );
  }
}