import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/timeline_cue_model.dart';
import '../utils/ColorUtils.dart';
import '../utils/text_formatters.dart';

class CueUpdateDialog extends StatefulWidget {
  final Cue? cue;
  final int? startTime;
  final List<Cue>? existingCues;

  const CueUpdateDialog({
    Key? key,
    this.cue,
    this.startTime,
    this.existingCues,
  }) : super(key: key);

  bool get isCreateMode => cue == null;

  /// 수정 모드: 기존 Cue를 편집
  static Future<Cue?> showForUpdate(
      BuildContext context, {
        required Cue cue,
        List<Cue>? existingCues,
      }) {
    return _showDraggableDialog(context, CueUpdateDialog(cue: cue, existingCues: existingCues));
  }

  /// 생성 모드: 새 Cue를 생성 (startTime는 우클릭한 위치의 시간)
  static Future<Cue?> showForCreate(
      BuildContext context, {
        required int startTime,
        List<Cue>? existingCues,
      }) {
    return _showDraggableDialog(context, CueUpdateDialog(startTime: startTime, existingCues: existingCues));
  }

  static Future<Cue?> _showDraggableDialog(BuildContext context, Widget dialog) {
    Offset dialogOffset = Offset.zero;

    return showGeneralDialog<Cue>(
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
  State<CueUpdateDialog> createState() => _CueUpdateDialogState();
}

class _CueUpdateDialogState extends State<CueUpdateDialog> {
  late TextEditingController _labelController;
  late TextEditingController _commentController;
  late TextEditingController _startTimeController;
  late TextEditingController _durationController;
  late Color _selectedColor;

  // 종료 시간 실시간 표시용
  int _startTime = 0;
  int _duration = 10;

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

    if (widget.isCreateMode) {
      final initialStartTime = widget.startTime ?? 0;
      _labelController = TextEditingController(text: '');
      _commentController = TextEditingController(text: '');
      _startTimeController =
          TextEditingController(text: initialStartTime.toString());
      _durationController = TextEditingController(text: '10');
      _selectedColor = _presetColors[0];
      _startTime = initialStartTime;
      _duration = 10;
    } else {
      _labelController = TextEditingController(text: widget.cue!.label);
      _commentController = TextEditingController(text: widget.cue!.comment);
      _startTimeController =
          TextEditingController(text: widget.cue!.startTime.toString());
      _durationController =
          TextEditingController(text: widget.cue!.duration.toString());
      _selectedColor = ColorUtils.parseColor(widget.cue!.color);
      _startTime = widget.cue!.startTime;
      _duration = widget.cue!.duration;
    }

    // 종료 시간 표시만 갱신 (콜백은 저장 시점에만 발생)
    _startTimeController.addListener(_refreshComputedTimes);
    _durationController.addListener(_refreshComputedTimes);
    _labelController.addListener(_onLabelChanged);
  }

  @override
  void dispose() {
    _labelController.removeListener(_onLabelChanged);
    _labelController.dispose();
    _commentController.dispose();
    _startTimeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _onLabelChanged() {
    final input = _labelController.text.trim();
    if (input.isEmpty || widget.existingCues == null) return;
    final match = widget.existingCues!.firstWhere(
      (c) => c.label == input && c.id != widget.cue?.id,
      orElse: () => Cue(startTime: 0, duration: 0, label: '', color: ''),
    );
    if (match.label.isNotEmpty) {
      setState(() { _selectedColor = ColorUtils.parseColor(match.color); });
    }
  }

  void _refreshComputedTimes() {
    setState(() {
      _startTime = int.tryParse(_startTimeController.text) ?? 0;
      _duration = int.tryParse(_durationController.text) ?? 10;
    });
  }

  void _onSave() {
    final nameText = _labelController.text.trim();
    final startText = _startTimeController.text.trim();
    final durationText = _durationController.text.trim();

    // 빈칸 검사
    if (nameText.isEmpty || startText.isEmpty || durationText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('빈칸을 채워주세요.')),
      );
      return; // 저장 중단
    }

    final startTime = int.tryParse(startText);
    final duration = int.tryParse(durationText);

    // 파싱 실패 검사
    if (startTime == null || duration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('숫자만 입력할 수 있습니다.')),
      );
      return;
    }

    final updated = Cue(
      id: widget.isCreateMode ? null : widget.cue!.id,
      label: nameText,
      comment: _commentController.text.trim(),
      startTime: startTime,
      duration: duration,
      color: ColorUtils.parseHex(_selectedColor),
    );

    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _selectedColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            )
          ),
          const SizedBox(width: 12),
          Text(widget.isCreateMode ? '큐 생성' : '큐 수정'),
        ],
      ),
      // 다이얼로그 폭을 넉넉히 확보
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                inputFormatters: noOuterWhitespace,
              ),
              const SizedBox(height: 12),

              // 큐 설명
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

              // 시작 시간 & 지속 시간
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

              // 종료 시간 표시 (실시간)
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
                      '종료 시간: ${_startTime + _duration}초',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.black
                              : Colors.grey.shade300,
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
                          ? const Icon(Icons.check,
                          color: Colors.white, size: 24)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // null 반환
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: Text(widget.isCreateMode ? '생성' : '저장'),
        ),
      ],
    );
  }
}
