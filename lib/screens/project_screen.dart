import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gantt/flutter_gantt.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/issue_repository.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/screens/add_project/add_project_screen.dart';
import 'package:taskman/screens/add_task/add_task_screen.dart';
import 'package:taskman/screens/task_detail_screen.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/issue.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

final DateFormat _dateFormat = DateFormat('yyyy/MM/dd');
final DateFormat _shortDateFormat = DateFormat('M/d');

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  String? selectedProjectId;
  final projectRepository = ProjectRepository();

  void _openAddProjectScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProjectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showDetail = constraints.maxWidth >= 700;

        return Scaffold(
          floatingActionButton: showDetail
              ? null
              : FloatingActionButton(
                  onPressed: _openAddProjectScreen,
                  tooltip: 'プロジェクト作成',
                  child: const Icon(Icons.create),
                ),
          body: SafeArea(
            child: StreamBuilder<List<Project>>(
              stream: projectRepository.watchProjects(memberId: currentUser.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('プロジェクトの読み込みに失敗しました'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final projects = snapshot.data ?? const <Project>[];

                final selectedProject = _findProject(
                  projects,
                  selectedProjectId,
                );

                return Row(
                  children: [
                    SizedBox(
                      width: showDetail ? 320 : constraints.maxWidth,
                      child: _ProjectList(
                        projects: projects,
                        selectedProjectId: selectedProjectId,
                        showHeader: showDetail,
                        onCreateProject: _openAddProjectScreen,
                        onSelectProject: (project) {
                          if (showDetail) {
                            setState(() {
                              selectedProjectId = project.id;
                            });
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ProjectDetailScreen(project: project),
                            ),
                          );
                        },
                      ),
                    ),
                    if (showDetail) ...[
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selectedProject == null
                            ? const Center(child: Text('プロジェクトを選択してください'))
                            : _ProjectDetailScaffold(
                                key: ValueKey(selectedProject.id),
                                project: selectedProject,
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Project? _findProject(List<Project> projects, String? projectId) {
    if (projectId == null) {
      return null;
    }

    for (final project in projects) {
      if (project.id == projectId) {
        return project;
      }
    }

    return null;
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({
    required this.projects,
    required this.selectedProjectId,
    required this.showHeader,
    required this.onCreateProject,
    required this.onSelectProject,
  });

  final List<Project> projects;
  final String? selectedProjectId;
  final bool showHeader;
  final VoidCallback onCreateProject;
  final ValueChanged<Project> onSelectProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'プロジェクト',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onCreateProject,
                  icon: const Icon(Icons.create),
                  label: const Text('作成'),
                ),
              ],
            ),
          ),
        Expanded(
          child: projects.isEmpty
              ? _EmptyProjectList(onCreateProject: onCreateProject)
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(12, showHeader ? 8 : 12, 12, 12),
                  itemCount: projects.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    final isSelected = selectedProjectId == project.id;

                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        selected: isSelected,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: const Icon(Icons.folder),
                        ),
                        title: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          project.description ?? '詳細なし',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelectProject(project),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyProjectList extends StatelessWidget {
  const _EmptyProjectList({required this.onCreateProject});

  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 40),
            const SizedBox(height: 12),
            const Text('プロジェクトがありません'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateProject,
              icon: const Icon(Icons.create),
              label: const Text('プロジェクト作成'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return _ProjectDetailScaffold(project: project, showAppBar: true);
  }
}

class ProjectGanttScreen extends StatelessWidget {
  ProjectGanttScreen({super.key, required this.project});

  final Project project;
  final taskRepository = TaskRepository();

  void _openTaskDetail(BuildContext context, Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskDetailScreen(taskId: task.id, project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${project.name} ガントチャート')),
      body: SafeArea(
        child: StreamBuilder<List<Task>>(
          stream: taskRepository.watchTasks(projectId: project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('タスクの読み込みに失敗しました'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final tasks = snapshot.data ?? const <Task>[];

            return LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight = constraints.maxHeight > 32
                    ? constraints.maxHeight - 32
                    : constraints.maxHeight;

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: _GanttChart(
                    tasks: tasks,
                    taskRepository: taskRepository,
                    height: chartHeight,
                    onOpenTask: (task) => _openTaskDetail(context, task),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class EditProjectScreen extends StatefulWidget {
  const EditProjectScreen({super.key, required this.project});

  final Project project;

  @override
  State<EditProjectScreen> createState() => _EditProjectScreenState();
}

class _EditProjectScreenState extends State<EditProjectScreen> {
  final projectRepository = ProjectRepository();
  final userRepository = UserRepository();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final userSearchController = TextEditingController();

  bool isLoadingMembers = true;
  bool isSearchingUsers = false;
  bool isSaving = false;
  UserSearchField userSearchField = UserSearchField.email;
  List<AppUser> members = [];
  List<AppUser> userSearchResults = [];
  String? userSearchMessage;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.project.name;
    descriptionController.text = widget.project.description ?? '';
    _loadMembers();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    userSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      isLoadingMembers = true;
    });

    try {
      final loadedMembers = await userRepository.fetchProjectMembers(
        widget.project,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        members = loadedMembers;
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

  Future<void> _searchUsers({
    String? query,
    UserSearchField? searchField,
  }) async {
    final rawQuery = query ?? userSearchController.text;
    final field = searchField ?? userSearchField;

    if (rawQuery.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('検索キーワードを入力してください')));
      return;
    }

    setState(() {
      isSearchingUsers = true;
      userSearchMessage = null;
      userSearchResults = [];
    });

    try {
      final users = await userRepository.searchUsers(
        query: rawQuery,
        field: field,
      );
      final memberIds = members.map((member) => member.id).toSet();
      final filteredUsers = users
          .where(
            (user) =>
                user.id != AppUser.localUserId && !memberIds.contains(user.id),
          )
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        userSearchResults = filteredUsers;
        if (users.isEmpty) {
          userSearchMessage = 'ユーザーが見つかりません';
        } else if (filteredUsers.isEmpty) {
          userSearchMessage = 'このユーザーは既に追加されています';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ユーザー検索に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isSearchingUsers = false;
        });
      }
    }
  }

  void _addMember(AppUser user) {
    if (members.any((member) => member.id == user.id)) {
      return;
    }

    setState(() {
      members = [...members, user];
      userSearchResults.removeWhere((result) => result.id == user.id);
      userSearchMessage = userSearchResults.isEmpty ? '追加済みです' : null;
    });
  }

  void _removeMember(AppUser user) {
    if (user.id == widget.project.ownerId) {
      return;
    }

    setState(() {
      members.removeWhere((member) => member.id == user.id);
    });
  }

  Future<void> _saveProject() async {
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('プロジェクト名を入力してください')));
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final memberIds = <String>{
        widget.project.ownerId,
        ...members.map((member) => member.id),
      }.where((id) => id.trim().isNotEmpty).toList();
      final memberRoles = <String, String>{
        for (final memberId in memberIds)
          memberId: widget.project.memberRoles[memberId] ?? 'member',
        widget.project.ownerId: 'owner',
      };
      final updatedProject = Project(
        id: widget.project.id,
        name: name,
        description: description.isEmpty ? null : description,
        ownerId: widget.project.ownerId,
        organizationId: widget.project.organizationId,
        memberIds: memberIds,
        memberRoles: memberRoles,
        createdAt: widget.project.createdAt,
        updatedAt: widget.project.updatedAt,
        startDate: widget.project.startDate,
        deadline: widget.project.deadline,
        isArchived: widget.project.isArchived,
        color: widget.project.color,
        icon: widget.project.icon,
      );

      await projectRepository.updateProject(updatedProject);

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } on DuplicateProjectNameException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同じ名前のプロジェクトが既にあります')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('プロジェクトの更新に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロジェクト編集'),
        actions: [
          IconButton(
            onPressed: isSaving ? null : _saveProject,
            tooltip: '保存',
            icon: isSaving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TextField(
              controller: nameController,
              enabled: !isSaving,
              maxLength: 50,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'プロジェクト名',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              enabled: !isSaving,
              minLines: 4,
              maxLines: 8,
              maxLength: 1000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '詳細',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            _ProjectMemberEditSection(
              ownerId: widget.project.ownerId,
              members: members,
              searchResults: userSearchResults,
              searchMessage: userSearchMessage,
              searchField: userSearchField,
              searchController: userSearchController,
              isLoadingMembers: isLoadingMembers,
              isSearching: isSearchingUsers,
              isSaving: isSaving,
              onSearchFieldChanged: (field) {
                setState(() {
                  userSearchField = field;
                  userSearchMessage = null;
                  userSearchResults = [];
                });
              },
              onSearch: () => _searchUsers(),
              onAddMember: _addMember,
              onRemoveMember: _removeMember,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMemberEditSection extends StatelessWidget {
  const _ProjectMemberEditSection({
    required this.ownerId,
    required this.members,
    required this.searchResults,
    required this.searchMessage,
    required this.searchField,
    required this.searchController,
    required this.isLoadingMembers,
    required this.isSearching,
    required this.isSaving,
    required this.onSearchFieldChanged,
    required this.onSearch,
    required this.onAddMember,
    required this.onRemoveMember,
  });

  final String ownerId;
  final List<AppUser> members;
  final List<AppUser> searchResults;
  final String? searchMessage;
  final UserSearchField searchField;
  final TextEditingController searchController;
  final bool isLoadingMembers;
  final bool isSearching;
  final bool isSaving;
  final ValueChanged<UserSearchField> onSearchFieldChanged;
  final VoidCallback onSearch;
  final ValueChanged<AppUser> onAddMember;
  final ValueChanged<AppUser> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final searchInput = TextField(
      controller: searchController,
      enabled: !isSaving && !isSearching,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: _projectEditSearchFieldLabel(searchField),
        prefixIcon: Icon(_projectEditSearchFieldIcon(searchField)),
      ),
    );
    final searchButton = FilledButton.icon(
      onPressed: isSaving || isSearching ? null : onSearch,
      icon: isSearching
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Text('検索'),
    );

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _ProjectEditSectionTitle(
                    icon: Icons.group,
                    title: 'メンバー',
                  ),
                ),
                if (isLoadingMembers)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (members.isEmpty && !isLoadingMembers)
              const _EmptyLine(text: 'メンバーがいません')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in members)
                    InputChip(
                      avatar: CircleAvatar(
                        child: Text(_projectEditUserInitial(member)),
                      ),
                      label: Text(
                        member.id == ownerId
                            ? '${member.label} / owner'
                            : member.label,
                      ),
                      onDeleted: member.id == ownerId || isSaving
                          ? null
                          : () => onRemoveMember(member),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            SegmentedButton<UserSearchField>(
              showSelectedIcon: false,
              selected: {searchField},
              segments: const [
                ButtonSegment(
                  value: UserSearchField.email,
                  icon: Icon(Icons.mail_outline),
                  label: Text('メール'),
                ),
                ButtonSegment(
                  value: UserSearchField.userId,
                  icon: Icon(Icons.badge_outlined),
                  label: Text('ユーザーID'),
                ),
              ],
              onSelectionChanged: isSaving || isSearching
                  ? null
                  : (values) => onSearchFieldChanged(values.first),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 560) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: searchInput),
                      const SizedBox(width: 8),
                      searchButton,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchInput,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: searchButton,
                    ),
                  ],
                );
              },
            ),
            if (searchMessage != null) ...[
              const SizedBox(height: 8),
              Text(searchMessage!),
            ],
            if (searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final user in searchResults)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(_projectEditUserInitial(user)),
                  ),
                  title: Text(user.label),
                  subtitle: user.searchableSubtitle.isEmpty
                      ? null
                      : Text(user.searchableSubtitle),
                  trailing: IconButton(
                    onPressed: isSaving ? null : () => onAddMember(user),
                    tooltip: '追加',
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _projectEditSearchFieldLabel(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => 'メールアドレス',
    UserSearchField.userId => 'ユーザーID',
    UserSearchField.qrCode => 'QRコード',
  };
}

IconData _projectEditSearchFieldIcon(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => Icons.mail_outline,
    UserSearchField.userId => Icons.badge_outlined,
    UserSearchField.qrCode => Icons.qr_code_scanner,
  };
}

String _projectEditUserInitial(AppUser user) {
  final label = user.label.trim();

  if (label.isEmpty) {
    return '?';
  }

  return label.characters.first.toUpperCase();
}

class _ProjectEditSectionTitle extends StatelessWidget {
  const _ProjectEditSectionTitle({required this.icon, required this.title});

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

class ProjectAnalyticsScreen extends StatelessWidget {
  ProjectAnalyticsScreen({super.key, required this.project});

  final Project project;
  final taskRepository = TaskRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${project.name} アナリティクス')),
      body: SafeArea(
        child: StreamBuilder<List<Task>>(
          stream: taskRepository.watchTasks(projectId: project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('タスクの読み込みに失敗しました'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            return _ProjectAnalyticsContent(
              data: _ProjectAnalyticsData(
                project: project,
                tasks: snapshot.data ?? const <Task>[],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProjectDetailScaffold extends StatefulWidget {
  const _ProjectDetailScaffold({
    super.key,
    required this.project,
    this.showAppBar = false,
  });

  final Project project;
  final bool showAppBar;

  @override
  State<_ProjectDetailScaffold> createState() => _ProjectDetailScaffoldState();
}

class _ProjectDetailScaffoldState extends State<_ProjectDetailScaffold> {
  final taskRepository = TaskRepository();
  final projectRepository = ProjectRepository();
  final issueRepository = IssueRepository();

  bool isDeletingProject = false;
  bool isMutatingIssue = false;

  void _openAddTaskScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskScreen(project: widget.project),
      ),
    );
  }

  void _openGanttChart() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectGanttScreen(project: widget.project),
      ),
    );
  }

  void _openAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectAnalyticsScreen(project: widget.project),
      ),
    );
  }

  void _openTaskDetail(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskDetailScreen(taskId: task.id, project: widget.project),
      ),
    );
  }

  void _openEditProjectScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProjectScreen(project: widget.project),
      ),
    );
  }

  Future<void> _openAddIssueDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final labelsController = TextEditingController();
    final externalUrlController = TextEditingController();
    bool isSaving = false;
    String? errorText;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> saveIssue() async {
                final title = titleController.text.trim();

                if (title.isEmpty) {
                  setDialogState(() {
                    errorText = 'Issue タイトルを入力してください';
                  });
                  return;
                }

                setDialogState(() {
                  isSaving = true;
                  errorText = null;
                });

                final currentUser =
                    AuthScope.maybeOf(context)?.currentUser ?? AppUser.local();
                final externalUrl = externalUrlController.text.trim();

                try {
                  await issueRepository.addIssue(
                    ProjectIssue(
                      id: '',
                      projectId: widget.project.id,
                      organizationId: widget.project.organizationId,
                      title: title,
                      body: bodyController.text.trim().isEmpty
                          ? null
                          : bodyController.text.trim(),
                      labels: _parseIssueLabels(labelsController.text),
                      authorId: currentUser.id,
                      authorName: currentUser.label,
                      externalSource: externalUrl.isEmpty ? null : 'github',
                      externalUrl: externalUrl.isEmpty ? null : externalUrl,
                    ),
                  );

                  if (!mounted || !dialogContext.mounted) {
                    return;
                  }

                  Navigator.pop(dialogContext);
                } catch (_) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  setDialogState(() {
                    isSaving = false;
                    errorText = 'Issue の保存に失敗しました';
                  });
                }
              }

              return AlertDialog(
                title: const Text('Issue を追加'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
                        TextField(
                          controller: titleController,
                          enabled: !isSaving,
                          autofocus: true,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Issue タイトル',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: bodyController,
                          enabled: !isSaving,
                          minLines: 4,
                          maxLines: 7,
                          maxLength: 1200,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '本文',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: labelsController,
                          enabled: !isSaving,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'ラベル',
                            helperText: 'カンマ区切りで入力',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: externalUrlController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'GitHub Issue URL',
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
                    onPressed: isSaving ? null : saveIssue,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('追加'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      bodyController.dispose();
      labelsController.dispose();
      externalUrlController.dispose();
    }
  }

  Future<void> _setIssueStatus(
    ProjectIssue issue,
    ProjectIssueStatus status,
  ) async {
    if (isMutatingIssue) {
      return;
    }

    setState(() {
      isMutatingIssue = true;
    });

    try {
      await issueRepository.setIssueStatus(issue: issue, status: status);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Issue の更新に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isMutatingIssue = false;
        });
      }
    }
  }

  Future<void> _deleteProject() async {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('プロジェクトを削除しますか'),
          content: Text(
            '「${widget.project.name}」と、このプロジェクト内のタスクを削除します。この操作は取り消せません。',
          ),
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

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      isDeletingProject = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await taskRepository.deleteTasksByProjectId(widget.project.id);
      await issueRepository.deleteIssuesByProjectId(widget.project.id);
      await projectRepository.archiveProject(widget.project);

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(const SnackBar(content: Text('プロジェクトを削除しました')));

      if (widget.showAppBar && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(const SnackBar(content: Text('プロジェクトの削除に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isDeletingProject = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;
    final canManageProject = currentUser.id == widget.project.ownerId;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: Text(widget.project.name))
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: isDeletingProject ? null : _openAddTaskScreen,
        tooltip: 'タスク追加',
        child: const Icon(Icons.add_task),
      ),
      body: SafeArea(
        top: !widget.showAppBar,
        child: StreamBuilder<List<Task>>(
          stream: taskRepository.watchTasks(projectId: widget.project.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('タスクの読み込みに失敗しました'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final tasks = snapshot.data ?? const <Task>[];

            return StreamBuilder<List<ProjectIssue>>(
              stream: issueRepository.watchIssues(projectId: widget.project.id),
              builder: (context, issueSnapshot) {
                if (issueSnapshot.hasError) {
                  return const Center(child: Text('Issue の読み込みに失敗しました'));
                }

                if (issueSnapshot.connectionState == ConnectionState.waiting &&
                    !issueSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return _ProjectDetailContent(
                  project: widget.project,
                  tasks: tasks,
                  issues: issueSnapshot.data ?? const <ProjectIssue>[],
                  isMutatingIssue: isMutatingIssue,
                  onOpenGantt: _openGanttChart,
                  onOpenAnalytics: _openAnalytics,
                  onEditProject: canManageProject
                      ? _openEditProjectScreen
                      : null,
                  onDeleteProject: canManageProject && !isDeletingProject
                      ? _deleteProject
                      : null,
                  onOpenTask: _openTaskDetail,
                  onCreateIssue: _openAddIssueDialog,
                  onSetIssueStatus: _setIssueStatus,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProjectDetailContent extends StatelessWidget {
  const _ProjectDetailContent({
    required this.project,
    required this.tasks,
    required this.issues,
    required this.isMutatingIssue,
    required this.onOpenGantt,
    required this.onOpenAnalytics,
    required this.onEditProject,
    required this.onDeleteProject,
    required this.onOpenTask,
    required this.onCreateIssue,
    required this.onSetIssueStatus,
  });

  final Project project;
  final List<Task> tasks;
  final List<ProjectIssue> issues;
  final bool isMutatingIssue;
  final VoidCallback onOpenGantt;
  final VoidCallback onOpenAnalytics;
  final VoidCallback? onEditProject;
  final VoidCallback? onDeleteProject;
  final ValueChanged<Task> onOpenTask;
  final VoidCallback onCreateIssue;
  final void Function(ProjectIssue issue, ProjectIssueStatus status)
  onSetIssueStatus;

  @override
  Widget build(BuildContext context) {
    final sortedTasks = _sortTasks(tasks);
    final nearestDeadlineTask = _nearestDeadlineTask(tasks);
    final highestPriorityTask = _highestPriorityTask(tasks);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
          children: [
            _DetailHeader(
              project: project,
              onOpenGantt: onOpenGantt,
              onOpenAnalytics: onOpenAnalytics,
              onEditProject: onEditProject,
              onDeleteProject: onDeleteProject,
            ),
            const SizedBox(height: 16),
            _TaskHighlights(
              isWide: isWide,
              nearestDeadlineTask: nearestDeadlineTask,
              highestPriorityTask: highestPriorityTask,
            ),
            if (project.description != null &&
                project.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(project.description!),
            ],
            const SizedBox(height: 24),
            _IssueSection(
              issues: issues,
              isMutating: isMutatingIssue,
              onCreateIssue: onCreateIssue,
              onSetIssueStatus: onSetIssueStatus,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'タスク一覧',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${tasks.length}件'),
              ],
            ),
            const SizedBox(height: 12),
            if (sortedTasks.isEmpty)
              const _EmptyTaskList()
            else
              for (final task in sortedTasks) ...[
                _TaskCard(task: task, onTap: () => onOpenTask(task)),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.project,
    required this.onOpenGantt,
    required this.onOpenAnalytics,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final Project project;
  final VoidCallback onOpenGantt;
  final VoidCallback onOpenAnalytics;
  final VoidCallback? onEditProject;
  final VoidCallback? onDeleteProject;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onOpenGantt,
              icon: const Icon(Icons.open_in_full),
              label: const Text('ガントチャート'),
            ),
            FilledButton.tonalIcon(
              onPressed: onOpenAnalytics,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('アナリティクス'),
            ),
            if (onEditProject != null)
              OutlinedButton.icon(
                onPressed: onEditProject,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('編集'),
              ),
            if (onDeleteProject != null)
              OutlinedButton.icon(
                onPressed: onDeleteProject,
                icon: const Icon(Icons.delete_outline),
                label: const Text('削除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.64),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TaskHighlights extends StatelessWidget {
  const _TaskHighlights({
    required this.isWide,
    required this.nearestDeadlineTask,
    required this.highestPriorityTask,
  });

  final bool isWide;
  final Task? nearestDeadlineTask;
  final Task? highestPriorityTask;

  @override
  Widget build(BuildContext context) {
    final nearestDeadlineCard = _HighlightCard(
      icon: Icons.event,
      label: '期限が近いタスク',
      task: nearestDeadlineTask,
      emptyText: '期限付きタスクなし',
      detailBuilder: (task) => '期限 ${_formatDate(task.deadline)}',
    );
    final highestPriorityCard = _HighlightCard(
      icon: Icons.priority_high,
      label: '重要度が高いタスク',
      task: highestPriorityTask,
      emptyText: '重要度付きタスクなし',
      detailBuilder: (task) => _formatPriority(task.priority),
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: nearestDeadlineCard),
          const SizedBox(width: 12),
          Expanded(child: highestPriorityCard),
        ],
      );
    }

    return Column(
      children: [
        nearestDeadlineCard,
        const SizedBox(height: 12),
        highestPriorityCard,
      ],
    );
  }
}

class _ProjectAnalyticsContent extends StatelessWidget {
  const _ProjectAnalyticsContent({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _AnalyticsMetric(
        icon: Icons.task_alt,
        label: '総タスク',
        value: '${data.totalTasks}',
        detail: '完了 ${data.doneTasks} / 未完了 ${data.openTasks}',
      ),
      _AnalyticsMetric(
        icon: Icons.percent,
        label: '平均進捗',
        value: _formatPercent(data.averageProgress),
        detail: '完了率 ${_formatPercent(data.doneRate)}',
      ),
      _AnalyticsMetric(
        icon: Icons.warning_amber,
        label: '期限超過',
        value: '${data.overdueTasks}',
        detail: data.overdueTasks == 0 ? '遅延なし' : '対応が必要',
      ),
      _AnalyticsMetric(
        icon: Icons.event_available,
        label: '7日以内期限',
        value: '${data.dueSoonTasks}',
        detail: '未完了タスクのみ',
      ),
      _AnalyticsMetric(
        icon: Icons.event_busy,
        label: '日付未設定',
        value: '${data.unscheduledTasks}',
        detail: 'ガント未表示',
      ),
      _AnalyticsMetric(
        icon: Icons.priority_high,
        label: '高重要度',
        value: '${data.highPriorityOpenTasks}',
        detail: '重要度4以上の未完了',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;
        final gridColumns = constraints.maxWidth >= 1020
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _AnalyticsSummaryCard(data: data),
            const SizedBox(height: 16),
            _AnalyticsMetricGrid(metrics: metrics, columns: gridColumns),
            const SizedBox(height: 16),
            _ProjectAnalyticsChartGrid(
              children: [
                _CompletionTrendChartCard(data: data),
                _DeadlineRiskChartCard(data: data),
                _PriorityDistributionChartCard(data: data),
                _AssigneeWorkloadChartCard(data: data),
              ],
            ),
            const SizedBox(height: 16),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _AnalyticsStatusCard(data: data)),
                  const SizedBox(width: 16),
                  Expanded(child: _AnalyticsAssigneeCard(data: data)),
                ],
              )
            else ...[
              _AnalyticsStatusCard(data: data),
              const SizedBox(height: 16),
              _AnalyticsAssigneeCard(data: data),
            ],
            const SizedBox(height: 16),
            _AnalyticsDeadlineCard(data: data),
          ],
        );
      },
    );
  }
}

class _AnalyticsSummaryCard extends StatelessWidget {
  const _AnalyticsSummaryCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.project.name,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge,
                  ),
                ),
                Text(_formatPercent(data.averageProgress)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: data.averageProgress,
                minHeight: 12,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              data.totalTasks == 0
                  ? 'タスクがまだありません'
                  : '${data.totalTasks}件中 ${data.doneTasks}件完了、'
                        '${data.openTasks}件が進行中です',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsMetricGrid extends StatelessWidget {
  const _AnalyticsMetricGrid({required this.metrics, required this.columns});

  final List<_AnalyticsMetric> metrics;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: metrics.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 118,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        return _AnalyticsMetricCard(metric: metrics[index]);
      },
    );
  }
}

class _AnalyticsMetricCard extends StatelessWidget {
  const _AnalyticsMetricCard({required this.metric});

  final _AnalyticsMetric metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(metric.value, style: textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            metric.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProjectAnalyticsChartGrid extends StatelessWidget {
  const _ProjectAnalyticsChartGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180 ? 2 : 1;
        const gap = 16.0;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _CompletionTrendChartCard extends StatelessWidget {
  const _CompletionTrendChartCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final trend = data.completionTrend;
    final maxCount = trend.fold<int>(
      0,
      (currentMax, point) => math.max(currentMax, point.count),
    );

    return _AnalyticsPanel(
      icon: Icons.show_chart,
      title: '完了推移',
      child: data.totalTasks == 0
          ? const _AnalyticsEmptyMessage(text: 'タスクが追加されると推移を表示します')
          : SizedBox(
              height: 230,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: math.max(1, maxCount).toDouble(),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.64),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: _projectLineChartTitles(context, trend),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var index = 0; index < trend.length; index += 1)
                          FlSpot(
                            index.toDouble(),
                            trend[index].count.toDouble(),
                          ),
                      ],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                  lineTouchData: const LineTouchData(enabled: true),
                ),
              ),
            ),
    );
  }
}

