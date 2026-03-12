import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/proxy_connection.dart';
import '../widgets/app_gradient_background.dart';
import '../widgets/unity_banner_slot.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.connections,
    required this.onAddPressed,
    required this.onEditPressed,
    required this.onStartPressed,
    required this.activeConnectionId,
    required this.onStopPressed,
    required this.onLogsPressed,
    required this.onDeletePressed,
  });

  final List<ProxyConnection> connections;
  final VoidCallback onAddPressed;
  final ValueChanged<ProxyConnection> onEditPressed;
  final ValueChanged<ProxyConnection> onStartPressed;
  final String? activeConnectionId;
  final ValueChanged<ProxyConnection> onStopPressed;
  final VoidCallback onLogsPressed;
  final ValueChanged<ProxyConnection> onDeletePressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: onAddPressed,
        backgroundColor: Colors.white.withValues(alpha: 0.22),
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        child: const Icon(Icons.add, size: 24),
      ),
      body: AppGradientBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 8,
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              toolbarHeight: 68,
              automaticallyImplyLeading: false,
              leadingWidth: 72,
              leading: const SizedBox.shrink(),
              titleSpacing: 0,
              centerTitle: true,
              title: const Text('Proxy Tools'),
              actions: <Widget>[
                SizedBox(
                  width: 72,
                  child: Center(
                    child: TextButton(
                      onPressed: onLogsPressed,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Logs'),
                    ),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  <Widget>[
                    if (connections.isEmpty) _EmptyState(onAddPressed: onAddPressed),
                    ...connections.asMap().entries.expand(
                      (MapEntry<int, ProxyConnection> entry) => <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Dismissible(
                            key: ValueKey<String>(entry.value.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmDelete(context, entry.value),
                            onDismissed: (_) => onDeletePressed(entry.value),
                            background: const SizedBox.shrink(),
                            secondaryBackground: _DeleteBackground(
                              isActive: entry.value.id == activeConnectionId,
                            ),
                            child: _ConnectionCard(
                              connection: entry.value,
                              isActive: entry.value.id == activeConnectionId,
                              onEditPressed: () => onEditPressed(entry.value),
                              onStartPressed: () => onStartPressed(entry.value),
                              onStopPressed: () => onStopPressed(entry.value),
                            ),
                          ),
                        ),
                        if (entry.key == 0)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: UnityBannerSlot(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(
    BuildContext context,
    ProxyConnection connection,
  ) {
    final bool isActive = connection.id == activeConnectionId;
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete connection?'),
          content: Text(
            isActive
                ? 'This profile is active right now. It will be stopped and removed.'
                : 'The profile "${connection.name}" will be removed from saved connections.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.hub_outlined,
              size: 38,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No connections yet',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first profile to start routing all traffic or only selected apps.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAddPressed,
            icon: const Icon(Icons.add),
            label: const Text('Add connection'),
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isActive ? colorScheme.errorContainer : colorScheme.error,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Icon(
            Icons.delete_outline,
            color: isActive ? colorScheme.onErrorContainer : colorScheme.onError,
          ),
          const SizedBox(height: 6),
          Text(
            'Delete',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isActive ? colorScheme.onErrorContainer : colorScheme.onError,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.isActive,
    required this.onEditPressed,
    required this.onStartPressed,
    required this.onStopPressed,
  });

  final ProxyConnection connection;
  final bool isActive;
  final VoidCallback onEditPressed;
  final VoidCallback onStartPressed;
  final VoidCallback onStopPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.14),
                      ],
                    ),
                    border: Border.all(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.46)
                          : Colors.white.withValues(alpha: 0.28),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -30,
              right: -20,
              child: _LiquidBlob(
                size: 150,
                color: const Color(0xFF85F3C5).withValues(alpha: 0.42),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -10,
              child: _LiquidBlob(
                size: 170,
                color: const Color(0xFF7FD9FF).withValues(alpha: 0.28),
              ),
            ),
            Positioned(
              top: 70,
              right: 40,
              child: _LiquidBlob(
                size: 76,
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.38),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    connection.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF10352F),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _LiquidChip(label: connection.type.toUpperCase()),
                      _LiquidChip(label: connection.routingSummary),
                      if (connection.hasCredentials)
                        const _LiquidChip(label: 'Auth enabled'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEditPressed,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.46),
                            side: BorderSide(
                              color: const Color(0xFF76D3B0).withValues(alpha: 0.5),
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: isActive
                            ? FilledButton.tonalIcon(
                                onPressed: onStopPressed,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.62),
                                  foregroundColor: const Color(0xFF0D5F52),
                                ),
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: const Text('Stop'),
                              )
                            : FilledButton.icon(
                                onPressed: onStartPressed,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF18B675),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start'),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidBlob extends StatelessWidget {
  const _LiquidBlob({
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
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _LiquidChip extends StatelessWidget {
  const _LiquidChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF91DFC0).withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF165046),
        ),
      ),
    );
  }
}
