import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
final DateFormat _dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.project});

  final String taskId;
  final Project? project;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final taskRepository = TaskRepository();
  final userRepository = UserRepository();
  final todoController = TextEditingController();
  final commentController = TextEditingController();

  bool isMutating = false;
  bool isLoadingMembers = false;
  String? selectedTodoAssigneeId;
  List<AppUser> projectMembers = [AppUser.local()];

  @override
  void initState() {
    super.initState();
    loadProjectMembers();
  }

  @override
  void didUpdateWidget(covariant TaskDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.project?.id != widget.project?.id) {
      loadProjectMembers();
    }
  }

  @override
  void dispose() {
    todoController.dispose();
    commentController.dispose();
    super.dispose();
  }

  Future<void> loadProjectMembers() async {
    setState(() {
      isLoadingMembers = true;
    });

    try {
      final members = widget.project == null
          ? [AppUser.local()]
          : await userRepository.fetchProjectMembers(widget.project!);

      if (!mounted) {
        return;
      }

      setState(() {
        projectMembers = members.isEmpty ? [AppUser.local()] : members;
        if (selectedTodoAssigneeId != null &&
            !projectMembers.any(
              (member) => member.id == selectedTodoAssigneeId,
            )) {
          selectedTodoAssigneeId = null;
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

  Future<bool> _runMutation(
    Future<void> Function() action, {
    required String errorMessage,
  }) async {
    if (isMutating) {
      return false;
    }

    setState(() {
      isMutating = true;
    });

    try {
      await action();
      return true;
    } catch (_) {
      if (!mounted) {
        return false;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
      return false;
    } finally {
      if (mounted) {
        setState(() {
          isMutating = false;
        });
      }
    }
  }

  Future<void> _setTaskDone(Task task, bool isDone) async {
    await _runMutation(
      () => taskRepository.setTaskDone(task: task, isDone: isDone),
      errorMessage: 'タスク状態の更新に失敗しました',
    );
  }

  Future<void> _addTodo(Task task) async {
    final title = todoController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('todo を入力してください')));
      return;
    }

    final didAdd = await _runMutation(
      () => taskRepository.addTodo(
        taskId: task.id,
        title: title,
        assigneeId: _findMemberById(projectMembers, selectedTodoAssigneeId)?.id,
        assigneeName: _findMemberById(
          projectMembers,
          selectedTodoAssigneeId,
        )?.label,
      ),
      errorMessage: 'todo の追加に失敗しました',
    );

    if (!mounted || !didAdd) {
      return;
    }

    todoController.clear();
    setState(() {
      selectedTodoAssigneeId = null;
    });
  }

  Future<void> _setTodoDone(Task task, TaskTodo todo, bool isDone) async {
    await _runMutation(
      () => taskRepository.setTodoDone(
        taskId: task.id,
        todoId: todo.id,
        isDone: isDone,
      ),
      errorMessage: 'todo の更新に失敗しました',
    );
  }

  Future<void> _deleteTodo(Task task, TaskTodo todo) async {
    await _runMutation(
      () => taskRepository.deleteTodo(taskId: task.id, todoId: todo.id),
      errorMessage: 'todo の削除に失敗しました',
    );
  }

  Future<void> _addComment(Task task) async {
    final body = commentController.text.trim();

    if (body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コメントを入力してください')));
      return;
    }

    final currentUser =
        AuthScope.maybeOf(context)?.currentUser ?? AppUser.local();
    final didAdd = await _runMutation(
      () => taskRepository.addComment(
        taskId: task.id,
        body: body,
        authorId: currentUser.id,
        authorName: currentUser.label,
      ),
      errorMessage: 'コメントの追加に失敗しました',
    );

    if (!mounted || !didAdd) {
      return;
    }

    commentController.clear();
  }

  Future<void> _deleteComment(Task task, TaskComment comment) async {
    await _runMutation(
      () =>
          taskRepository.deleteComment(taskId: task.id, commentId: comment.id),
      errorMessage: 'コメントの削除に失敗しました',
    );
  }

  Future<void> _editTaskDetails(Task task) async {
    final categoryController = TextEditingController(text: task.category);
    DateTime? draftStartDate = task.startDate;
    DateTime? draftDeadline = task.deadline;
    int? draftPriority = task.priority;
    bool isSaving = false;
    String? errorText;

    Future<void> pickDate(
      BuildContext dialogContext,
      StateSetter setDialogState, {
      required bool isStartDate,
    }) async {
      final currentValue = isStartDate ? draftStartDate : draftDeadline;
      final picked = await showDatePicker(
        context: dialogContext,
        initialDate: currentValue ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

      if (picked == null) {
        return;
      }

      setDialogState(() {
        if (isStartDate) {
          draftStartDate = picked;
        } else {
          draftDeadline = picked;
        }
        errorText = null;
      });
    }

    Future<void> saveDetails(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (draftStartDate != null &&
          draftDeadline != null &&
          draftDeadline!.isBefore(draftStartDate!)) {
        setDialogState(() {
          errorText = '期限は開始日以降にしてください';
        });
        return;
      }

      setDialogState(() {
        isSaving = true;
        errorText = null;
      });

      final didUpdate = await _runMutation(
        () => taskRepository.updateTaskDetails(
          taskId: task.id,
          startDate: draftStartDate,
          deadline: draftDeadline,
          priority: draftPriority,
          category: categoryController.text,
        ),
        errorMessage: '詳細情報の更新に失敗しました',
      );

      if (!mounted || !dialogContext.mounted) {
        return;
      }

      if (didUpdate) {
        Navigator.pop(dialogContext);
        return;
      }

      setDialogState(() {
        isSaving = false;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('詳細情報を編集'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (errorText != null) ...[
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _EditableDateField(
                        label: '開始日',
                        value: draftStartDate,
                        onTap: isSaving
                            ? null
                            : () => pickDate(
                                dialogContext,
                                setDialogState,
                                isStartDate: true,
                              ),
                        onClear: isSaving || draftStartDate == null
                            ? null
                            : () {
                                setDialogState(() {
                                  draftStartDate = null;
                                  errorText = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      _EditableDateField(
                        label: '期限',
                        value: draftDeadline,
                        onTap: isSaving
                            ? null
                            : () => pickDate(
                                dialogContext,
                                setDialogState,
                                isStartDate: false,
                              ),
                        onClear: isSaving || draftDeadline == null
                            ? null
                            : () {
                                setDialogState(() {
                                  draftDeadline = null;
                                  errorText = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        key: ValueKey(draftPriority),
                        initialValue: draftPriority,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: '重要度',
                        ),
                        items: const [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text('重要度なし'),
                          ),
                          DropdownMenuItem<int?>(value: 1, child: Text('1 低')),
                          DropdownMenuItem<int?>(value: 2, child: Text('2')),
                          DropdownMenuItem<int?>(value: 3, child: Text('3 中')),
                          DropdownMenuItem<int?>(value: 4, child: Text('4')),
                          DropdownMenuItem<int?>(value: 5, child: Text('5 高')),
                        ],
                        onChanged: isSaving
                            ? null
                            : (value) {
                                setDialogState(() {
                                  draftPriority = value;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: categoryController,
                        enabled: !isSaving,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'カテゴリ',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('キャンセル'),
                ),
                FilledButton.icon(
                  onPressed: isSaving
                      ? null
                      : () => saveDetails(dialogContext, setDialogState),
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    categoryController.dispose();
  }

  Future<void> _deleteTask(Task task) async {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('タスクを削除しますか'),
          content: Text('「${task.title}」を削除します。この操作は取り消せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    final didDelete = await _runMutation(
      () => taskRepository.deleteTask(task.id),
      errorMessage: 'タスクの削除に失敗しました',
    );

    if (mounted && didDelete) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Task?>(
      stream: taskRepository.watchTask(widget.taskId),
      builder: (context, snapshot) {
        final task = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            title: Text(task?.title ?? 'タスク詳細'),
            actions: [
              if (task != null)
                IconButton(
                  onPressed: isMutating
                      ? null
                      : () => _setTaskDone(task, !task.isDone),
                  tooltip: task.isDone ? '未完了に戻す' : '完了にする',
                  icon: Icon(
                    task.isDone
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                ),
              if (task != null)
                IconButton(
                  onPressed: isMutating ? null : () => _deleteTask(task),
                  tooltip: '削除',
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: SafeArea(child: _buildBody(snapshot)),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<Task?> snapshot) {
    if (snapshot.hasError) {
      return const Center(child: Text('タスクの読み込みに失敗しました'));
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    final task = snapshot.data;

    if (task == null) {
      return const Center(child: Text('タスクが見つかりません'));
    }

    return _TaskDetailContent(
      task: task,
      project: widget.project,
      todoController: todoController,
      commentController: commentController,
      projectMembers: projectMembers,
      selectedTodoAssigneeId: selectedTodoAssigneeId,
      isLoadingMembers: isLoadingMembers,
      isMutating: isMutating,
      onSetTaskDone: (isDone) => _setTaskDone(task, isDone),
      onAddTodo: () => _addTodo(task),
      onTodoAssigneeChanged: (memberId) {
        setState(() {
          selectedTodoAssigneeId = memberId;
        });
      },
      onSetTodoDone: (todo, isDone) => _setTodoDone(task, todo, isDone),
      onDeleteTodo: (todo) => _deleteTodo(task, todo),
      onEditDetails: () => _editTaskDetails(task),
      onAddComment: () => _addComment(task),
      onDeleteComment: (comment) => _deleteComment(task, comment),
    );
  }
}

class _TaskDetailContent extends StatelessWidget {
  const _TaskDetailContent({
    required this.task,
    required this.project,
    required this.todoController,
    required this.commentController,
    required this.projectMembers,
    required this.selectedTodoAssigneeId,
    required this.isLoadingMembers,
    required this.isMutating,
    required this.onSetTaskDone,
    required this.onAddTodo,
    required this.onTodoAssigneeChanged,
    required this.onSetTodoDone,
    required this.onDeleteTodo,
    required this.onEditDetails,
    required this.onAddComment,
    required this.onDeleteComment,
  });

  final Task task;
  final Project? project;
  final TextEditingController todoController;
  final TextEditingController commentController;
  final List<AppUser> projectMembers;
  final String? selectedTodoAssigneeId;
  final bool isLoadingMembers;
  final bool isMutating;
  final ValueChanged<bool> onSetTaskDone;
  final VoidCallback onAddTodo;
  final ValueChanged<String?> onTodoAssigneeChanged;
  final void Function(TaskTodo todo, bool isDone) onSetTodoDone;
  final ValueChanged<TaskTodo> onDeleteTodo;
  final VoidCallback onEditDetails;
  final VoidCallback onAddComment;
  final ValueChanged<TaskComment> onDeleteComment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _TaskSummary(
              task: task,
              project: project,
              isMutating: isMutating,
              onSetTaskDone: onSetTaskDone,
            ),
            const SizedBox(height: 16),
            _TaskMetaSection(
              task: task,
              isWide: isWide,
              isMutating: isMutating,
              onEditDetails: onEditDetails,
            ),
            if (task.memo != null && task.memo!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _TaskMemoSection(memo: task.memo!),
            ],
            const SizedBox(height: 16),
            _TodoSection(
              task: task,
              todoController: todoController,
              members: projectMembers,
              selectedAssigneeId: selectedTodoAssigneeId,
              isLoadingMembers: isLoadingMembers,
              isMutating: isMutating,
              isWide: isWide,
              onAddTodo: onAddTodo,
              onAssigneeChanged: onTodoAssigneeChanged,
              onSetTodoDone: onSetTodoDone,
              onDeleteTodo: onDeleteTodo,
            ),
            const SizedBox(height: 16),
            _CommentSection(
              task: task,
              commentController: commentController,
              isMutating: isMutating,
              isWide: isWide,
              onAddComment: onAddComment,
              onDeleteComment: onDeleteComment,
            ),
          ],
        );
      },
    );
  }
}

class _TaskSummary extends StatelessWidget {
  const _TaskSummary({
    required this.task,
    required this.project,
    required this.isMutating,
    required this.onSetTaskDone,
  });

  final Task task;
  final Project? project;
  final bool isMutating;
  final ValueChanged<bool> onSetTaskDone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final doneTodoCount = task.todos.where((todo) => todo.isDone).length;
    final todoText = task.todos.isEmpty
        ? (task.isDone ? 'タスク完了' : 'タスク未完了')
        : '$doneTodoCount / ${task.todos.length} todo';

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                _StatusChip(isDone: task.isDone),
              ],
            ),
            if (project != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      project!.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: task.completionRatio,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(999),
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${task.completionPercent}%',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(todoText),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: isMutating
                    ? null
                    : () => onSetTaskDone(!task.isDone),
                icon: Icon(
                  task.isDone
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle_outline,
                ),
                label: Text(task.isDone ? '未完了に戻す' : '完了にする'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMetaSection extends StatelessWidget {
  const _TaskMetaSection({
    required this.task,
    required this.isWide,
    required this.isMutating,
    required this.onEditDetails,
  });

  final Task task;
  final bool isWide;
  final bool isMutating;
  final VoidCallback onEditDetails;

  @override
  Widget build(BuildContext context) {
    final metas = [
      _TaskMetaItem(
        icon: Icons.play_arrow,
        label: '開始日',
        value: _formatDate(task.startDate),
      ),
      _TaskMetaItem(
        icon: Icons.event,
        label: '期限',
        value: _formatDate(task.deadline),
      ),
      _TaskMetaItem(
        icon: Icons.priority_high,
        label: '重要度',
        value: _formatPriority(task.priority),
      ),
      _TaskMetaItem(
        icon: Icons.label,
        label: 'カテゴリ',
        value: task.category.trim().isEmpty ? '未設定' : task.category,
      ),
      _TaskMetaItem(
        icon: Icons.person_outline,
        label: '担当者',
        value: task.assigneeName?.trim().isEmpty ?? true
            ? '未設定'
            : task.assigneeName!,
      ),
      _TaskMetaItem(
        icon: Icons.schedule,
        label: '更新日',
        value: _dateTimeFormat.format(task.updatedAt),
      ),
    ];

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionTitle(icon: Icons.info_outline, title: '詳細情報'),
                ),
                IconButton(
                  onPressed: isMutating ? null : onEditDetails,
                  tooltip: '詳細情報を編集',
                  icon: const Icon(Icons.edit),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 3 : 1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 64,
              ),
              itemCount: metas.length,
              itemBuilder: (context, index) {
                return _MetaTile(item: metas[index]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskMemoSection extends StatelessWidget {
  const _TaskMemoSection({required this.memo});

  final String memo;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.notes, title: 'メモ'),
            const SizedBox(height: 10),
            Text(memo),
          ],
        ),
      ),
    );
  }
}

class _TodoSection extends StatelessWidget {
  const _TodoSection({
    required this.task,
    required this.todoController,
    required this.members,
    required this.selectedAssigneeId,
    required this.isLoadingMembers,
    required this.isMutating,
    required this.isWide,
    required this.onAddTodo,
    required this.onAssigneeChanged,
    required this.onSetTodoDone,
    required this.onDeleteTodo,
  });

  final Task task;
  final TextEditingController todoController;
  final List<AppUser> members;
  final String? selectedAssigneeId;
  final bool isLoadingMembers;
  final bool isMutating;
  final bool isWide;
  final VoidCallback onAddTodo;
  final ValueChanged<String?> onAssigneeChanged;
  final void Function(TaskTodo todo, bool isDone) onSetTodoDone;
  final ValueChanged<TaskTodo> onDeleteTodo;

  @override
  Widget build(BuildContext context) {
    final todos = [...task.todos]
      ..sort((a, b) {
        if (a.isDone != b.isDone) {
          return a.isDone ? 1 : -1;
        }

        return a.createdAt.compareTo(b.createdAt);
      });

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.checklist, title: 'todo'),
            const SizedBox(height: 12),
            if (todos.isEmpty)
              const _EmptyLine(text: 'まだ todo がありません')
            else
              for (final todo in todos) ...[
                _TodoTile(
                  todo: todo,
                  isMutating: isMutating,
                  onChanged: (value) => onSetTodoDone(todo, value),
                  onDelete: () => onDeleteTodo(todo),
                ),
                if (todo != todos.last) const Divider(height: 1),
              ],
            const SizedBox(height: 16),
            _TodoComposer(
              todoController: todoController,
              members: members,
              selectedAssigneeId: selectedAssigneeId,
              isLoadingMembers: isLoadingMembers,
              isMutating: isMutating,
              isWide: isWide,
              onAssigneeChanged: onAssigneeChanged,
              onSubmit: onAddTodo,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.isMutating,
    required this.onChanged,
    required this.onDelete,
  });

  final TaskTodo todo;
  final bool isMutating;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textStyle = todo.isDone
        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
            decoration: TextDecoration.lineThrough,
            color: Theme.of(context).colorScheme.outline,
          )
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: todo.isDone,
            onChanged: isMutating ? null : (value) => onChanged(value ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(todo.title, style: textStyle),
                  if (todo.assigneeName != null &&
                      todo.assigneeName!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '担当 ${todo.assigneeName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: isMutating ? null : onDelete,
            tooltip: 'todo を削除',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _TodoComposer extends StatelessWidget {
  const _TodoComposer({
    required this.todoController,
    required this.members,
    required this.selectedAssigneeId,
    required this.isLoadingMembers,
    required this.isMutating,
    required this.isWide,
    required this.onAssigneeChanged,
    required this.onSubmit,
  });

  final TextEditingController todoController;
  final List<AppUser> members;
  final String? selectedAssigneeId;
  final bool isLoadingMembers;
  final bool isMutating;
  final bool isWide;
  final ValueChanged<String?> onAssigneeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final titleField = TextField(
      controller: todoController,
      enabled: !isMutating,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'todo を追加',
      ),
    );
    final assigneeField = _MemberDropdown(
      label: '担当者',
      emptyLabel: '担当者なし',
      members: members,
      selectedMemberId: selectedAssigneeId,
      allowEmpty: true,
      isEnabled: !isMutating && !isLoadingMembers,
      isLoading: isLoadingMembers,
      onChanged: onAssigneeChanged,
    );
    final submitButton = FilledButton.icon(
      onPressed: isMutating ? null : onSubmit,
      icon: const Icon(Icons.add),
      label: const Text('追加'),
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: titleField),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: assigneeField),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(top: 4), child: submitButton),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        titleField,
        const SizedBox(height: 8),
        assigneeField,
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: submitButton),
      ],
    );
  }
}

class _CommentSection extends StatelessWidget {
  const _CommentSection({
    required this.task,
    required this.commentController,
    required this.isMutating,
    required this.isWide,
    required this.onAddComment,
    required this.onDeleteComment,
  });

  final Task task;
  final TextEditingController commentController;
  final bool isMutating;
  final bool isWide;
  final VoidCallback onAddComment;
  final ValueChanged<TaskComment> onDeleteComment;

  @override
  Widget build(BuildContext context) {
    final comments = [...task.comments]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(icon: Icons.chat_bubble_outline, title: 'コメント'),
            const SizedBox(height: 12),
            _CommentComposer(
              commentController: commentController,
              isMutating: isMutating,
              isWide: isWide,
              onSubmit: onAddComment,
            ),
            const SizedBox(height: 16),
            if (comments.isEmpty)
              const _EmptyLine(text: 'まだコメントがありません')
            else
              for (final comment in comments) ...[
                _CommentTile(
                  comment: comment,
                  isMutating: isMutating,
                  onDelete: () => onDeleteComment(comment),
                ),
                if (comment != comments.last) const Divider(height: 20),
              ],
          ],
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.commentController,
    required this.isMutating,
    required this.isWide,
    required this.onSubmit,
  });

  final TextEditingController commentController;
  final bool isMutating;
  final bool isWide;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final commentField = TextField(
      controller: commentController,
      enabled: !isMutating,
      minLines: 3,
      maxLines: 5,
      maxLength: 400,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'コメント',
        alignLabelWithHint: true,
      ),
    );
    final submitButton = FilledButton.icon(
      onPressed: isMutating ? null : onSubmit,
      icon: const Icon(Icons.send),
      label: const Text('投稿'),
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: commentField),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(top: 4), child: submitButton),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        commentField,
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: submitButton),
      ],
    );
  }
}

class _EditableDateField extends StatelessWidget {
  const _EditableDateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

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
            tooltip: value == null ? '日付を選択' : '日付をクリア',
            icon: Icon(value == null ? Icons.calendar_today : Icons.clear),
          ),
        ),
        child: Text(value == null ? '未設定' : _dateFormat.format(value!)),
      ),
    );
  }
}

