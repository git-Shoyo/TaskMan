import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:taskman/repositories/organization_repository.dart';
import 'package:taskman/repositories/user_repository.dart';
import 'package:taskman/systems/app_user.dart';
import 'package:taskman/systems/auth_scope.dart';

class AddOrganizationScreen extends StatefulWidget {
  const AddOrganizationScreen({super.key});

  @override
  State<AddOrganizationScreen> createState() => _AddOrganizationScreenState();
}

class _AddOrganizationScreenState extends State<AddOrganizationScreen> {
  final organizationNameController = TextEditingController();
  final organizationDetailController = TextEditingController();
  final userSearchController = TextEditingController();
  final organizationRepository = OrganizationRepository();
  final userRepository = UserRepository();

  bool isSaving = false;
  bool isSearchingUsers = false;
  UserSearchField userSearchField = UserSearchField.email;
  List<AppUser> selectedMembers = [];
  List<AppUser> userSearchResults = [];
  String? userSearchMessage;

  Future<void> createOrganization() async {
    final organizationName = organizationNameController.text.trim();
    final organizationDetail = organizationDetailController.text.trim();

    if (organizationName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('組織名を入力してください')));
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final currentUser =
          AuthScope.maybeOf(context)?.currentUser ?? AppUser.local();

      await organizationRepository.addOrganization(
        name: organizationName,
        description: organizationDetail.isEmpty ? null : organizationDetail,
        ownerId: currentUser.id,
        memberIds: selectedMembers.map((user) => user.id).toList(),
      );

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
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint(
        'Organization save failed: ${error.plugin} / ${error.code} / ${error.message}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_organizationSaveErrorMessage(error))),
      );
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      debugPrint('Organization save failed: $error\n$stackTrace');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('組織の保存に失敗しました: $error')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> searchUsers({
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
      final currentUserId =
          AuthScope.maybeOf(context)?.currentUser.id ?? AppUser.localUserId;
      final users = await userRepository.searchUsers(
        query: rawQuery,
        field: field,
      );
      final selectedIds = selectedMembers.map((user) => user.id).toSet();
      final filteredUsers = users
          .where(
            (user) =>
                user.id != currentUserId &&
                user.id != AppUser.localUserId &&
                !selectedIds.contains(user.id),
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

  Future<void> openQrSearchDialog() async {
    final qrController = TextEditingController();

    try {
      final qrValue = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('QRコードから追加'),
            content: TextField(
              controller: qrController,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '読み取ったQRコードの文字列',
                alignLabelWithHint: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, qrController.text),
                icon: const Icon(Icons.search),
                label: const Text('検索'),
              ),
            ],
          );
        },
      );

      if (!mounted || qrValue == null || qrValue.trim().isEmpty) {
        return;
      }