class _DeadlineRiskChartCard extends StatelessWidget {
  const _DeadlineRiskChartCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buckets = data.deadlineBuckets;
    final total = buckets.fold<int>(0, (sum, bucket) => sum + bucket.count);

    return _AnalyticsPanel(
      icon: Icons.event_busy,
      title: '期限リスク分析',
      child: total == 0
          ? const _AnalyticsEmptyMessage(text: '未完了タスクがありません')
          : Column(
              children: [
                SizedBox(
                  height: 210,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 42,
                      sectionsSpace: 2,
                      sections: [
                        for (final bucket in buckets)
                          if (bucket.count > 0)
                            PieChartSectionData(
                              value: bucket.count.toDouble(),
                              title: '${bucket.count}',
                              color: bucket.color(colorScheme),
                              radius: 58,
                              cornerRadius: 4,
                              titleStyle: TextStyle(
                                color: bucket.onColor(colorScheme),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _AnalyticsLegendWrap(
                  items: [
                    for (final bucket in buckets)
                      _AnalyticsLegendItem(
                        color: bucket.color(colorScheme),
                        label: '${bucket.label} ${bucket.count}',
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PriorityDistributionChartCard extends StatelessWidget {
  const _PriorityDistributionChartCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final counts = data.priorityCounts;
    final maxCount = counts.values.fold<int>(0, math.max);

    return _AnalyticsPanel(
      icon: Icons.priority_high,
      title: '重要度分布',
      child: maxCount == 0
          ? const _AnalyticsEmptyMessage(text: '重要度付きの未完了タスクはありません')
          : SizedBox(
              height: 230,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxCount.toDouble(),
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.64),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: _projectBarChartTitles(
                    context,
                    bottomLabel: (value) => '${value.toInt()}',
                  ),
                  barGroups: [
                    for (var priority = 1; priority <= 5; priority += 1)
                      BarChartGroupData(
                        x: priority,
                        barRods: [
                          BarChartRodData(
                            toY: (counts[priority] ?? 0).toDouble(),
                            width: 22,
                            color: _priorityColor(
                              Theme.of(context).colorScheme,
                              priority,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AssigneeWorkloadChartCard extends StatelessWidget {
  const _AssigneeWorkloadChartCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final stats = data.assigneeStats;
    final maxActive = stats.fold<int>(
      0,
      (currentMax, stat) => math.max(currentMax, stat.active),
    );

    return _AnalyticsPanel(
      icon: Icons.groups_2_outlined,
      title: '担当者別の負荷',
      child: stats.isEmpty
          ? const _AnalyticsEmptyMessage(text: '担当者データがありません')
          : Column(
              children: [
                SizedBox(
                  height: 230,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: math.max(1, maxActive).toDouble(),
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.64),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: _projectBarChartTitles(
                        context,
                        bottomLabel: (value) {
                          final index = value.toInt();
                          if (index < 0 || index >= stats.length) {
                            return '';
                          }

                          return '${index + 1}';
                        },
                      ),
                      barGroups: [
                        for (var index = 0; index < stats.length; index += 1)
                          BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: stats[index].active.toDouble(),
                                width: 22,
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < stats.length; index += 1) ...[
                  _AssigneeWorkloadLegendRow(
                    index: index + 1,
                    stat: stats[index],
                  ),
                  if (index != stats.length - 1) const SizedBox(height: 6),
                ],
              ],
            ),
    );
  }
}

class _AssigneeWorkloadLegendRow extends StatelessWidget {
  const _AssigneeWorkloadLegendRow({required this.index, required this.stat});

  final int index;
  final _AssigneeStat stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text('$index', style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Text(stat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(
          '未完了 ${stat.active} / 期限超過 ${stat.overdue}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AnalyticsLegendWrap extends StatelessWidget {
  const _AnalyticsLegendWrap({required this.items});

  final List<_AnalyticsLegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 6),
              Text(item.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

class _AnalyticsEmptyMessage extends StatelessWidget {
  const _AnalyticsEmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

class _AnalyticsStatusCard extends StatelessWidget {
  const _AnalyticsStatusCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _BreakdownData(
        label: '完了',
        value: data.doneTasks,
        fraction: data.doneRate,
      ),
      _BreakdownData(
        label: '未完了',
        value: data.openTasks,
        fraction: data.openRate,
      ),
      _BreakdownData(
        label: '期限超過',
        value: data.overdueTasks,
        fraction: data.totalTasks == 0
            ? 0
            : data.overdueTasks / data.totalTasks,
      ),
      _BreakdownData(
        label: '日付未設定',
        value: data.unscheduledTasks,
        fraction: data.totalTasks == 0
            ? 0
            : data.unscheduledTasks / data.totalTasks,
      ),
    ];

    return _AnalyticsPanel(
      icon: Icons.donut_large,
      title: '状態内訳',
      child: Column(
        children: [
          for (final row in rows) ...[
            _BreakdownRow(data: row),
            if (row != rows.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.data});

  final _BreakdownData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(data.label)),
            Text('${data.value}件'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: data.fraction.clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsAssigneeCard extends StatelessWidget {
  const _AnalyticsAssigneeCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final assignees = data.assigneeStats;

    return _AnalyticsPanel(
      icon: Icons.group_outlined,
      title: '担当者別',
      child: assignees.isEmpty
          ? const Text('担当者が設定されたタスクはありません')
          : Column(
              children: [
                for (final assignee in assignees) ...[
                  _AssigneeRow(stat: assignee),
                  if (assignee != assignees.last) const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _AssigneeRow extends StatelessWidget {
  const _AssigneeRow({required this.stat});

  final _AssigneeStat stat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stat.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${stat.done}/${stat.total}'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: stat.doneRate,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _AnalyticsDeadlineCard extends StatelessWidget {
  const _AnalyticsDeadlineCard({required this.data});

  final _ProjectAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final tasks = data.deadlineRiskTasks;

    return _AnalyticsPanel(
      icon: Icons.event_note,
      title: '期限リスク',
      child: tasks.isEmpty
          ? const Text('期限が近い未完了タスクはありません')
          : Column(
              children: [
                for (final task in tasks) ...[
                  _DeadlineRiskRow(task: task),
                  if (task != tasks.last) const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}

class _DeadlineRiskRow extends StatelessWidget {
  const _DeadlineRiskRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOverdue = _isOverdue(task);

    return Row(
      children: [
        Icon(
          isOverdue ? Icons.warning_amber : Icons.event,
          color: isOverdue ? colorScheme.error : colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                '期限 ${_formatDate(task.deadline)} ・ 進捗 ${task.completionPercent}%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyticsPanel extends StatelessWidget {
  const _AnalyticsPanel({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AnalyticsMetric {
  const _AnalyticsMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
}

class _BreakdownData {
  const _BreakdownData({
    required this.label,
    required this.value,
    required this.fraction,
  });

  final String label;
  final int value;
  final double fraction;
}

class _AssigneeStat {
  const _AssigneeStat({
    required this.name,
    required this.total,
    required this.done,
    required this.active,
    required this.overdue,
  });

  final String name;
  final int total;
  final int done;
  final int active;
  final int overdue;

  double get doneRate => total == 0 ? 0 : done / total;
}

class _ProjectAnalyticsData {
  _ProjectAnalyticsData({required this.project, required this.tasks})
    : today = DateUtils.dateOnly(DateTime.now());

  final Project project;
  final List<Task> tasks;
  final DateTime today;

  int get totalTasks => tasks.length;

  int get doneTasks => tasks.where((task) => task.isDone).length;

  int get openTasks => totalTasks - doneTasks;

  List<Task> get doneTaskList => tasks.where((task) => task.isDone).toList();

  List<Task> get activeTasks => tasks.where((task) => !task.isDone).toList();

  int get overdueTasks =>
      tasks.where((task) => _isOverdueOn(task, today)).length;

  int get unscheduledTasks => tasks
      .where((task) => task.startDate == null && task.deadline == null)
      .length;

  int get highPriorityOpenTasks =>
      tasks.where((task) => !task.isDone && (task.priority ?? 0) >= 4).length;

  int get dueSoonTasks {
    final limit = today.add(const Duration(days: 7));

    return tasks.where((task) {
      final deadline = task.deadline;
      if (task.isDone || deadline == null) {
        return false;
      }

      final day = DateUtils.dateOnly(deadline);
      return !day.isBefore(today) && !day.isAfter(limit);
    }).length;
  }

  double get doneRate => totalTasks == 0 ? 0 : doneTasks / totalTasks;

  double get openRate => totalTasks == 0 ? 0 : openTasks / totalTasks;

  double get averageProgress {
    if (tasks.isEmpty) {
      return 0;
    }

    final total = tasks.fold<double>(
      0,
      (sum, task) => sum + task.completionRatio,
    );
    return total / tasks.length;
  }

  List<_ProjectTrendPoint> get completionTrend {
    final start = today.subtract(const Duration(days: 6));

    return [
      for (var index = 0; index < 7; index += 1)
        _ProjectTrendPoint(
          date: start.add(Duration(days: index)),
          count: doneTaskList.where((task) {
            return DateUtils.isSameDay(
              task.updatedAt,
              start.add(Duration(days: index)),
            );
          }).length,
        ),
    ];
  }

  List<_ProjectDeadlineBucket> get deadlineBuckets {
    final active = activeTasks;

    return [
      _ProjectDeadlineBucket(
        label: '期限超過',
        kind: _ProjectDeadlineRiskKind.overdue,
        count: active.where((task) => _isOverdueOn(task, today)).length,
      ),
      _ProjectDeadlineBucket(
        label: '3日以内',
        kind: _ProjectDeadlineRiskKind.withinThreeDays,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          final days = DateUtils.dateOnly(deadline).difference(today).inDays;
          return days >= 0 && days <= 3;
        }).length,
      ),
      _ProjectDeadlineBucket(
        label: '7日以内',
        kind: _ProjectDeadlineRiskKind.withinSevenDays,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          final days = DateUtils.dateOnly(deadline).difference(today).inDays;
          return days > 3 && days <= 7;
        }).length,
      ),
      _ProjectDeadlineBucket(
        label: 'それ以降',
        kind: _ProjectDeadlineRiskKind.later,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          return DateUtils.dateOnly(deadline).difference(today).inDays > 7;
        }).length,
      ),
      _ProjectDeadlineBucket(
        label: '期限未設定',
        kind: _ProjectDeadlineRiskKind.noDeadline,
        count: active.where((task) => task.deadline == null).length,
      ),
    ];
  }

  Map<int, int> get priorityCounts {
    return {
      for (var priority = 1; priority <= 5; priority += 1)
        priority: activeTasks.where((task) => task.priority == priority).length,
    };
  }

  List<_AssigneeStat> get assigneeStats {
    final grouped = <String, List<Task>>{};

    for (final task in tasks) {
      final name = task.assigneeName?.trim();
      if (name == null || name.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(name, () => []).add(task);
    }

    final stats = grouped.entries.map((entry) {
      return _AssigneeStat(
        name: entry.key,
        total: entry.value.length,
        done: entry.value.where((task) => task.isDone).length,
        active: entry.value.where((task) => !task.isDone).length,
        overdue: entry.value.where((task) => _isOverdueOn(task, today)).length,
      );
    }).toList();

    stats.sort((a, b) {
      final countCompare = b.total.compareTo(a.total);
      if (countCompare != 0) {
        return countCompare;
      }

      return a.name.compareTo(b.name);
    });

    return stats.take(6).toList();
  }

  List<Task> get deadlineRiskTasks {
    final limit = today.add(const Duration(days: 14));
    final candidates = tasks.where((task) {
      final deadline = task.deadline;
      if (task.isDone || deadline == null) {
        return false;
      }

      final day = DateUtils.dateOnly(deadline);
      return day.isBefore(today) || !day.isAfter(limit);
    }).toList();

    candidates.sort((a, b) => a.deadline!.compareTo(b.deadline!));
    return candidates.take(6).toList();
  }
}

class _ProjectTrendPoint {
  const _ProjectTrendPoint({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class _ProjectDeadlineBucket {
  const _ProjectDeadlineBucket({
    required this.label,
    required this.kind,
    required this.count,
  });

  final String label;
  final _ProjectDeadlineRiskKind kind;
  final int count;

  Color color(ColorScheme colorScheme) {
    return switch (kind) {
      _ProjectDeadlineRiskKind.overdue => colorScheme.error,
      _ProjectDeadlineRiskKind.withinThreeDays => colorScheme.tertiary,
      _ProjectDeadlineRiskKind.withinSevenDays => colorScheme.primary,
      _ProjectDeadlineRiskKind.later => colorScheme.secondary,
      _ProjectDeadlineRiskKind.noDeadline => colorScheme.outline,
    };
  }

  Color onColor(ColorScheme colorScheme) {
    return switch (kind) {
      _ProjectDeadlineRiskKind.overdue => colorScheme.onError,
      _ProjectDeadlineRiskKind.withinThreeDays => colorScheme.onTertiary,
      _ProjectDeadlineRiskKind.withinSevenDays => colorScheme.onPrimary,
      _ProjectDeadlineRiskKind.later => colorScheme.onSecondary,
      _ProjectDeadlineRiskKind.noDeadline => colorScheme.surface,
    };
  }
}

enum _ProjectDeadlineRiskKind {
  overdue,
  withinThreeDays,
  withinSevenDays,
  later,
  noDeadline,
}

class _AnalyticsLegendItem {
  const _AnalyticsLegendItem({required this.color, required this.label});

  final Color color;
  final String label;
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.icon,
    required this.label,
    required this.task,
    required this.emptyText,
    required this.detailBuilder,
  });

  final IconData icon;
  final String label;
  final Task? task;
  final String emptyText;
  final String Function(Task task) detailBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            task?.title ?? emptyText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(task == null ? '未設定' : detailBuilder(task!)),
        ],
      ),
    );
  }
}

class _GanttChart extends StatefulWidget {
  const _GanttChart({
    required this.tasks,
    required this.taskRepository,
    required this.onOpenTask,
    this.height,
  });

  final List<Task> tasks;
  final TaskRepository taskRepository;
  final ValueChanged<Task> onOpenTask;
  final double? height;

  @override
  State<_GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<_GanttChart> {
  late final GanttController controller;
  int daysView = 30;

  @override
  void initState() {
    super.initState();
    controller = GanttController(
      startDate: _initialGanttStartDate(widget.tasks),
      daysViews: daysView,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handleActivityChanged(
    GanttActivity activity,
    DateTime? start,
    DateTime? end,
  ) async {
    final task = activity.data;

    if (task is! Task) {
      return;
    }

    final nextStart = start == null
        ? task.startDate
        : DateUtils.dateOnly(start);
    final nextEnd = end == null ? task.deadline : DateUtils.dateOnly(end);

    if (nextStart != null && nextEnd != null && nextEnd.isBefore(nextStart)) {
      return;
    }

    if (nextStart != null) {
      task.startDate = nextStart;
      activity.start = nextStart;
    }

    if (nextEnd != null) {
      task.deadline = nextEnd;
      activity.end = nextEnd;
    }

    controller.update();

    try {
      await widget.taskRepository.updateTask(task);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ガントの日付更新に失敗しました')));
    }
  }

  void _setDaysView(int value) {
    setState(() {
      daysView = value;
      controller.daysViews = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activities = _ganttActivities(
      context,
      widget.tasks,
      widget.onOpenTask,
    );
    controller.setActivities(activities, notify: false);

    if (activities.isEmpty) {
      return _SectionFrame(
        child: SizedBox(
          height: widget.height,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.stacked_bar_chart),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '日付が設定されたタスクがありません',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return _SectionFrame(
      child: SizedBox(
        height: widget.height ?? _ganttChartHeight(activities.length),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stacked_bar_chart),
                      const SizedBox(width: 8),
                      Text(
                        'ガントチャート',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  GanttRangeSelector(controller: controller),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    selected: {daysView},
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7日')),
                      ButtonSegment(value: 30, label: Text('30日')),
                      ButtonSegment(value: 90, label: Text('90日')),
                    ],
                    onSelectionChanged: (values) => _setDaysView(values.first),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columnFlex = _ganttColumnFlex(constraints.maxWidth);

                    return Gantt(
                      controller: controller,
                      activities: activities,
                      highlightedDates: [DateTime.now()],
                      showIsoWeek: true,
                      enableDraggable: true,
                      activitiesListFlex: columnFlex.taskName,
                      gridAreaFlex: columnFlex.timeline,
                      monthToText: (context, date) =>
                          DateFormat('yyyy/MM').format(date),
                      theme: GanttTheme.of(
                        context,
                        backgroundColor: colorScheme.surface,
                        defaultCellColor: colorScheme.primary,
                        cellHeight: 30,
                        rowPadding: 6,
                        rowsGroupPadding: 8,
                        dayMinWidth: constraints.maxWidth < 560 ? 30 : 34,
                      ),
                      onActivityChanged: _handleActivityChanged,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GanttActivityBar extends StatelessWidget {
  const _GanttActivityBar({required this.activity});

  final GanttActivity activity;

  @override
  Widget build(BuildContext context) {
    final task = activity.data is Task ? activity.data as Task : null;
    final colorScheme = Theme.of(context).colorScheme;
    final color = activity.color ?? colorScheme.primary;
    final progress = (task?.completionRatio ?? 0).clamp(0.0, 1.0).toDouble();

    return Tooltip(
      message: activity.tooltip ?? '',
      child: InkWell(
        onTap: () => activity.onCellTap?.call(activity),
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FractionallySizedBox(
                  widthFactor: progress,
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          activity.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _ganttOnColor(colorScheme, task),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (task != null && task.completionPercent > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${task.completionPercent}%',
                          style: TextStyle(
                            color: _ganttOnColor(colorScheme, task),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GanttListTitle extends StatelessWidget {
  const _GanttListTitle({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: task.isDone ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${task.completionPercent}%',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                color: task.isDone ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _TaskMeta(
                          icon: Icons.event,
                          text: _formatDate(task.deadline),
                        ),
                        if (task.startDate != null)
                          _TaskMeta(
                            icon: Icons.play_arrow,
                            text: _formatDate(task.startDate),
                          ),
                        _TaskMeta(
                          icon: Icons.priority_high,
                          text: _formatPriority(task.priority),
                        ),
                        if (task.category.trim().isNotEmpty)
                          _TaskMeta(icon: Icons.label, text: task.category),
                        if (task.assigneeName?.trim().isNotEmpty ?? false)
                          _TaskMeta(
                            icon: Icons.person_outline,
                            text: task.assigneeName!,
                          ),
                        _TaskMeta(
                          icon: Icons.percent,
                          text: '${task.completionPercent}%',
                        ),
                        if (task.comments.isNotEmpty)
                          _TaskMeta(
                            icon: Icons.chat_bubble_outline,
                            text: '${task.comments.length}',
                          ),
                      ],
                    ),
                    if (task.memo != null && task.memo!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        task.memo!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(text)],
    );
  }
}

class _EmptyTaskList extends StatelessWidget {
  const _EmptyTaskList();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: const Text('タスクがありません'),
    );
  }
}

class _IssueSection extends StatelessWidget {
  const _IssueSection({
    required this.issues,
    required this.isMutating,
    required this.onCreateIssue,
    required this.onSetIssueStatus,
  });

  final List<ProjectIssue> issues;
  final bool isMutating;
  final VoidCallback onCreateIssue;
  final void Function(ProjectIssue issue, ProjectIssueStatus status)
  onSetIssueStatus;

  @override
  Widget build(BuildContext context) {
    final sortedIssues = [...issues]
      ..sort((a, b) {
        if (a.isOpen != b.isOpen) {
          return a.isOpen ? -1 : 1;
        }

        return b.updatedAt.compareTo(a.updatedAt);
      });
    final openCount = issues.where((issue) => issue.isOpen).length;

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.adjust, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Issue',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Text('$openCount open / ${issues.length}件'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onCreateIssue,
                  icon: const Icon(Icons.add),
                  label: const Text('追加'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sortedIssues.isEmpty)
              const _EmptyLine(text: 'Issue はまだありません')
            else
              for (final issue in sortedIssues) ...[
                _IssueCard(
                  issue: issue,
                  isMutating: isMutating,
                  onSetStatus: (status) => onSetIssueStatus(issue, status),
                ),
                if (issue != sortedIssues.last) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.isMutating,
    required this.onSetStatus,
  });

  final ProjectIssue issue;
  final bool isMutating;
  final ValueChanged<ProjectIssueStatus> onSetStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _issueStatusColor(colorScheme, issue.status);
    final nextStatus = issue.isOpen
        ? ProjectIssueStatus.closed
        : ProjectIssueStatus.open;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_issueStatusIcon(issue.status), color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.title.isEmpty ? '無題の Issue' : issue.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _IssueMeta(icon: Icons.tag, text: _issueNumber(issue)),
                        _IssueMeta(
                          icon: _issueStatusIcon(issue.status),
                          text: _issueStatusLabel(issue.status),
                        ),
                        _IssueMeta(
                          icon: Icons.person_outline,
                          text: issue.authorName,
                        ),
                        _IssueMeta(
                          icon: Icons.update,
                          text: _dateFormat.format(issue.updatedAt),
                        ),
                        if (issue.externalUrl?.trim().isNotEmpty ?? false)
                          const _IssueMeta(icon: Icons.link, text: 'GitHub'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: isMutating ? null : () => onSetStatus(nextStatus),
                icon: Icon(_issueActionIcon(issue.status)),
                label: Text(_issueActionLabel(issue.status)),
              ),
            ],
          ),
          if (issue.body != null && issue.body!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(issue.body!, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (issue.labels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in issue.labels)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _IssueMeta extends StatelessWidget {
  const _IssueMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(text)],
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

class _GanttTaskRange {
  const _GanttTaskRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _GanttColumnFlex {
  const _GanttColumnFlex({required this.taskName, required this.timeline});

  final int taskName;
  final int timeline;
}

Task? _nearestDeadlineTask(List<Task> tasks) {
  final candidates = tasks
      .where((task) => !task.isDone && task.deadline != null)
      .toList();
  candidates.sort((a, b) => a.deadline!.compareTo(b.deadline!));

  return candidates.isEmpty ? null : candidates.first;
}

Task? _highestPriorityTask(List<Task> tasks) {
  final candidates = tasks
      .where((task) => !task.isDone && task.priority != null)
      .toList();
  candidates.sort((a, b) {
    final priorityCompare = b.priority!.compareTo(a.priority!);
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    return _compareDeadlineThenCreatedAt(a, b);
  });

  return candidates.isEmpty ? null : candidates.first;
}

List<Task> _sortTasks(List<Task> tasks) {
  final sortedTasks = [...tasks];
  sortedTasks.sort((a, b) {
    if (a.isDone != b.isDone) {
      return a.isDone ? 1 : -1;
    }

    return _compareDeadlineThenCreatedAt(a, b);
  });

  return sortedTasks;
}

int _compareDeadlineThenCreatedAt(Task a, Task b) {
  if (a.deadline != null && b.deadline != null) {
    return a.deadline!.compareTo(b.deadline!);
  }

  if (a.deadline != null) {
    return -1;
  }

  if (b.deadline != null) {
    return 1;
  }

  return b.createdAt.compareTo(a.createdAt);
}

List<GanttActivity> _ganttActivities(
  BuildContext context,
  List<Task> tasks,
  ValueChanged<Task> onOpenTask,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final activities = <GanttActivity>[];

  for (final task in _sortTasks(tasks)) {
    final range = _ganttTaskRange(task);

    if (range == null) {
      continue;
    }

    activities.add(
      GanttActivity<Task>(
        key: task.id.isEmpty
            ? '${task.title}-${task.createdAt.microsecondsSinceEpoch}'
            : task.id,
        start: range.start,
        end: range.end,
        title: task.title.isEmpty ? '無題のタスク' : task.title,
        listTitleWidget: _GanttListTitle(
          task: task,
          onTap: () => onOpenTask(task),
        ),
        tooltip: _ganttTooltip(task, range),
        color: _ganttActivityColor(colorScheme, task),
        data: task,
        builder: (activity) => _GanttActivityBar(activity: activity),
        onCellTap: (activity) {
          final data = activity.data;
          if (data is Task) {
            onOpenTask(data);
          }
        },
      ),
    );
  }

  return activities;
}

_GanttTaskRange? _ganttTaskRange(Task task) {
  final rawStart = task.startDate ?? task.deadline;
  final rawEnd = task.deadline ?? task.startDate;

  if (rawStart == null || rawEnd == null) {
    return null;
  }

  final start = DateUtils.dateOnly(rawStart);
  final end = DateUtils.dateOnly(rawEnd);

  return _GanttTaskRange(
    start: end.isBefore(start) ? end : start,
    end: end.isBefore(start) ? start : end,
  );
}

DateTime _initialGanttStartDate(List<Task> tasks) {
  DateTime? earliestStart;

  for (final task in tasks) {
    final range = _ganttTaskRange(task);

    if (range == null) {
      continue;
    }

    if (earliestStart == null || range.start.isBefore(earliestStart)) {
      earliestStart = range.start;
    }
  }

  return (earliestStart ?? DateUtils.dateOnly(DateTime.now())).subtract(
    const Duration(days: 7),
  );
}

double _ganttChartHeight(int activityCount) {
  final preferredHeight = 150.0 + (activityCount * 44.0);

  if (preferredHeight < 280) {
    return 280;
  }

  if (preferredHeight > 560) {
    return 560;
  }

  return preferredHeight;
}

_GanttColumnFlex _ganttColumnFlex(double width) {
  final desiredTaskNameWidth = width >= 1200
      ? 200.0
      : width >= 760
      ? 175.0
      : 145.0;
  final minTotalFlex = width < 520 ? 3 : 4;
  final totalFlex = (width / desiredTaskNameWidth).round().clamp(
    minTotalFlex,
    9,
  );

  return _GanttColumnFlex(taskName: 1, timeline: totalFlex - 1);
}

Color _ganttActivityColor(ColorScheme colorScheme, Task task) {
  if (task.isDone) {
    return colorScheme.secondary;
  }

  if (_isOverdue(task)) {
    return colorScheme.error;
  }

  if ((task.priority ?? 0) >= 4) {
    return colorScheme.tertiary;
  }

  return colorScheme.primary;
}

Color _ganttOnColor(ColorScheme colorScheme, Task? task) {
  if (task == null) {
    return colorScheme.onPrimary;
  }

  if (task.isDone) {
    return colorScheme.onSecondary;
  }

  if (_isOverdue(task)) {
    return colorScheme.onError;
  }

  if ((task.priority ?? 0) >= 4) {
    return colorScheme.onTertiary;
  }

  return colorScheme.onPrimary;
}

bool _isOverdue(Task task) {
  return _isOverdueOn(task, DateUtils.dateOnly(DateTime.now()));
}

bool _isOverdueOn(Task task, DateTime today) {
  final deadline = task.deadline;

  if (task.isDone || deadline == null) {
    return false;
  }

  return DateUtils.dateOnly(deadline).isBefore(today);
}

String _ganttTooltip(Task task, _GanttTaskRange range) {
  final category = task.category.trim();
  final lines = [
    task.title,
    '${_formatDate(range.start)} - ${_formatDate(range.end)}',
    _formatPriority(task.priority),
    '進捗 ${task.completionPercent}%',
    if (category.isNotEmpty) category,
  ];

  return lines.join('\n');
}

FlTitlesData _projectLineChartTitles(
  BuildContext context,
  List<_ProjectTrendPoint> trend,
) {
  final textStyle = Theme.of(context).textTheme.labelSmall;

  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        getTitlesWidget: (value, meta) {
          if (value % 1 != 0) {
            return const SizedBox.shrink();
          }

          return SideTitleWidget(
            meta: meta,
            child: Text(value.toInt().toString(), style: textStyle),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 32,
        getTitlesWidget: (value, meta) {
          final index = value.toInt();
          if (index < 0 || index >= trend.length) {
            return const SizedBox.shrink();
          }

          return SideTitleWidget(
            meta: meta,
            child: Text(
              _shortDateFormat.format(trend[index].date),
              style: textStyle,
            ),
          );
        },
      ),
    ),
  );
}

FlTitlesData _projectBarChartTitles(
  BuildContext context, {
  required String Function(double value) bottomLabel,
}) {
  final textStyle = Theme.of(context).textTheme.labelSmall;

  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        getTitlesWidget: (value, meta) {
          if (value % 1 != 0) {
            return const SizedBox.shrink();
          }

          return SideTitleWidget(
            meta: meta,
            child: Text(value.toInt().toString(), style: textStyle),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 30,
        getTitlesWidget: (value, meta) {
          return SideTitleWidget(
            meta: meta,
            child: Text(bottomLabel(value), style: textStyle),
          );
        },
      ),
    ),
  );
}

Color _priorityColor(ColorScheme colorScheme, int priority) {
  if (priority >= 5) {
    return colorScheme.error;
  }
  if (priority >= 4) {
    return colorScheme.tertiary;
  }

  return colorScheme.primary;
}

String _formatDate(DateTime? date) {
  if (date == null) {
    return '未設定';
  }

  return _dateFormat.format(date);
}

String _formatPercent(double value) {
  return '${(value.clamp(0, 1) * 100).round()}%';
}

String _formatPriority(int? priority) {
  if (priority == null) {
    return '重要度なし';
  }

  return '重要度 $priority';
}

List<String> _parseIssueLabels(String rawLabels) {
  return rawLabels
      .split(',')
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toSet()
      .toList();
}

String _issueNumber(ProjectIssue issue) {
  final number = issue.issueNumber;
  return number == null ? '#-' : '#$number';
}

String _issueStatusLabel(ProjectIssueStatus status) {
  return switch (status) {
    ProjectIssueStatus.open => 'open',
    ProjectIssueStatus.closed => 'closed',
  };
}

IconData _issueStatusIcon(ProjectIssueStatus status) {
  return switch (status) {
    ProjectIssueStatus.open => Icons.adjust,
    ProjectIssueStatus.closed => Icons.check_circle,
  };
}

IconData _issueActionIcon(ProjectIssueStatus status) {
  return switch (status) {
    ProjectIssueStatus.open => Icons.check_circle_outline,
    ProjectIssueStatus.closed => Icons.replay,
  };
}

String _issueActionLabel(ProjectIssueStatus status) {
  return switch (status) {
    ProjectIssueStatus.open => 'close',
    ProjectIssueStatus.closed => 'reopen',
  };
}

Color _issueStatusColor(ColorScheme colorScheme, ProjectIssueStatus status) {
  return switch (status) {
    ProjectIssueStatus.open => colorScheme.primary,
    ProjectIssueStatus.closed => colorScheme.outline,
  };
}
