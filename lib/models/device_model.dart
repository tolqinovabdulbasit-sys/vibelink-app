class DeviceModel {
  final String id;
  String name;
  String status; // online, offline, connecting
  DateTime? lastSeen;
  bool isActive;

  DeviceModel({
    required this.id,
    required this.name,
    this.status = 'offline',
    this.lastSeen,
    this.isActive = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'lastSeen': lastSeen?.toIso8601String(),
    'isActive': isActive,
  };

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
    id: json['id'],
    name: json['name'],
    status: json['status'] ?? 'offline',
    lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen']) : null,
    isActive: json['isActive'] ?? false,
  );
}
