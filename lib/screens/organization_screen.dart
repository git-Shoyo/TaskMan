import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/issue_repository.dart';
import 'package:taskman/repositories/organization_repository.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/screens/add_organization/add_organization_screen.dart';
import 'package:taskman/screens/add_project/add_project_screen.dart';
import 'package:taskman/screens/project_screen.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/issue.dart';
import 'package:taskman/systems/organization.dart';
import 'package:taskman/systems/project.dart';

final DateFormat _dateTimeFormat = DateFormat('yyyy/MM/dd HH:mm');

class OrganizationScreen extends StatefulWidget {
  const OrganizationScreen({super.key});

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  final organizationRepository = OrganizationRepository();
  final projectRepository = ProjectRepository();
  final issueRepository = IssueRepository();
  final userRepository = UserRepository();

  String? selectedOrganizationId;

  void _openAddOrganizationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddOrganizationScreen()),
    );
  }

  void _openAddProjectScreen(Organization organization) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProjectScreen(organization: organization),
      ),
    );
  }

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(project: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;

    return LayoutBuilder(
      builder: (context, constraints) {
        final showDetail = constraints.maxWidth >= 760;

        return Scaffold(
          floatingActionButton: showDetail
              ? null
              : FloatingActionButton(
                  onPressed: _openAddOrganizationScreen,
                  tooltip: '組織作成',
                  child: const Icon(Icons.apartment),
                ),
          body: SafeArea(
            child: StreamBuilder<List<Organization>>(
              stream: organizationRepository.watchOrganizations(
                memberId: currentUser.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('組織の読み込みに失敗しました'));
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final organizations = snapshot.data ?? const <Organization>[];
                final selectedOrganization = _findOrganization(
                  organizations,
                  selectedOrganizationId,
                );

                return Row(
                  children: [
                    SizedBox(
                      width: showDetail ? 320 : constraints.maxWidth,
                      child: _OrganizationList(
                        organizations: organizations,
                        selectedOrganizationId: selectedOrganizationId,
                        showHeader: showDetail,
                        onCreateOrganization: _openAddOrganizationScreen,
                        onSelectOrganization: (organization) {
                          if (showDetail) {
                            setState(() {
                              selectedOrganizationId = organization.id;
                            });
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OrganizationDetailScreen(
                                organization: organization,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (showDetail) ...[
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selectedOrganization == null
                            ? const Center(child: Text('組織を選択してください'))
                            : OrganizationDetailScreen(
                                key: ValueKey(selectedOrganization.id),
                                organization: selectedOrganization,
                                showAppBar: false,
                                projectRepository: projectRepository,
                                issueRepository: issueRepository,
                                userRepository: userRepository,
                                onCreateProject: () =>
                                    _openAddProjectScreen(selectedOrganization),
                                onOpenProject: _openProject,
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

  Organization? _findOrganization(
    List<Organization> organizations,
    String? organizationId,
  ) {
    if (organizationId == null) {
      return null;
    }

    for (final organization in organizations) {
      if (organization.id == organizationId) {
        return organization;
      }
    }

    return null;
  }
}

class _OrganizationList extends StatelessWidget {
  const _OrganizationList({
    required this.organizations,
    required this.selectedOrganizationId,
    required this.showHeader,
    required this.onCreateOrganization,
    required this.onSelectOrganization,
  });

  final List<Organization> organizations;
  final String? selectedOrganizationId;
  final bool showHeader;
  final VoidCallback onCreateOrganization;
  final ValueChanged<Organization> onSelectOrganization;

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
                    '組織',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onCreateOrganization,
                  icon: const Icon(Icons.add_business),
                  label: const Text('作成'),
                ),
              ],
            ),
          ),
        Expanded(
          child: organizations.isEmpty
              ? _EmptyOrganizationList(
                  onCreateOrganization: onCreateOrganization,
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(12, showHeader ? 8 : 12, 12, 12),
                  itemCount: organizations.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final organization = organizations[index];
                    final isSelected =
                        selectedOrganizationId == organization.id;

                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        selected: isSelected,
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          child: const Icon(Icons.apartment),
                        ),
                        title: Text(
                          organization.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${organization.memberIds.length}人 / ${organization.description ?? '詳細なし'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelectOrganization(organization),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyOrganizationList extends StatelessWidget {
  const _EmptyOrganizationList({required this.onCreateOrganization});

  final VoidCallback onCreateOrganization;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment, size: 40),
            const SizedBox(height: 12),
            const Text('組織がありません'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateOrganization,
              icon: const Icon(Icons.add_business),
              label: const Text('組織作成'),
            ),
          ],
        ),
      ),
    );
  }
}

class OrganizationDetailScreen extends StatelessWidget {
  OrganizationDetailScreen({
    super.key,
    required this.organization,
    this.showAppBar = true,
    ProjectRepository? projectRepository,
    IssueRepository? issueRepository,
    UserRepository? userRepository,
    this.onCreateProject,
    this.onOpenProject,
  }) : projectRepository = projectRepository ?? ProjectRepository(),
       issueRepository = issueRepository ?? IssueRepository(),
       userRepository = userRepository ?? UserRepository();

  final Organization organization;
  final bool showAppBar;
  final ProjectRepository projectRepository;
  final IssueRepository issueRepository;
  final UserRepository userRepository;
  final VoidCallback? onCreateProject;
  final ValueChanged<Project>? onOpenProject;

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;
    final canManageOrganization = currentUser.id == organization.ownerId;
    final createProject =
        onCreateProject ??
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  AddProjectScreen(organization: organization),
            ),
          );
        };
    final openProject =
        onOpenProject ??
        (Project project) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProjectDetailScreen(project: project),
            ),
          );
        };
    final editOrganization = canManageOrganization
        ? () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    EditOrganizationScreen(organization: organization),
              ),
            );
          }
        : null;

    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(organization.name)) : null,
      body: SafeArea(
        top: !showAppBar,
        child: StreamBuilder<List<Project>>(
          stream: projectRepository.watchProjects(
            memberId: currentUser.id,
            organizationId: organization.id,
          ),
          builder: (context, projectSnapshot) {
            if (projectSnapshot.hasError) {
              return const Center(child: Text('プロジェクトの読み込みに失敗しました'));
            }

            final projects = projectSnapshot.data ?? const <Project>[];

            return StreamBuilder<List<ProjectIssue>>(
              stream: issueRepository.watchIssues(
                projectIds: projects.map((project) => project.id),
              ),
              builder: (context, issueSnapshot) {
                final isLoadingProjects =
                    projectSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !projectSnapshot.hasData;
                final isLoadingIssues =
                    issueSnapshot.connectionState == ConnectionState.waiting &&
                    !issueSnapshot.hasData;

                if (isLoadingProjects || isLoadingIssues) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (issueSnapshot.hasError) {
                  return const Center(child: Text('Issue の読み込みに失敗しました'));
                }

                return _OrganizationDetailContent(
                  organization: organization,
                  projects: projects,
                  issues: issueSnapshot.data ?? const <ProjectIssue>[],
                  userRepository: userRepository,
                  onCreateProject: createProject,
                  onOpenProject: openProject,
                  onEditOrganization: editOrganization,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _OrganizationDetailContent extends StatelessWidget {
  const _OrganizationDetailContent({
    required this.organization,
    required this.projects,
    required this.issues,
    required this.userRepository,
    required this.onCreateProject,
    required this.onOpenProject,
    required this.onEditOrganization,
  });

  final Organization organization;
  final List<Project> projects;
  final List<ProjectIssue> issues;
  final UserRepository userRepository;
  final VoidCallback onCreateProject;
  final ValueChanged<Project> onOpenProject;
  final VoidCallback? onEditOrganization;

  @override
  Widget build(BuildContext context) {
    final openIssues = issues.where((issue) => issue.isOpen).toList();
    final projectById = {for (final project in projects) project.id: project};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _OrganizationHeader(
          organization: organization,
          projectCount: projects.length,
          openIssueCount: openIssues.length,
          onCreateProject: onCreateProject,
          onEditOrganization: onEditOrganization,
        ),
        if (organization.description != null &&
            organization.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(organization.description!),
        ],
        const SizedBox(height: 16),
        _MemberSection(
          organization: organization,
          userRepository: userRepository,
        ),
        const SizedBox(height: 16),
        _ProjectSection(
          projects: projects,
          onCreateProject: onCreateProject,
          onOpenProject: onOpenProject,
        ),
        const SizedBox(height: 16),
        _IssueSection(issues: issues, projectById: projectById),
      ],
    );
  }
}

class _OrganizationHeader extends StatelessWidget {
  const _OrganizationHeader({
    required this.organization,
    required this.projectCount,
    required this.openIssueCount,
    required this.onCreateProject,
    required this.onEditOrganization,
  });

  final Organization organization;
  final int projectCount;
  final int openIssueCount;
  final VoidCallback onCreateProject;
  final VoidCallback? onEditOrganization;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apartment),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  organization.name,
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
            Chip(
              avatar: const Icon(Icons.folder, size: 18),
              label: Text('$projectCount プロジェクト'),
            ),
            Chip(
              avatar: const Icon(Icons.adjust, size: 18),
              label: Text('$openIssueCount open Issue'),
            ),
            FilledButton.icon(
              onPressed: onCreateProject,
              icon: const Icon(Icons.create_new_folder),
              label: const Text('プロジェクト作成'),
            ),
            if (onEditOrganization != null)
              OutlinedButton.icon(
                onPressed: onEditOrganization,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('編集'),
              ),
          ],
        ),
      ],
    );
  }
}

