import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:que_pilot_admin_01/dialog/cue_update_dialog.dart';
import '../models/timeline_cue_model.dart';
import '../models/timeline_room_model.dart';
import '../models/timeline_track_model.dart';
import '../services/socket_service.dart';
import '../utils/colorUtils.dart';
import '../utils/text_formatters.dart';

class UpdateTrackDialog extends StatefulWidget {
  final String projectId;
  final List<Room>? roomList;
  final Function(Track) onTimelineUpdated;

  final String? roomId;
  final List<Cue> cueList;
  final String trackName;
  final String trackId;

  const UpdateTrackDialog({
    Key? key,
    required this.projectId,
    this.roomList,
    required this.onTimelineUpdated,
    required this.roomId,
    required this.cueList,
    required this.trackName,
    required this.trackId,
  }) : super(key: key);

  @override
  State<UpdateTrackDialog> createState() => _UpdateTrackDialogState();
}

class _UpdateTrackDialogState extends State<UpdateTrackDialog> {
  final _formKey = GlobalKey<FormState>();
  final socketService = SocketService();

  final TextEditingController _nameController = TextEditingController();
  // final TextEditingController _durationController = TextEditingController(text: '120');
  // final TextEditingController _fpsController = TextEditingController(text: '30');

  bool _isCreating = false;
  String? _selectedRoomId;

  // 큐 목록
  List<Cue> _cues = [];

  @override
  void initState() {
    super.initState();
    // print("dialog: ${widget.roomList}");

    _selectedRoomId = widget.roomId;
    _cues = List<Cue>.from(widget.cueList);
    _nameController.text = widget.trackName;

    for (int i = 0; i < widget.cueList.length; i++) {
      print(
          "id : ${widget.cueList[i].id} , ${widget.cueList[i].label} , ${widget.cueList[i].color} , ${widget.cueList[i].startTime},${widget.cueList[i].duration}");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    // _durationController.dispose();
    // _fpsController.dispose();
    super.dispose();
  }

  void _addCue() async {
    final newCue = await CueUpdateDialog.showForCreate(context,
        startTime: 0, existingCues: _cues);
    if (newCue != null) {
      setState(() {
        _cues.add(newCue);
        _syncCueColors(sourceCueIndex: _cues.length - 1);
      });
    }
  }

  void _removeCue(int index) {
    setState(() {
      _cues.removeAt(index);
    });
  }

  void _syncCueColors({int? sourceCueIndex}) {
    final colorMap = <String, String>{};
    for (final cue in _cues) {
      if (cue.label.isNotEmpty) {
        colorMap[cue.label] = cue.color;
      }
    }
    if (sourceCueIndex != null &&
        sourceCueIndex >= 0 &&
        sourceCueIndex < _cues.length) {
      final src = _cues[sourceCueIndex];
      if (src.label.isNotEmpty) {
        colorMap[src.label] = src.color;
      }
    }
    for (int i = 0; i < _cues.length; i++) {
      final syncColor = colorMap[_cues[i].label];
      if (syncColor != null && _cues[i].color != syncColor) {
        _cues[i] = Cue(
          id: _cues[i].id,
          startTime: _cues[i].startTime,
          duration: _cues[i].duration,
          label: _cues[i].label,
          comment: _cues[i].comment,
          color: syncColor,
          data: _cues[i].data,
        );
      }
    }
  }

  void _updateTimeline() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    Navigator.pop(context);
    final isProjectTrack = _selectedRoomId == widget.projectId;
    widget.onTimelineUpdated(Track(
        id: widget.trackId,
        room_id: isProjectTrack ? null : _selectedRoomId,
        project_id: isProjectTrack ? widget.projectId : null,
        name: _nameController.text.trim(),
        cues: _cues));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_circle, color: Colors.blue),
          SizedBox(width: 12),
          Text('타임라인 수정'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 타임라인 이름
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '타임라인 이름',
                  hintText: '예: 카메라, BGM, 조명',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
                inputFormatters: noOuterWhitespace,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '타임라인 이름을 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (widget.roomList != null && widget.roomList!.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedRoomId,
                  decoration: const InputDecoration(
                    labelText: '개시 방',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.meeting_room),
                  ),
                  items: widget.roomList!.map((item) {
                    return DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedRoomId = value;
                    });
                  },
                ),
              const SizedBox(height: 16),

              // 큐 목록 섹션 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '큐(Cue) 목록',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addCue,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('큐 추가'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 큐 리스트 (ExpansionTile 방식)
              if (_cues.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade50,
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.movie_creation_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          '큐를 추가하려면 "큐 추가" 버튼을 클릭하세요',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._cues.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cue = entry.value;
                  // final color = ColorUtils.parseColor(cue.color);

                  //   return CueExpansionTile(
                  //     cue: cue,
                  //     index: index,
                  //     onUpdate: (updatedCue) {
                  //       setState(() {
                  //         _cues[index] = updatedCue;
                  //       });
                  //     },
                  //     onDelete: () => _removeCue(index),
                  //   );
                  // }).toList(),

                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ColorUtils.parseColor(cue.color),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Text('${index + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      title: Text(
                          cue.label.isEmpty ? 'Cue ${index + 1}' : cue.label),
                      subtitle: Text(
                        '${cue.startTime}초 → ${cue.startTime + cue.duration}초 (${cue.duration}초)',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeCue(index),
                      ),
                      onTap: () async {
                        final updated = await CueUpdateDialog.showForUpdate(
                          context,
                          cue: cue,
                          existingCues: _cues,
                        );
                        if (updated != null) {
                          // 여기서 기존 onUpdate(updated) 콜백 호출
                          setState(() {
                            _cues[index] = updated;
                            _syncCueColors(sourceCueIndex: index);
                          });
                        }
                      },
                    ),
                  );
                }).toList(),

              const SizedBox(height: 16),
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
          onPressed: _isCreating ? null : _updateTimeline,
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
          label: Text(_isCreating ? '수정 중...' : '수정'),
        ),
      ],
    );
  }
}
