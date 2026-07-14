import 'package:flutter/material.dart';
import 'package:taskman/repositories/project_repository.dart';

// stateありウィジット
class AddProjectScreen extends StatefulWidget {
  const AddProjectScreen({super.key});

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

/// Projectを追加するスクリーン
/// 情報として, タイトル・詳細を記入する.
class _AddProjectScreenState extends State<AddProjectScreen> {
  final projectNameController = TextEditingController();
  final projectDetailController = TextEditingController();
  final projectRepository = ProjectRepository();

  bool isSaving = false;

  Future<void> createProject() async {
    final projectName = projectNameController.text.trim();
    final projectDetail = projectDetailController.text.trim();

    if (projectName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('プロジェクトタイトルを入力してください')));
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await projectRepository.addProject(
        name: projectName,
        description: projectDetail.isEmpty ? null : projectDetail,
      );

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
      ).showSnackBar(const SnackBar(content: Text('プロジェクトの保存に失敗しました')));
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    projectNameController.dispose();
    projectDetailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('プロジェクト作成'),
        actions: [
          IconButton(
            onPressed: isSaving ? null : createProject,
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
            const outerPadding = 10.0;
            const cardPadding = 16.0;
            const headerHeight = 24.0;
            const titleFieldHeight = 76.0;
            const verticalGaps = 20.0;
            const minDetailHeight = 96.0;

            final remainingHeight =
                constraints.maxHeight -
                (outerPadding * 2) -
                (cardPadding * 2) -
                headerHeight -
                titleFieldHeight -
                verticalGaps;
            final detailHeight = remainingHeight < minDetailHeight
                ? minDetailHeight
                : remainingHeight;
            final cardMinHeight = constraints.maxHeight > (outerPadding * 2)
                ? constraints.maxHeight - (outerPadding * 2)
                : 0.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(outerPadding),
              child: Container(
                constraints: BoxConstraints(minHeight: cardMinHeight),
                padding: const EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '基本情報',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: TextField(
                        controller: projectNameController,
                        maxLength: 50,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'プロジェクトタイトル',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: SizedBox(
                        height: detailHeight,
                        child: TextField(
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          maxLength: 1000,
                          controller: projectDetailController,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '詳細',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