class EditOrganizationScreen extends StatefulWidget {
  const EditOrganizationScreen({super.key, required this.organization});

  final Organization organization;

  @override
  State<EditOrganizationScreen> createState() => _EditOrganizationScreenState();
}

class _EditOrganizationScreenState extends State<EditOrganizationScreen> {
  final organizationRepository = OrganizationRepository();
  final userRepository = UserRepository();
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final userSearchController = TextEditingController();

  bool isLoadingMembers = true;
  bool isSearchingUsers = false;
  bool isSaving = false;
  bool isArchiving = false;
  UserSearchField userSearchField = UserSearchField.email;
  List<AppUser> members = [];
  List<AppUser> userSearchResults = [];
  String? userSearchMessage;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.organization.name;
    descriptionController.text = widget.organization.description ?? '';
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
      final loadedMembers = await userRepository.fetchOrganizationMembers(
        widget.organization,
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
    if (user.id == widget.organization.ownerId) {
      return;
    }

    setState(() {
      members.removeWhere((member) => member.id == user.id);
    });
  }

  Future<void> _saveOrganization() async {
    final name = nameController.text.trim();
    final description = descriptionController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('組織名を入力してください')));
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final memberIds = <String>{
        widget.organization.ownerId,
        ...members.map((member) => member.id),
      }.where((id) => id.trim().isNotEmpty).toList();
      final memberRoles = <String, String>{
        for (final memberId in memberIds)
          memberId: widget.organization.memberRoles[memberId] ?? 'member',
        widget.organization.ownerId: 'owner',
      };
      final updatedOrganization = Organization(
        id: widget.organization.id,
        name: name,
        description: description.isEmpty ? null : description,
        ownerId: widget.organization.ownerId,
        memberIds: memberIds,
        memberRoles: memberRoles,
        createdAt: widget.organization.createdAt,
        updatedAt: widget.organization.updatedAt,
        isArchived: widget.organization.isArchived,
        color: widget.organization.color,
      );

      await organizationRepository.updateOrganization(updatedOrganization);

      if (!mounted) {
        return;
      }

      Navigator.pop(context);
    } on DuplicateOrganizationNameException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同じ名前の組織が既にあります')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('組織の更新に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> _archiveOrganization() async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('組織を削除しますか'),
          content: Text('「${widget.organization.name}」を削除します。配下のプロジェクトは残ります。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (shouldArchive != true || !mounted) {
      return;
    }

    setState(() {
      isArchiving = true;
    });

    try {
      await organizationRepository.archiveOrganization(widget.organization);

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
      ).showSnackBar(const SnackBar(content: Text('組織の削除に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isArchiving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = isSaving || isArchiving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('組織編集'),
        actions: [
          IconButton(
            onPressed: isBusy ? null : _saveOrganization,
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
              enabled: !isBusy,
              maxLength: 50,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '組織名',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              enabled: !isBusy,
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
            _OrganizationMemberEditSection(
              ownerId: widget.organization.ownerId,
              members: members,
              searchResults: userSearchResults,
              searchMessage: userSearchMessage,
              searchField: userSearchField,
              searchController: userSearchController,
              isLoadingMembers: isLoadingMembers,
              isSearching: isSearchingUsers,
              isSaving: isBusy,
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
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: isBusy ? null : _archiveOrganization,
              icon: isArchiving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('組織を削除'),
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
      ),
    );
  }
}

class _OrganizationMemberEditSection extends StatelessWidget {
  const _OrganizationMemberEditSection({
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
        labelText: _organizationEditSearchFieldLabel(searchField),
        prefixIcon: Icon(_organizationEditSearchFieldIcon(searchField)),
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
                  child: _SectionTitle(icon: Icons.groups_2, title: 'メンバー'),
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
                      avatar: CircleAvatar(child: Text(_userInitial(member))),
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
                  leading: CircleAvatar(child: Text(_userInitial(user))),
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

String _organizationEditSearchFieldLabel(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => 'メールアドレス',
    UserSearchField.userId => 'ユーザーID',
    UserSearchField.qrCode => 'QRコード',
  };
}

IconData _organizationEditSearchFieldIcon(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => Icons.mail_outline,
    UserSearchField.userId => Icons.badge_outlined,
    UserSearchField.qrCode => Icons.qr_code_scanner,
  };
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.organization,
    required this.userRepository,
  });

  final Organization organization;
  final UserRepository userRepository;

  @override
  Widget build(BuildContext context) {
    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<AppUser>>(
          future: userRepository.fetchOrganizationMembers(organization),
          builder: (context, snapshot) {
            final members = snapshot.data ?? const <AppUser>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(icon: Icons.groups_2, title: 'メンバー'),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  const Text('メンバーの読み込みに失敗しました')
                else if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final member in members)
                        Chip(
                          avatar: CircleAvatar(
                            child: Text(_userInitial(member)),
                          ),
                          label: Text(member.label),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.projects,
    required this.onCreateProject,
    required this.onOpenProject,
  });

  final List<Project> projects;
  final VoidCallback onCreateProject;
  final ValueChanged<Project> onOpenProject;

  @override
  Widget build(BuildContext context) {
    final sortedProjects = [...projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _SectionTitle(
                    icon: Icons.folder_copy,
                    title: 'プロジェクト',
                  ),
                ),
                IconButton(
                  onPressed: onCreateProject,
                  tooltip: 'プロジェクト作成',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sortedProjects.isEmpty)
              const _EmptyLine(text: 'この組織のプロジェクトはまだありません')
            else
              for (final project in sortedProjects) ...[
                _ProjectTile(
                  project: project,
                  onTap: () => onOpenProject(project),
                ),
                if (project != sortedProjects.last) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.folder),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '更新 ${_dateTimeFormat.format(project.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueSection extends StatelessWidget {
  const _IssueSection({required this.issues, required this.projectById});

  final List<ProjectIssue> issues;
  final Map<String, Project> projectById;

  @override
  Widget build(BuildContext context) {
    final sortedIssues = [...issues]
      ..sort((a, b) {
        if (a.isOpen != b.isOpen) {
          return a.isOpen ? -1 : 1;
        }

        return b.updatedAt.compareTo(a.updatedAt);
      });
    final visibleIssues = sortedIssues.take(8).toList();

    return _SectionFrame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(icon: Icons.adjust, title: 'Issue'),
            const SizedBox(height: 12),
            if (sortedIssues.isEmpty)
              const _EmptyLine(text: 'この組織の Issue はまだありません')
            else
              for (final issue in visibleIssues) ...[
                _IssueTile(issue: issue, project: projectById[issue.projectId]),
                if (issue != visibleIssues.last) const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.project});

  final ProjectIssue issue;
  final Project? project;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = issue.isOpen
        ? colorScheme.primary
        : colorScheme.outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            issue.isOpen ? Icons.adjust : Icons.check_circle,
            color: statusColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title.isEmpty ? '無題の Issue' : issue.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(_issueNumber(issue)),
                    if (project != null) Text(project!.name),
                    Text(issue.isOpen ? 'open' : 'closed'),
                    Text('更新 ${_dateTimeFormat.format(issue.updatedAt)}'),
                  ],
                ),
                if (issue.labels.isNotEmpty) ...[
                  const SizedBox(height: 6),
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
          ),
        ],
      ),
    );
  }
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

String _issueNumber(ProjectIssue issue) {
  final number = issue.issueNumber;
  return number == null ? '#-' : '#$number';
}

String _userInitial(AppUser user) {
  final label = user.label.trim();

  if (label.isEmpty) {
    return '?';
  }

  return label.characters.first.toUpperCase();
}
