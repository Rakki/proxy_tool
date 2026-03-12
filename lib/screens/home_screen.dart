import 'package:flutter/material.dart';

import '../models/proxy_connection.dart';

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
  });

  final List<ProxyConnection> connections;
  final VoidCallback onAddPressed;
  final ValueChanged<ProxyConnection> onEditPressed;
  final ValueChanged<ProxyConnection> onStartPressed;
  final String? activeConnectionId;
  final ValueChanged<ProxyConnection> onStopPressed;
  final VoidCallback onLogsPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        actions: <Widget>[
          IconButton(
            onPressed: onLogsPressed,
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Open logs',
          ),
        ],
      ),
      body: connections.isEmpty
          ? _EmptyState(onAddPressed: onAddPressed)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: connections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final ProxyConnection connection = connections[index];
                return _ConnectionCard(
                  connection: connection,
                  isActive: connection.id == activeConnectionId,
                  onEditPressed: () => onEditPressed(connection),
                  onStartPressed: () => onStartPressed(connection),
                  onStopPressed: () => onStopPressed(connection),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: onAddPressed,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddPressed});

  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.hub_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No connections yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first proxy configuration to start building the list.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add connection'),
            ),
          ],
        ),
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
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.shield_outlined,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    connection.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    connection.endpoint,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Chip(label: Text(connection.type.toUpperCase())),
                      Chip(label: Text(connection.routingSummary)),
                      if (isActive) const Chip(label: Text('Active')),
                      if (connection.hasCredentials)
                        const Chip(label: Text('Auth enabled')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: onEditPressed,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      if (isActive)
                        OutlinedButton.icon(
                          onPressed: onStopPressed,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: onStartPressed,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
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