class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.label,
    required this.emptyLabel,
    required this.members,
    required this.selectedMemberId,
    required this.allowEmpty,
    required this.isEnabled,
    required this.isLoading,
    required this.onChanged,
  });

  final String label;
  final String emptyLabel;
  final List<AppUser> members;
  final String? selectedMemberId;
  final bool allowEmpty;
  final bool isEnabled;
  final bool isLoading;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final availableMembers = members.isEmpty ? [AppUser.local()] : members;
    final memberIds = availableMembers.map((member) => member.id).toSet();
    final selectedValue =
        selectedMemberId != null && memberIds.contains(selectedMemberId)
        ? selectedMemberId
        : (allowEmpty ? null : availableMembers.first.id);

    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-$selectedValue-${memberIds.join(',')}-$allowEmpty'),
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
        if (allowEmpty)
          DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
        ...availableMembers.map(
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isMutating,
    required this.onDelete,
  });

  final TaskComment comment;
  final bool isMutating;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(_authorInitial(comment.authorName)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    comment.authorName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    _dateTimeFormat.format(comment.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(comment.body),
            ],
          ),
        ),
        IconButton(
          onPressed: isMutating ? null : onDelete,
          tooltip: 'コメントを削除',
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({required this.item});

  final _TaskMetaItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(item.value, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetaItem {
  const _TaskMetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isDone});

  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        isDone ? Icons.check_circle : Icons.pending_outlined,
        size: 18,
      ),
      label: Text(isDone ? '完了' : '進行中'),
      backgroundColor: isDone
          ? colorScheme.primaryContainer
          : colorScheme.secondaryContainer,
    );
  }
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) {
    return '未設定';
  }

  return _dateFormat.format(date);
}

String _formatPriority(int? priority) {
  if (priority == null) {
    return '重要度なし';
  }

  return '重要度 $priority';
}

String _authorInitial(String authorName) {
  final trimmed = authorName.trim();

  if (trimmed.isEmpty) {
    return '?';
  }

  return trimmed.characters.first.toUpperCase();
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
