import 'dart:convert';

enum RoutingMode {
  allTraffic,
  selectedApps;

  String get label => switch (this) {
        RoutingMode.allTraffic => 'All traffic',
        RoutingMode.selectedApps => 'Selected apps',
      };
}

class SelectedApp {
  const SelectedApp({
    required this.name,
    required this.packageName,
  });

  final String name;
  final String packageName;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'packageName': packageName,
    };
  }

  factory SelectedApp.fromMap(Map<String, dynamic> map) {
    return SelectedApp(
      name: map['name'] as String,
      packageName: map['packageName'] as String,
    );
  }
}

class ProxyConnection {
  const ProxyConnection({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.routingMode,
    required this.selectedApps,
    this.username,
    this.password,
  });

  final String id;
  final String name;
  final String type;
  final String host;
  final int port;
  final RoutingMode routingMode;
  final List<SelectedApp> selectedApps;
  final String? username;
  final String? password;

  String get endpoint => '$host:$port';

  bool get hasCredentials =>
      (username != null && username!.isNotEmpty) ||
      (password != null && password!.isNotEmpty);

  String get routingSummary => switch (routingMode) {
        RoutingMode.allTraffic => 'All traffic',
        RoutingMode.selectedApps => '${selectedApps.length} app(s)',
      };

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'type': type,
      'host': host,
      'port': port,
      'routingMode': routingMode.name,
      'selectedApps':
          selectedApps.map((SelectedApp app) => app.toMap()).toList(),
      'username': username,
      'password': password,
    };
  }

  factory ProxyConnection.fromMap(Map<String, dynamic> map) {
    return ProxyConnection(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      routingMode: RoutingMode.values.byName(map['routingMode'] as String),
      selectedApps: ((map['selectedApps'] as List<dynamic>?) ?? <dynamic>[])
          .map(
            (dynamic app) => SelectedApp.fromMap(app as Map<String, dynamic>),
          )
          .toList(),
      username: map['username'] as String?,
      password: map['password'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ProxyConnection.fromJson(String source) {
    return ProxyConnection.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
