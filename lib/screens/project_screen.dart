import 'package:flutter/material.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/screens/add_project/add_project_screen.dart';
import 'package:taskman/systems/project.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  int? selectedIndex;
  final projectRepository = ProjectRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProjectScreen()),
          );
        },
        tooltip: 'プロジェクト作成',
        child: const Icon(Icons.create),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Project>>(
          stream: projectRepository.watchProjects(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('プロジェクトの読み込みに失敗しました'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final projects = snapshot.data ?? const <Project>[];

            if (projects.isEmpty) {
              return const Center(child: Text('プロジェクトがありません'));
            }

            final selectedProject =
                selectedIndex != null && selectedIndex! < projects.length
                ? projects[selectedIndex!]
                : null;

            return LayoutBuilder(
              builder: (context, constraints) {
                final showDetail = constraints.maxWidth >= 700;

                return Row(
                  children: [
                    SizedBox(
                      width: showDetail ? 320 : constraints.maxWidth,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: projects.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final project = projects[index];
                          final isSelected = selectedIndex == index;

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
                              onTap: () {
                                setState(() {
                                  selectedIndex = index;
                                });
                              },
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
                            : _ProjectDetail(project: selectedProject),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProjectDetail extends StatelessWidget {
  const _ProjectDetail({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(project.description ?? '詳細なし'),
        ],
      ),
    );
  }
}
