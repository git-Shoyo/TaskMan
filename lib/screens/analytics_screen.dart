import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskman/repositories/project_repository.dart';
import 'package:taskman/repositories/task_repository.dart';
import 'package:taskman/systems/auth_scope.dart';
import 'package:taskman/systems/project.dart';
import 'package:taskman/systems/task.dart';

final DateFormat _shortDateFormat = DateFormat('M/d');

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final projectRepository = ProjectRepository();
  final taskRepository = TaskRepository();

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthScope.of(context).currentUser;

    return StreamBuilder<List<Project>>(
      stream: projectRepository.watchProjects(memberId: currentUser.id),
      builder: (context, projectSnapshot) {
        final projects = projectSnapshot.data ?? const <Project>[];
        final projectIds = projects.map((project) => project.id);

        return StreamBuilder<List<Task>>(
          stream: taskRepository.watchTasks(projectIds: projectIds),
          builder: (context, taskSnapshot) {
            final hasError = projectSnapshot.hasError || taskSnapshot.hasError;
            final isLoading =
                (projectSnapshot.connectionState == ConnectionState.waiting &&
                    !projectSnapshot.hasData) ||
                (taskSnapshot.connectionState == ConnectionState.waiting &&
                    !taskSnapshot.hasData);

            if (hasError) {
              return const _ScreenMessage(text: 'アナリティクスの読み込みに失敗しました');
            }

            if (isLoading) {
              return const _ScreenMessage.loading();
            }

            final data = _AnalyticsData(
              projects: projects,
              tasks: taskSnapshot.data ?? const <Task>[],
            );

            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  const _AnalyticsHeader(),
                  const SizedBox(height: 16),
                  _SummaryStrip(data: data),
                  const SizedBox(height: 16),
                  _ResponsiveGrid(
                    children: [
                      _CompletionTrendCard(data: data),
                      _DeadlineRiskCard(data: data),
                      _ProjectProgressCard(data: data),
                      _PriorityDistributionCard(data: data),
                      _CategoryTagCard(data: data),
                      _EstimateTimeCard(data: data),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AnalyticsHeader extends StatelessWidget {
  const _AnalyticsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.bar_chart, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'アナリティクス',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final items = [
      _SummaryMetric(
        icon: Icons.all_inbox,
        label: '総タスク',
        value: '${data.totalTasks}',
      ),
      _SummaryMetric(
        icon: Icons.check_circle_outline,
        label: '完了',
        value: '${data.doneTasks.length}',
      ),
      _SummaryMetric(
        icon: Icons.pending_actions,
        label: '未完了',
        value: '${data.activeTasks.length}',
      ),
      _SummaryMetric(
        icon: Icons.error_outline,
        label: '期限切れ',
        value: '${data.overdueTasks.length}',
        isDanger: data.overdueTasks.isNotEmpty,
      ),
      _SummaryMetric(
        icon: Icons.today,
        label: '今日期限',
        value: '${data.dueTodayTasks.length}',
      ),
      _SummaryMetric(
        icon: Icons.trending_up,
        label: '平均進捗',
        value: '${data.averageCompletionPercent}%',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 6
            : constraints.maxWidth >= 760
            ? 3
            : 2;
        const gap = 8.0;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _SummaryMetricTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryMetricTile extends StatelessWidget {
  const _SummaryMetricTile({required this.item});

  final _SummaryMetric item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.isDanger ? colorScheme.error : colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minHeight: 90),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, size: 20, color: accent),
          const SizedBox(height: 8),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _CompletionTrendCard extends StatelessWidget {
  const _CompletionTrendCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final trend = data.completionTrend;
    final maxCount = trend.fold<int>(
      0,
      (currentMax, point) => math.max(currentMax, point.count),
    );

    return _AnalyticsCard(
      icon: Icons.show_chart,
      title: '完了率の推移',
      child: data.totalTasks == 0
          ? const _EmptyPanelMessage(text: 'タスクが追加されると推移を表示します')
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
                  titlesData: _lineChartTitles(context, trend),
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

class _DeadlineRiskCard extends StatelessWidget {
  const _DeadlineRiskCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buckets = data.deadlineBuckets;
    final total = buckets.fold<int>(0, (sum, bucket) => sum + bucket.count);

    return _AnalyticsCard(
      icon: Icons.event_busy,
      title: '期限リスク分析',
      child: total == 0
          ? const _EmptyPanelMessage(text: '未完了タスクがありません')
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
                _LegendWrap(
                  items: [
                    for (final bucket in buckets)
                      _LegendItem(
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

class _ProjectProgressCard extends StatelessWidget {
  const _ProjectProgressCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final stats = data.projectStats;

    return _AnalyticsCard(
      icon: Icons.folder_copy_outlined,
      title: 'プロジェクト別進捗',
      child: stats.isEmpty
          ? const _EmptyPanelMessage(text: 'プロジェクトがありません')
          : Column(
              children: [
                for (final stat in stats) ...[
                  _ProjectProgressRow(stat: stat),
                  if (stat != stats.last) const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ProjectProgressRow extends StatelessWidget {
  const _ProjectProgressRow({required this.stat});

  final _ProjectStat stat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = (stat.completionRatio * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                stat.project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 8),
            Text('$percent%', style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: stat.completionRatio,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            _MiniMeta(
              icon: Icons.check_circle_outline,
              text: '${stat.done} 完了',
            ),
            _MiniMeta(icon: Icons.pending_actions, text: '${stat.active} 未完了'),
            if (stat.overdue > 0)
              _MiniMeta(
                icon: Icons.error_outline,
                text: '${stat.overdue} 期限切れ',
              ),
          ],
        ),
      ],
    );
  }
}

class _PriorityDistributionCard extends StatelessWidget {
  const _PriorityDistributionCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final counts = data.priorityCounts;
    final maxCount = counts.values.fold<int>(0, math.max);

    return _AnalyticsCard(
      icon: Icons.priority_high,
      title: '優先度分布',
      child: maxCount == 0
          ? const _EmptyPanelMessage(text: '重要度付きの未完了タスクはありません')
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
                  titlesData: _barChartTitles(
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

class _CategoryTagCard extends StatelessWidget {
  const _CategoryTagCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final categories = data.categoryStats;
    final tags = data.tagStats;

    return _AnalyticsCard(
      icon: Icons.label_outline,
      title: 'カテゴリ・タグ別分析',
      child: categories.isEmpty && tags.isEmpty
          ? const _EmptyPanelMessage(text: 'カテゴリやタグ付きのタスクはありません')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categories.isNotEmpty) ...[
                  Text('カテゴリ', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final stat in categories) ...[
                    _CategoryRow(stat: stat),
                    if (stat != categories.last) const SizedBox(height: 8),
                  ],
                ],
                if (categories.isNotEmpty && tags.isNotEmpty)
                  const SizedBox(height: 16),
                if (tags.isNotEmpty) ...[
                  Text('タグ', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        Chip(
                          avatar: const Icon(Icons.tag, size: 16),
                          label: Text('${tag.name} ${tag.count}'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.stat});

  final _NamedCount stat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.label, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(stat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text('${stat.count}件'),
      ],
    );
  }
}

class _EstimateTimeCard extends StatelessWidget {
  const _EstimateTimeCard({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final estimates = data.projectEstimateStats;

    return _AnalyticsCard(
      icon: Icons.schedule,
      title: '見積もり時間の集計',
      child: data.totalEstimatedTime == Duration.zero
          ? const _EmptyPanelMessage(text: '見積もり時間が設定されたタスクはありません')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth >= 520
                        ? (constraints.maxWidth - 8) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _EstimateMetric(
                            label: '合計',
                            value: _formatDuration(data.totalEstimatedTime),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _EstimateMetric(
                            label: '未完了分',
                            value: _formatDuration(data.activeEstimatedTime),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (estimates.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'プロジェクト別',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final estimate in estimates) ...[
                    Row(
                      children: [
                        const Icon(Icons.folder, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            estimate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_formatDuration(estimate.duration)),
                      ],
                    ),
                    if (estimate != estimates.last) const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
    );
  }
}

class _EstimateMetric extends StatelessWidget {
  const _EstimateMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

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

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _LegendWrap extends StatelessWidget {
  const _LegendWrap({required this.items});

  final List<_LegendItem> items;

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

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  const _EmptyPanelMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

class _ScreenMessage extends StatelessWidget {
  const _ScreenMessage({required this.text}) : isLoading = false;

  const _ScreenMessage.loading() : text = '', isLoading = true;

  final String text;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: isLoading ? const CircularProgressIndicator() : Text(text),
    );
  }
}

class _AnalyticsData {
  _AnalyticsData({required this.projects, required this.tasks})
    : today = DateUtils.dateOnly(DateTime.now());

  final List<Project> projects;
  final List<Task> tasks;
  final DateTime today;

  int get totalTasks => tasks.length;

  List<Task> get doneTasks => tasks.where((task) => task.isDone).toList();

  List<Task> get activeTasks => tasks.where((task) => !task.isDone).toList();

  List<Task> get overdueTasks =>
      tasks.where((task) => _isOverdue(task, today)).toList();

  List<Task> get dueTodayTasks => tasks
      .where(
        (task) =>
            !task.isDone &&
            task.deadline != null &&
            DateUtils.isSameDay(task.deadline, today),
      )
      .toList();

  int get averageCompletionPercent {
    if (tasks.isEmpty) {
      return 0;
    }

    final totalPercent = tasks.fold<int>(
      0,
      (sum, task) => sum + task.completionPercent,
    );
    return (totalPercent / tasks.length).round();
  }

  Duration get totalEstimatedTime => tasks.fold<Duration>(
    Duration.zero,
    (sum, task) => sum + (task.estimatedTime ?? Duration.zero),
  );

  Duration get activeEstimatedTime => activeTasks.fold<Duration>(
    Duration.zero,
    (sum, task) => sum + (task.estimatedTime ?? Duration.zero),
  );

  List<_TrendPoint> get completionTrend {
    final start = today.subtract(const Duration(days: 6));

    return [
      for (var index = 0; index < 7; index += 1)
        _TrendPoint(
          date: start.add(Duration(days: index)),
          count: doneTasks.where((task) {
            return DateUtils.isSameDay(
              task.updatedAt,
              start.add(Duration(days: index)),
            );
          }).length,
        ),
    ];
  }

  List<_DeadlineBucket> get deadlineBuckets {
    final active = activeTasks;

    return [
      _DeadlineBucket(
        label: '期限切れ',
        kind: _DeadlineRiskKind.overdue,
        count: active.where((task) => _isOverdue(task, today)).length,
      ),
      _DeadlineBucket(
        label: '3日以内',
        kind: _DeadlineRiskKind.withinThreeDays,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          final days = DateUtils.dateOnly(deadline).difference(today).inDays;
          return days >= 0 && days <= 3;
        }).length,
      ),
      _DeadlineBucket(
        label: '7日以内',
        kind: _DeadlineRiskKind.withinSevenDays,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          final days = DateUtils.dateOnly(deadline).difference(today).inDays;
          return days > 3 && days <= 7;
        }).length,
      ),
      _DeadlineBucket(
        label: 'それ以降',
        kind: _DeadlineRiskKind.later,
        count: active.where((task) {
          final deadline = task.deadline;
          if (deadline == null) {
            return false;
          }

          return DateUtils.dateOnly(deadline).difference(today).inDays > 7;
        }).length,
      ),
      _DeadlineBucket(
        label: '期限未設定',
        kind: _DeadlineRiskKind.noDeadline,
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

  List<_ProjectStat> get projectStats {
    final sortedProjects = [...projects]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return sortedProjects.take(6).map((project) {
      final projectTasks = tasks
          .where((task) => task.projectId == project.id)
          .toList();
      final done = projectTasks.where((task) => task.isDone).length;
      final overdue = projectTasks
          .where((task) => _isOverdue(task, today))
          .length;

      return _ProjectStat(
        project: project,
        total: projectTasks.length,
        done: done,
        overdue: overdue,
      );
    }).toList();
  }

  List<_NamedCount> get categoryStats {
    final counts = <String, int>{};

    for (final task in tasks) {
      final name = task.category.trim().isEmpty ? '未分類' : task.category.trim();
      counts[name] = (counts[name] ?? 0) + 1;
    }

    final stats =
        counts.entries
            .map((entry) => _NamedCount(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return stats.take(5).toList();
  }

  List<_NamedCount> get tagStats {
    final counts = <String, int>{};

    for (final task in tasks) {
      for (final tag in task.tags) {
        final name = tag.trim();
        if (name.isEmpty) {
          continue;
        }

        counts[name] = (counts[name] ?? 0) + 1;
      }
    }

    final stats =
        counts.entries
            .map((entry) => _NamedCount(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return stats.take(8).toList();
  }

  List<_ProjectEstimate> get projectEstimateStats {
    final projectById = {for (final project in projects) project.id: project};
    final durations = <String, Duration>{};

    for (final task in tasks) {
      final duration = task.estimatedTime;
      if (duration == null || duration == Duration.zero) {
        continue;
      }

      final projectName = projectById[task.projectId]?.name ?? 'プロジェクト未設定';
      durations[projectName] =
          (durations[projectName] ?? Duration.zero) + duration;
    }

    final stats =
        durations.entries
            .map(
              (entry) =>
                  _ProjectEstimate(name: entry.key, duration: entry.value),
            )
            .toList()
          ..sort((a, b) => b.duration.compareTo(a.duration));

    return stats.take(5).toList();
  }
}

class _SummaryMetric {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDanger;
}

class _TrendPoint {
  const _TrendPoint({required this.date, required this.count});

  final DateTime date;
  final int count;
}

class _DeadlineBucket {
  const _DeadlineBucket({
    required this.label,
    required this.kind,
    required this.count,
  });

  final String label;
  final _DeadlineRiskKind kind;
  final int count;

  Color color(ColorScheme colorScheme) {
    return switch (kind) {
      _DeadlineRiskKind.overdue => colorScheme.error,
      _DeadlineRiskKind.withinThreeDays => colorScheme.tertiary,
      _DeadlineRiskKind.withinSevenDays => colorScheme.primary,
      _DeadlineRiskKind.later => colorScheme.secondary,
      _DeadlineRiskKind.noDeadline => colorScheme.outline,
    };
  }

  Color onColor(ColorScheme colorScheme) {
    return switch (kind) {
      _DeadlineRiskKind.overdue => colorScheme.onError,
      _DeadlineRiskKind.withinThreeDays => colorScheme.onTertiary,
      _DeadlineRiskKind.withinSevenDays => colorScheme.onPrimary,
      _DeadlineRiskKind.later => colorScheme.onSecondary,
      _DeadlineRiskKind.noDeadline => colorScheme.surface,
    };
  }
}

enum _DeadlineRiskKind {
  overdue,
  withinThreeDays,
  withinSevenDays,
  later,
  noDeadline,
}

class _ProjectStat {
  const _ProjectStat({
    required this.project,
    required this.total,
    required this.done,
    required this.overdue,
  });

  final Project project;
  final int total;
  final int done;
  final int overdue;

  int get active => total - done;

  double get completionRatio {
    if (total == 0) {
      return 0;
    }

    return done / total;
  }
}

class _NamedCount {
  const _NamedCount({required this.name, required this.count});

  final String name;
  final int count;
}

class _ProjectEstimate {
  const _ProjectEstimate({required this.name, required this.duration});

  final String name;
  final Duration duration;
}

class _LegendItem {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;
}

FlTitlesData _lineChartTitles(BuildContext context, List<_TrendPoint> trend) {
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

FlTitlesData _barChartTitles(
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

bool _isOverdue(Task task, DateTime today) {
  final deadline = task.deadline;

  if (task.isDone || deadline == null) {
    return false;
  }

  return DateUtils.dateOnly(deadline).isBefore(today);
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours == 0) {
    return '$minutes分';
  }
  if (minutes == 0) {
    return '$hours時間';
  }

  return '$hours時間$minutes分';
}
