import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
final DateFormat _dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key, required this.project});

  final Project project;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final titleController = TextEditingController();
  final categoryController = TextEditingController();
  final memoController = TextEditingController();
  final estimatedHoursController = TextEditingController();
  final estimatedMinutesController = TextEditingController();
  final tagsController = TextEditingController();
  final taskRepository = TaskRepository();
  final userRepository = UserRepository();

  DateTime? startDate;
  DateTime? deadline;
  DateTime? reminder;
  int? priority;
  String? selectedAssigneeId;
  List<AppUser> projectMembers = [AppUser.local()];
  bool isSaving = false;
  bool isLoadingMembers = false;

  @override
  void initState() {
    super.initState();
    loadProjectMembers();
  }

  Future<void> loadProjectMembers() async {
    setState(() {
      isLoadingMembers = true;
    });

    try {
      final members = await userRepository.fetchProjectMembers(widget.project);

      if (!mounted) {
        return;
      }

      setState(() {
        projectMembers = members;
        if (selectedAssigneeId != null &&
            !members.any((member) => member.id == selectedAssigneeId)) {
          selectedAssigneeId = null;
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('メンバーの読み込みに失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isLoadingMembers = false;
        });
      }
    }
  }

  Future<void> createTask() async {
    final title = titleController.text.trim();
    final category = categoryController.text.trim();
    final memo = memoController.text.trim();
    final Duration? estimatedTime;

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タスクタイトルを入力してください')));
      return;
    }

    if (startDate != null &&
        deadline != null &&
        deadline!.isBefore(startDate!)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('期限は開始日以降にしてください')));
      return;
    }

    try {
      estimatedTime = _parseEstimatedTimeInput(
        estimatedHoursController.text,
        estimatedMinutesController.text,
      );
    } on FormatException {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('見積もり時間を確認してください')));
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final selectedAssignee = _findMemberById(
        projectMembers,
        selectedAssigneeId,
      );

      await taskRepository.addTask(
        Task(
          id: '',
          title: title,
          projectId: widget.project.id,
          assigneeId: selectedAssignee?.id,
          assigneeName: selectedAssignee?.label,
          startDate: startDate,
          deadline: deadline,
          priority: priority,
          category: category,
          memo: memo.isEmpty ? null : memo,
          estimatedTime: estimatedTime,
          reminder: reminder,
          tags: _parseTags(tagsController.text),
        ),
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タスクの保存に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> pickDate({required bool isStartDate}) async {
    final currentValue = isStartDate ? startDate : deadline;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      if (isStartDate) {
        startDate = picked;
      } else {
        deadline = picked;
      }
    });
  }

  Future<void> pickReminderDateTime() async {
    final initialValue =
        reminder ?? deadline ?? DateTime.now().add(const Duration(minutes: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialValue,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (!mounted || pickedDate == null) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialValue),
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    final pickedReminder = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!pickedReminder.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未来のリマインダー日時を選択してください')));
      return;
    }

    setState(() {
      reminder = pickedReminder;
    });
  }

  @override
  void dispose() {
    titleController.dispose();
    categoryController.dispose();
    memoController.dispose();
    estimatedHoursController.dispose();
    estimatedMinutesController.dispose();
    tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('タスク追加'),
        actions: [
          IconButton(
            onPressed: isSaving ? null : createTask,
            tooltip: '保存',
            icon: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleController,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'タスクタイトル',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MemberDropdown(
                        label: '担当者',
                        members: projectMembers,
                        selectedMemberId: selectedAssigneeId,
                        emptyLabel: '担当者なし',
                        isEnabled: !isSaving && !isLoadingMembers,
                        isLoading: isLoadingMembers,
                        onChanged: (value) {
                          setState(() {
                            selectedAssigneeId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (isWide)
                        Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                label: '開始日',
                                value: startDate,
                                onTap: () => pickDate(isStartDate: true),
                                onClear: startDate == null
                                    ? null
                                    : () {
                                        setState(() {
                                          startDate = null;
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DateField(
                                label: '期限',
                                value: deadline,
                                onTap: () => pickDate(isStartDate: false),
                                onClear: deadline == null
                                    ? null
                                    : () {
                                        setState(() {
                                          deadline = null;
                                        });
                                      },
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _DateField(
                          label: '開始日',
                          value: startDate,
                          onTap: () => pickDate(isStartDate: true),
                          onClear: startDate == null
                              ? null
                              : () {
                                  setState(() {
                                    startDate = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 12),
                        _DateField(
                          label: '期限',
                          value: deadline,
                          onTap: () => pickDate(isStartDate: false),
                          onClear: deadline == null
                              ? null
                              : () {
                                  setState(() {
                                    deadline = null;
                                  });
                                },
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey(priority),
                        initialValue: priority,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '重要度',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 低')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                          DropdownMenuItem(value: 3, child: Text('3 中')),
                          DropdownMenuItem(value: 4, child: Text('4')),
                          DropdownMenuItem(value: 5, child: Text('5 高')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            priority = value;
                          });
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: priority == null
                              ? null
                              : () {
                                  setState(() {
                                    priority = null;
                                  });
                                },
                          icon: const Icon(Icons.clear),
                          label: const Text('重要度をクリア'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final hoursField = TextField(
                            controller: estimatedHoursController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: '見積もり 時間',
                              suffixText: '時間',
                            ),
                          );
                          final minutesField = TextField(
                            controller: estimatedMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: '見積もり 分',
                              suffixText: '分',
                            ),
                          );

                          if (constraints.maxWidth >= 560) {
                            return Row(
                              children: [
                                Expanded(child: hoursField),
                                const SizedBox(width: 12),
                                Expanded(child: minutesField),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              hoursField,
                              const SizedBox(height: 12),
                              minutesField,
                            ],
                          );
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              estimatedHoursController.clear();
                              estimatedMinutesController.clear();
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text('見積もりをクリア'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _DateField(
                        label: 'リマインダー日時',
                        value: reminder,
                        includeTime: true,
                        onTap: pickReminderDateTime,
                        onClear: reminder == null
                            ? null
                            : () {
                                setState(() {
                                  reminder = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryController,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'カテゴリ',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tagsController,
                        maxLength: 120,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'タグ',
                          helperText: 'カンマ区切りで入力',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 160,
                        child: TextField(
                          controller: memoController,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          maxLength: 500,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'メモ',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.label,
    required this.members,
    required this.selectedMemberId,
    required this.emptyLabel,
    required this.isEnabled,
    required this.isLoading,
    required this.onChanged,
  });

  final String label;
  final List<AppUser> members;
  final String? selectedMemberId;
  final String emptyLabel;
  final bool isEnabled;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final memberIds = members.map((member) => member.id).toSet();
    final selectedValue =
        selectedMemberId != null && memberIds.contains(selectedMemberId)
        ? selectedMemberId
        : null;

    return DropdownButtonFormField<String?>(
      key: ValueKey('member-$selectedValue-${memberIds.join(',')}'),
      initialValue: selectedValue,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        suffixIcon: isLoading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
        ...members.map(
          (member) => DropdownMenuItem<String?>(
            value: member.id,
            child: Text(
              member.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: isEnabled ? onChanged : null,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
    this.includeTime = false,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool includeTime;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          suffixIcon: IconButton(
            onPressed: onClear ?? onTap,
            tooltip: value == null
                ? (includeTime ? '日時を選択' : '日付を選択')
                : (includeTime ? '日時をクリア' : '日付をクリア'),
            icon: Icon(value == null ? Icons.calendar_today : Icons.clear),
          ),
        ),
        child: Text(
          value == null
              ? '未設定'
              : (includeTime ? _dateTimeFormat : _dateFormat).format(value!),
        ),
      ),
    );
  }
}

AppUser? _findMemberById(List<AppUser> members, String? memberId) {
  if (memberId == null) {
    return null;
  }

  for (final member in members) {
    if (member.id == memberId) {
      return member;
    }
  }

  return null;
}

Duration? _parseEstimatedTimeInput(String hoursText, String minutesText) {
  final rawHours = hoursText.trim();
  final rawMinutes = minutesText.trim();

  if (rawHours.isEmpty && rawMinutes.isEmpty) {
    return null;
  }

  final hours = rawHours.isEmpty ? 0 : int.tryParse(rawHours);
  final minutes = rawMinutes.isEmpty ? 0 : int.tryParse(rawMinutes);

  if (hours == null || minutes == null || hours < 0 || minutes < 0) {
    throw const FormatException('Invalid estimated time.');
  }

  if (hours == 0 && minutes == 0) {
    return null;
  }

  return Duration(hours: hours, minutes: minutes);
}

List<String> _parseTags(String rawTags) {
  return rawTags
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();
}
