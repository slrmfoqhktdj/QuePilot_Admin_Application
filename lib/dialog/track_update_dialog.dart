import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/timeline_cue_model.dart';
import '../services/socket_service.dart';
import '../utils/colorUtils.dart';
import '../widgets/cue_expansion_tile.dart';

class UpdateTrackDialog extends StatefulWidget {
  final String projectId;
  // final List<Room>? roomList;
  final Function(Map<String,dynamic>) onTimelineUpdated;

  final String? roomId;
  final List<Cue> cueList;
  final String trackName;
  final String trackId;

  const UpdateTrackDialog({
    Key? key,
    required this.projectId,
    // required this.roomList,
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
    _cues = widget.cueList;
    _nameController.text = widget.trackName;


    for(int i = 0; i < widget.cueList.length; i ++) {
      print("id : ${widget.cueList[i].id} , ${widget.cueList[i].label} , ${widget.cueList[i].color} , ${widget.cueList[i].startTime},${widget.cueList[i].duration}");
    }
  }


  @override
  void dispose() {
    _nameController.dispose();
    // _durationController.dispose();
    // _fpsController.dispose();
    super.dispose();
  }

  void _addCue() {
    setState(() {
      _cues.add(Cue(
        label: 'Cue ${_cues.length + 1}',
        comment: '',
        startTime: 0,
        duration: 10,
        color: ColorUtils.parseHex(Colors.blue),
      ));
    });
  }

  void _removeCue(int index) {
    setState(() {
      _cues.removeAt(index);
    });
  }

  void _updateTimeline() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    socketService.updateTrack(
      widget.projectId,
      widget.trackId,
      _nameController.text.trim(),
      _selectedRoomId!,
      _cues,
          (success, data) {
        if (mounted) {
          setState(() {
            _isCreating = false;
          });

          if (success) {
            Navigator.pop(context);
            widget.onTimelineUpdated(data!);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('타임라인 수정 실패')),
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
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '타임라인 이름을 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // DropdownButton(
              //   value: _selectedRoomId,
              //   hint: const Text('타임라인을 개시할 그룹을 선택해주세요'),
              //   isExpanded: true,
              //   items: widget.roomList?.map((item) {
              //     Map<String,dynamic> jsonItem = item.toJson();
              //     return DropdownMenuItem(
              //       value: jsonItem['id'].toString(),
              //       child: Text(jsonItem['name'].toString()),
              //
              //     );
              //   }).toList(),
              //   onChanged: (value) {
              //     setState(() {
              //       _selectedRoomId = value;
              //     });
              //   },
              //
              // ),

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
                  return CueExpansionTile(
                    cue: cue,
                    index: index,
                    onUpdate: (updatedCue) {
                      setState(() {
                        _cues[index] = updatedCue;
                      });
                    },
                    onDelete: () => _removeCue(index),
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
