import 'package:flutter/material.dart';

class DeleteTrackDialog extends StatefulWidget {
  final String projectId;
  final String roomId;
  final String trackId;
  final String trackName;
  final Function() onTrackDeleted;

  const DeleteTrackDialog({
    Key? key,
    required this.projectId,
    required this.roomId,
    required this.trackId,
    required this.trackName,
    required this.onTrackDeleted,
  }) : super(key: key);

  @override
  State<DeleteTrackDialog> createState() => _DeleteTrackDialogState();
}

class _DeleteTrackDialogState extends State<DeleteTrackDialog> {
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

    Navigator.pop(context);
    widget.onTrackDeleted();

  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delete, color: Colors.blue),
          SizedBox(width: 12),
          Text('타임라인 삭제'),
        ],
      ),
      content: Text('타임라인 ${widget.trackName}를 삭제하시겠습니까?'),
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