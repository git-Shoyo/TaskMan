import 'package:flutter/material.dart';
import 'package:taskman/screens/task_detail_screen.dart';
import 'package:taskman/systems/task.dart';
import 'package:taskman/widgets/seven_day_gantt.dart';

const _transparentWindowKeyColor = Color(0xFFFF00FF);

class DesktopGanttWidgetScreen extends StatelessWidget {
  const DesktopGanttWidgetScreen({super.key});

  void _openTask(BuildContext context, Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskDetailScreen(taskId: task.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _transparentWindowKeyColor,
      body: ColoredBox(
        color: _transparentWindowKeyColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: UserSevenDayGantt(
              compact: true,
              frameless: true,
              maxRows: 7,
              onOpenTask: (task) => _openTask(context, task),
            ),
          ),
        ),
      ),
    );
  }
}
