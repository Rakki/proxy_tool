import 'package:flutter/material.dart';

import '../models/proxy_connection.dart';
import '../widgets/app_gradient_background.dart';
import '../widgets/glass_panel.dart';
import 'app_picker_screen.dart';

class ConnectionFormScreen extends StatefulWidget {
  const ConnectionFormScreen({
    super.key,
    this.initialConnection,
  });

  final ProxyConnection? initialConnection;

  @override
  State<ConnectionFormScreen> createState() => _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends State<ConnectionFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _selectedType = 'socks5';
  RoutingMode _routingMode = RoutingMode.allTraffic;
  List<SelectedApp> _selectedApps = <SelectedApp>[];
  bool _isPasswordVisible = false;

  bool get _isEditing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();

    final ProxyConnection? initialConnection = widget.initialConnection;
    if (initialConnection == null) {
      return;
    }

    _nameController.text = initialConnection.name;
    _hostController.text = initialConnection.host;
    _portController.text = initialConnection.port.toString();
    _usernameController.text = initialConnection.username ?? '';
    _passwordController.text = initialConnection.password ?? '';
    _selectedType = initialConnection.type;
    _routingMode = initialConnection.routingMode;
    _selectedApps = List<SelectedApp>.from(initialConnection.selectedApps);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final bool isFormValid = _formKey.currentState!.validate();
    final String? selectedAppsError = _validateSelectedApps();
    if (!isFormValid || selectedAppsError != null) {
      setState(() {});
      return;
    }

    final ProxyConnection connection = ProxyConnection(
      id: widget.initialConnection?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      type: _selectedType,
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      routingMode: _routingMode,
      selectedApps: _selectedApps,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password: _passwordController.text.trim().isEmpty
          ? null
          : _passwordController.text.trim(),
    );

    Navigator.of(context).pop(connection);
  }

  Future<void> _openAppPicker() async {
    final List<SelectedApp>? selectedApps = await Navigator.of(context).push(
      MaterialPageRoute<List<SelectedApp>>(
        builder: (_) => AppPickerScreen(initialSelection: _selectedApps),
      ),
    );

    if (selectedApps == null) {
      return;
    }

    setState(() {
      _selectedApps = selectedApps;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      body: AppGradientBackground(
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                toolbarHeight: 68,
                scrolledUnderElevation: 8,
                elevation: 4,
                title: Text(_isEditing ? 'Edit connection' : 'Add connection'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    <Widget>[
                    _SectionCard(
                      title: 'Traffic routing',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SegmentedButton<RoutingMode>(
                            segments: const <ButtonSegment<RoutingMode>>[
                              ButtonSegment<RoutingMode>(
                                value: RoutingMode.allTraffic,
                                label: Text('All traffic'),
                                icon: Icon(Icons.language),
                              ),
                              ButtonSegment<RoutingMode>(
                                value: RoutingMode.selectedApps,
                                label: Text('Selected apps'),
                                icon: Icon(Icons.apps_outlined),
                              ),
                            ],
                            selected: <RoutingMode>{_routingMode},
                            onSelectionChanged: (Set<RoutingMode> selection) {
                              setState(() {
                                _routingMode = selection.first;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          GlassPanel(
                            padding: const EdgeInsets.all(16),
                            borderRadius: BorderRadius.circular(20),
                            child: Text(
                              _routingMode == RoutingMode.allTraffic
                                  ? 'All device traffic will be wrapped by the VPN route while this profile is active.'
                                  : 'Only the selected applications will use the VPN route while the rest of the device stays direct.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (_routingMode == RoutingMode.selectedApps) ...<Widget>[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _openAppPicker,
                              icon: const Icon(Icons.apps_outlined),
                              label: Text(
                                _selectedApps.isEmpty
                                    ? 'Choose installed apps'
                                    : 'Selected apps: ${_selectedApps.length}',
                              ),
                            ),
                            if (_validateSelectedApps() case final String error) ...<Widget>[
                              const SizedBox(height: 10),
                              Text(
                                error,
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
                            if (_selectedApps.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 14),
                              ..._selectedApps.map(
                                (SelectedApp app) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GlassPanel(
                                    padding: const EdgeInsets.all(14),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Row(
                                      children: <Widget>[
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: colorScheme.secondaryContainer,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            Icons.apps,
                                            color: colorScheme.onSecondaryContainer,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(app.name),
                                              const SizedBox(height: 2),
                                              Text(
                                                app.packageName,
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Connection details',
                      child: Column(
                        children: <Widget>[
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              hintText: 'Work proxy',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: _validateRequired,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedType,
                            decoration: const InputDecoration(labelText: 'Type'),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(
                                value: 'socks5',
                                child: Text('SOCKS5'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'http',
                                child: Text('HTTP'),
                              ),
                              DropdownMenuItem<String>(
                                value: 'https',
                                child: Text('HTTPS CONNECT'),
                              ),
                            ],
                            onChanged: (String? value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedType = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Host',
                              hintText: '192.168.1.10 or proxy.example.com',
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            validator: _validateRequired,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              hintText: '1080',
                            ),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            validator: _validatePort,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Authentication',
                      child: Column(
                        children: <Widget>[
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              hintText: 'Optional',
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Optional',
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                                icon: Icon(
                                  _isPasswordVisible
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            obscureText: !_isPasswordVisible,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _save,
                      child: Text(_isEditing ? 'Save changes' : 'Save profile'),
                    ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }

    final int? port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Enter a valid port';
    }

    return null;
  }

  String? _validateSelectedApps() {
    if (_routingMode == RoutingMode.selectedApps && _selectedApps.isEmpty) {
      return 'Select at least one application';
    }
    return null;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
