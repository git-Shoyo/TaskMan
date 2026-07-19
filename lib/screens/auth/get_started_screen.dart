import 'package:flutter/material.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: _BackgroundDecoration()),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 920;

                    return SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 56 : 24,
                        vertical: isWide ? 36 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight -
                              (isWide ? 72 : 48),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BrandHeader(),
                            SizedBox(height: isWide ? 56 : 36),
                            if (isWide)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 10,
                                    child: _HeroContent(
                                      onGetStarted: widget.onGetStarted,
                                      onSignIn: widget.onSignIn,
                                    ),
                                  ),
                                  const SizedBox(width: 64),
                                  const Expanded(
                                    flex: 11,
                                    child: _TaskPreview(),
                                  ),
                                ],
                              )
                            else ...[
                              _HeroContent(
                                onGetStarted: widget.onGetStarted,
                                onSignIn: widget.onSignIn,
                              ),
                              const SizedBox(height: 44),
                              const _TaskPreview(),
                            ],
                            SizedBox(height: isWide ? 24 : 32),
                            const _Footer(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.tertiary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.task_alt_rounded,
            color: colorScheme.onPrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'TaskMan',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '学校生活のタスク管理を、ひとつに。',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'やるべきことを、\n迷わない毎日へ。',
          style: theme.textTheme.displaySmall?.copyWith(
            fontSize: 48,
            height: 1.12,
            letterSpacing: -1.8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            '課題、予定、プロジェクトを整理して、今日やることを明確に。'
            'TaskManが、学習と制作の進行をシンプルにします。',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.75,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FeatureChip(
              icon: Icons.check_circle_outline_rounded,
              label: '課題・タスク',
            ),
            _FeatureChip(
              icon: Icons.account_tree_outlined,
              label: 'プロジェクト',
            ),
            _FeatureChip(
              icon: Icons.timeline_rounded,
              label: '予定の見える化',
            ),
          ],
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: onGetStarted,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TaskManを始める',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 54,
              child: OutlinedButton(
                onPressed: onSignIn,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: const Text(
                  'ログイン',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '無料で開始できます',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPreview extends StatelessWidget {
  const _TaskPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 590),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 42,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.dashboard_customize_outlined,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日のタスク',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '7月19日 日曜日',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: null,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.tertiaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: 0.72,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          backgroundColor: colorScheme.surface
                              .withValues(alpha: 0.56),
                        ),
                        Text(
                          '72%',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今週の進捗',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'あと3件で今週の予定を完了できます',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _PreviewTaskTile(
              icon: Icons.electric_bolt_outlined,
              title: '電気回路レポート',
              detail: '今日 23:59',
              statusLabel: '優先',
              completed: false,
            ),
            const SizedBox(height: 10),
            const _PreviewTaskTile(
              icon: Icons.code_rounded,
              title: 'Flutter UI実装',
              detail: '明日 18:00',
              statusLabel: '制作',
              completed: false,
            ),
            const SizedBox(height: 10),
            const _PreviewTaskTile(
              icon: Icons.check_rounded,
              title: 'ROS 2 動作確認',
              detail: '完了',
              statusLabel: '完了',
              completed: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTaskTile extends StatelessWidget {
  const _PreviewTaskTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.statusLabel,
    required this.completed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String statusLabel;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: completed
                  ? colorScheme.secondaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              size: 20,
              color: completed
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    decoration:
                        completed ? TextDecoration.lineThrough : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: completed
                  ? colorScheme.secondaryContainer
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: completed
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: -160,
            right: -110,
            child: _BlurCircle(
              size: 420,
              color: colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            bottom: -190,
            left: -130,
            child: _BlurCircle(
              size: 430,
              color: colorScheme.tertiary.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            top: 150,
            left: -80,
            child: _BlurCircle(
              size: 210,
              color: colorScheme.secondary.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Text(
        'TaskMan  •  Plan clearly. Work calmly.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
