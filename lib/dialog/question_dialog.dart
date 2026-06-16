import 'package:flutter/material.dart';

class QuestionAlertDialog extends StatefulWidget {
  final String question;
  final String confirmedText;
  final VoidCallback onConfirmed;


  const QuestionAlertDialog({
    super.key,
    required this.question,
    required this.confirmedText,
    required this.onConfirmed,
  });

  @override
  State<QuestionAlertDialog> createState() => _QuestionAlertDialogState();
}

class _QuestionAlertDialogState extends State<QuestionAlertDialog> {

  @override
  void initState() {
    super.initState();

  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return  AlertDialog(
      backgroundColor: Colors.grey[850],
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.question,
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirmed.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.confirmedText),
        ),
      ],
    );
  }


}
