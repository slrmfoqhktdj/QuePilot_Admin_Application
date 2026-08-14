import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/timeline_cue_model.dart';

class CueDeleteDialog extends StatefulWidget {
  final Cue? cue;
  final List<Cue>? cues;

  const CueDeleteDialog({
    Key? key,
    this.cue,
    this.cues,
  }) : super(key: key);

  static Future<Cue?> show(
      BuildContext context, {
        Cue? cue,
        List<Cue>? cues,
      }) {
    return showDialog<Cue>(
      context: context,
      builder: (_) => CueDeleteDialog(cue: cue, cues: cues),
    );
  }

  @override
  State<CueDeleteDialog> createState() => _CueDeleteDialogState();
}

class _CueDeleteDialogState extends State<CueDeleteDialog> {
  bool _isDeleting = false;
  // bool _createDefaultCues = true;


  @override
  void dispose() {

    super.dispose();
  }

  void _deleteCue() async {

    setState(() {
      _isDeleting = true;
    });

    Navigator.pop(context, widget.cue ?? (widget.cues != null && widget.cues!.isNotEmpty ? widget.cues!.first : null));

  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.cues != null && widget.cues!.isNotEmpty;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delete, color: Colors.blue),
          SizedBox(width: 12),
          Text('큐 삭제'),
        ],
      ),
      content: isMulti
          ? SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('선택된 ${widget.cues!.length}개의 큐를 삭제하시겠습니까?'),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.cues!.length,
                      itemBuilder: (context, index) {
                        final c = widget.cues![index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(
                            '${index + 1}. ${c.label}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : Text('큐 ${widget.cue?.label ?? ''}를 삭제하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton.icon(
          onPressed: _isDeleting ? null : _deleteCue,
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