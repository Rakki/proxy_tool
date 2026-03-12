import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../models/proxy_connection.dart';
import '../widgets/app_gradient_background.dart';
import '../widgets/glass_panel.dart';

class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({
    super.key,
    required this.initialSelection,
  });

  final List<SelectedApp> initialSelection;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final Map<String, SelectedApp> _selectedByPackageName;

  List<AppInfo> _apps = <AppInfo>[];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedByPackageName = <String, SelectedApp>{
      for (final SelectedApp app in widget.initialSelection) app.packageName: app,
    };
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final List<AppInfo> apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      excludeNonLaunchableApps: true,
      withIcon: true,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _apps = apps;
      _isLoading = false;
    });
  }

  void _toggleApp(AppInfo app, bool selected) {
    setState(() {
      if (selected) {
        _selectedByPackageName[app.packageName] = SelectedApp(
          name: app.name,
          packageName: app.packageName,
        );
      } else {
        _selectedByPackageName.remove(app.packageName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<AppInfo> filteredApps = _apps.where((AppInfo app) {
      if (_query.isEmpty) {
        return true;
      }

      final String lowercaseQuery = _query.toLowerCase();
      return app.name.toLowerCase().contains(lowercaseQuery) ||
          app.packageName.toLowerCase().contains(lowercaseQuery);
    }).toList(growable: false);

    return Scaffold(
      body: AppGradientBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: 68,
              scrolledUnderElevation: 8,
              elevation: 4,
              title: const Text('Select apps'),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _selectedByPackageName.values.toList(growable: false),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  <Widget>[
                    GlassPanel(
                      child: Column(
                        children: <Widget>[
                          TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search installed apps',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (String value) {
                              setState(() {
                                _query = value.trim();
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              Text(
                                '${_selectedByPackageName.length} selected',
                                style: theme.textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                '${filteredApps.length} visible',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (filteredApps.isEmpty)
                      GlassPanel(
                        padding: const EdgeInsets.all(24),
                        borderRadius: BorderRadius.circular(24),
                        child: const Center(
                          child: Text('No installed apps found'),
                        ),
                      )
                    else
                      ...filteredApps.map(
                        (AppInfo app) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AppTile(
                            app: app,
                            selected: _selectedByPackageName.containsKey(app.packageName),
                            onChanged: (bool value) => _toggleApp(app, value),
                          ),
                        ),
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
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.onChanged,
  });

  final AppInfo app;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => onChanged(!selected),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: <Widget>[
            _AppIcon(icon: app.icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(app.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    app.packageName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: selected,
              onChanged: (bool? value) => onChanged(value ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.icon});

  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return const CircleAvatar(child: Icon(Icons.android));
    }

    return CircleAvatar(
      backgroundImage: MemoryImage(icon!),
      backgroundColor: Colors.transparent,
      radius: 24,
    );
  }
}
