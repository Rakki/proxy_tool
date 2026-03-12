import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../models/proxy_connection.dart';

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
      for (final SelectedApp app in widget.initialSelection)
        app.packageName: app,
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
    final List<AppInfo> filteredApps = _apps.where((AppInfo app) {
      if (_query.isEmpty) {
        return true;
      }

      final String lowercaseQuery = _query.toLowerCase();
      return app.name.toLowerCase().contains(lowercaseQuery) ||
          app.packageName.toLowerCase().contains(lowercaseQuery);
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select apps'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(
                _selectedByPackageName.values.toList(growable: false),
              );
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selectedByPackageName.length} selected',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredApps.isEmpty
                    ? const Center(child: Text('No installed apps found'))
                    : ListView.builder(
                        itemCount: filteredApps.length,
                        itemBuilder: (BuildContext context, int index) {
                          final AppInfo app = filteredApps[index];
                          final bool selected = _selectedByPackageName
                              .containsKey(app.packageName);

                          return CheckboxListTile(
                            value: selected,
                            onChanged: (bool? value) {
                              _toggleApp(app, value ?? false);
                            },
                            secondary: _AppIcon(icon: app.icon),
                            title: Text(app.name),
                            subtitle: Text(app.packageName),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
          ),
        ],
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
      return const CircleAvatar(
        child: Icon(Icons.android),
      );
    }

    return CircleAvatar(
      backgroundImage: MemoryImage(icon!),
      backgroundColor: Colors.transparent,
    );
  }
}