      userSearchController.text = qrValue.trim();
      await searchUsers(query: qrValue, searchField: UserSearchField.qrCode);
    } finally {
      qrController.dispose();
    }
  }

  void addMember(AppUser user) {
    if (selectedMembers.any((member) => member.id == user.id)) {
      return;
    }

    setState(() {
      selectedMembers = [...selectedMembers, user];
      userSearchResults.removeWhere((result) => result.id == user.id);
      userSearchMessage = userSearchResults.isEmpty ? '追加済みです' : null;
    });
  }

  void removeMember(AppUser user) {
    setState(() {
      selectedMembers.removeWhere((member) => member.id == user.id);
    });
  }

  @override
  void dispose() {
    organizationNameController.dispose();
    organizationDetailController.dispose();
    userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('組織作成')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: isSaving ? null : createOrganization,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(isSaving ? '保存中...' : '保存'),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(icon: Icons.apartment, title: '基本情報'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: organizationNameController,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '組織名',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    child: TextField(
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      maxLength: 1000,
                      controller: organizationDetailController,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '詳細',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _MemberPickerSection(
                    selectedMembers: selectedMembers,
                    searchResults: userSearchResults,
                    searchMessage: userSearchMessage,
                    searchField: userSearchField,
                    searchController: userSearchController,
                    isSearching: isSearchingUsers,
                    onSearchFieldChanged: (field) {
                      setState(() {
                        userSearchField = field;
                        userSearchMessage = null;
                        userSearchResults = [];
                      });
                    },
                    onSearch: () => searchUsers(),
                    onQrSearch: openQrSearchDialog,
                    onAddMember: addMember,
                    onRemoveMember: removeMember,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _organizationSaveErrorMessage(FirebaseException error) {
  switch (error.code) {
    case 'permission-denied':
      return '組織を保存できませんでした。Firestore ルールをデプロイしてください';
    case 'unavailable':
      return 'Firebase に接続できませんでした。ネットワークを確認してください';
    default:
      return '組織の保存に失敗しました (${error.plugin}/${error.code})';
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
        Icon(icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _MemberPickerSection extends StatelessWidget {
  const _MemberPickerSection({
    required this.selectedMembers,
    required this.searchResults,
    required this.searchMessage,
    required this.searchField,
    required this.searchController,
    required this.isSearching,
    required this.onSearchFieldChanged,
    required this.onSearch,
    required this.onQrSearch,
    required this.onAddMember,
    required this.onRemoveMember,
  });

  final List<AppUser> selectedMembers;
  final List<AppUser> searchResults;
  final String? searchMessage;
  final UserSearchField searchField;
  final TextEditingController searchController;
  final bool isSearching;
  final ValueChanged<UserSearchField> onSearchFieldChanged;
  final VoidCallback onSearch;
  final VoidCallback onQrSearch;
  final ValueChanged<AppUser> onAddMember;
  final ValueChanged<AppUser> onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final searchInput = TextField(
      controller: searchController,
      enabled: !isSearching,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: _searchFieldLabel(searchField),
        prefixIcon: Icon(_searchFieldIcon(searchField)),
        isDense: true,
      ),
    );
    final searchButton = FilledButton.icon(
      onPressed: isSearching ? null : onSearch,
      icon: isSearching
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Text('検索'),
    );
    final qrButton = IconButton.filledTonal(
      onPressed: isSearching ? null : onQrSearch,
      tooltip: 'QRコードで検索',
      icon: const Icon(Icons.qr_code_scanner),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.group_add, title: '組織メンバー'),
        const SizedBox(height: 10),
        if (selectedMembers.isEmpty)
          Text('追加ユーザーなし', style: Theme.of(context).textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedMembers.map((user) {
              return InputChip(
                avatar: CircleAvatar(child: Text(_userInitial(user))),
                label: Text(user.label),
                onDeleted: () => onRemoveMember(user),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
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
          onSelectionChanged: isSearching
              ? null
              : (values) => onSearchFieldChanged(values.first),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 640) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: searchInput),
                  const SizedBox(width: 8),
                  searchButton,
                  const SizedBox(width: 4),
                  qrButton,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchInput,
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [searchButton, const SizedBox(width: 4), qrButton],
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
                onPressed: () => onAddMember(user),
                tooltip: '追加',
                icon: const Icon(Icons.person_add_alt_1),
              ),
            ),
        ],
      ],
    );
  }
}

String _searchFieldLabel(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => 'メールアドレス',
    UserSearchField.userId => 'ユーザーID',
    UserSearchField.qrCode => 'QRコード',
  };
}

IconData _searchFieldIcon(UserSearchField field) {
  return switch (field) {
    UserSearchField.email => Icons.mail_outline,
    UserSearchField.userId => Icons.badge_outlined,
    UserSearchField.qrCode => Icons.qr_code_scanner,
  };
}

String _userInitial(AppUser user) {
  final label = user.label.trim();

  if (label.isEmpty) {
    return '?';
  }

  return label.characters.first.toUpperCase();
}
