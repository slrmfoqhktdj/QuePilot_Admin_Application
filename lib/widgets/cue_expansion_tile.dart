// ExpansionTile 기반 큐 편집 위젯
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:que_pilot_admin_01/utils/colorUtils.dart';
import '../models/timeline_cue_model.dart';

class CueExpansionTile extends StatefulWidget {
  final Cue cue;
  final int index;
  final Function(Cue) onUpdate;
  final VoidCallback onDelete;

  const CueExpansionTile({
    Key? key,
    required this.cue,
    required this.index,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<CueExpansionTile> createState() => _CueExpansionTileState();
}

class _CueExpansionTileState extends State<CueExpansionTile> {
  late TextEditingController _labelController;
  late TextEditingController _commentController;
  late TextEditingController _startTimeController;
  late TextEditingController _durationController;
  late Color _selectedColor;

  final List<Color> _presetColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.brown,
    Colors.indigo,
    Colors.lime,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.cue.label);
    _commentController = TextEditingController(text: widget.cue.comment);
    _startTimeController = TextEditingController(text: widget.cue.startTime.toString());
    _durationController = TextEditingController(text: widget.cue.duration.toString());
    // print("color : ${widget.cue.color}");
    _selectedColor = ColorUtils.parseColor(widget.cue.color);

    // 변경사항 자동 저장
    _labelController.addListener(_updateCue);
    _commentController.addListener(_updateCue);
    _startTimeController.addListener(_updateCue);
    _durationController.addListener(_updateCue);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _commentController.dispose();
    _startTimeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _updateCue() {
    if(!mounted) return;

    widget.onUpdate(Cue(
      id: widget.cue.id,
      label: _labelController.text.trim().isEmpty ? 'Cue ${widget.index + 1}' : _labelController.text.trim(),
      comment: _commentController.text.trim().isEmpty ? '': _commentController.text.trim(),
      startTime: int.tryParse(_startTimeController.text) ?? 0,
      duration: int.tryParse(_durationController.text) ?? 10,
      color: ColorUtils.parseHex(_selectedColor),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _selectedColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              '${widget.index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        title: Text(
          widget.cue.label.isEmpty ? 'Cue ${widget.index + 1}' : widget.cue.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${widget.cue.startTime}초 → ${widget.cue.startTime + widget.cue.duration}초 (${widget.cue.duration}초)',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('큐 삭제'),
                content: Text('${widget.cue.label}을(를) 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('삭제'),
                  ),
                ],
              ),
            );
          },
          tooltip: '삭제',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 큐 이름
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: '큐 이름',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                    hintText: '예: Intro, Main Scene',
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    labelText: '큐 설명',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.comment),
                    hintText: '예: Intro 설명, Main Scene 설명',
                  ),
                ),
                const SizedBox(height: 12),

                // 시작 시간 & 지속 시간 (Row로 나란히)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startTimeController,
                        decoration: const InputDecoration(
                          labelText: '시작 시간',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.play_arrow),
                          suffixText: '초',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _durationController,
                        decoration: const InputDecoration(
                          labelText: '지속 시간',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.timelapse),
                          suffixText: '초',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 종료 시간 표시
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        '종료 시간: ${widget.cue.startTime + widget.cue.duration}초',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 색상 선택에 컬러 피커 추가
                // TextButton.icon(
                //   onPressed: () {
                //     showDialog(
                //       context: context,
                //       builder: (context) => AlertDialog(
                //         title: const Text('색상 선택'),
                //         content: SingleChildScrollView(
                //           child: ColorPicker(
                //             pickerColor: _selectedColor,
                //             onColorChanged: (color) {
                //               setState(() {
                //                 _selectedColor = color;
                //               });
                //               _updateCue();
                //             },
                //           ),
                //         ),
                //         actions: [
                //           TextButton(
                //             onPressed: () => Navigator.pop(context),
                //             child: const Text('확인'),
                //           ),
                //         ],
                //       ),
                //     );
                //   },
                //   icon: const Icon(Icons.palette),
                //   label: const Text('커스텀 색상'),
                // ),

                // 색상 선택
                const Text(
                  '색상 선택:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _presetColors.map((color) {
                    final isSelected = _selectedColor == color;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColor = color;
                        });
                        _updateCue();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.grey.shade300,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 24)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}