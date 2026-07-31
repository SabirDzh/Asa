class TaskItem {
  final String id;
  String title;
  bool isCompleted;
  String? folderId;
  DateTime? dueDate;
  DateTime? startTime;
  DateTime? endTime;
  int? expectedDuration;
  DateTime? timerStartedAt;
  int timerElapsedSeconds;
  String? calendarId;
  String? calendarEventId;
  final DateTime createdAt;
  final DateTime updatedAt;
  bool isDeleted;

  TaskItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.folderId,
    this.dueDate,
    this.startTime,
    this.endTime,
    this.expectedDuration,
    this.timerStartedAt,
    this.timerElapsedSeconds = 0,
    this.calendarId,
    this.calendarEventId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
    'folderId': folderId,
    'dueDate': dueDate?.toIso8601String(),
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'expectedDuration': expectedDuration,
    'timerStartedAt': timerStartedAt?.toIso8601String(),
    'timerElapsedSeconds': timerElapsedSeconds,
    'calendarId': calendarId,
    'calendarEventId': calendarEventId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isDeleted': isDeleted,
  };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: json['id'],
    title: json['title'],
    isCompleted: json['isCompleted'] ?? false,
    folderId: json['folderId'],
    dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
    startTime:
        json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
    endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
    expectedDuration: json['expectedDuration'],
    timerStartedAt:
        json['timerStartedAt'] != null
            ? DateTime.parse(json['timerStartedAt'])
            : null,
    timerElapsedSeconds:
        json['timerElapsedSeconds'] is int
            ? json['timerElapsedSeconds'] as int
            : 0,
    calendarId: json['calendarId'],
    calendarEventId: json['calendarEventId'],
    createdAt:
        json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
    updatedAt:
        json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
    isDeleted: json['isDeleted'] ?? false,
  );

  /// Duration derived from the selected period in minutes.
  /// A period whose end is earlier than its start crosses midnight.
  int? get periodDurationMinutes {
    final start = startTime;
    final end = endTime;
    if (start == null || end == null) return null;
    var minutes = end.difference(start).inMinutes;
    if (minutes < 0) minutes += 24 * 60;
    return minutes == 0 ? null : minutes;
  }

  /// Uses the period duration for new tasks and keeps legacy imported values.
  int? get effectiveDurationMinutes =>
      periodDurationMinutes ?? expectedDuration;

  static int? durationForPeriod(DateTime start, DateTime end) {
    var minutes = end.difference(start).inMinutes;
    if (minutes < 0) minutes += 24 * 60;
    return minutes == 0 ? null : minutes;
  }

  TaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    Object? folderId = const Object(),
    Object? dueDate = const Object(),
    Object? startTime = const Object(),
    Object? endTime = const Object(),
    Object? expectedDuration = const Object(),
    Object? timerStartedAt = const Object(),
    int? timerElapsedSeconds,
    Object? calendarId = const Object(),
    Object? calendarEventId = const Object(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      folderId:
          folderId == const Object() ? this.folderId : folderId as String?,
      dueDate: dueDate == const Object() ? this.dueDate : dueDate as DateTime?,
      startTime:
          startTime == const Object() ? this.startTime : startTime as DateTime?,
      endTime: endTime == const Object() ? this.endTime : endTime as DateTime?,
      expectedDuration:
          expectedDuration == const Object()
              ? this.expectedDuration
              : expectedDuration as int?,
      timerStartedAt:
          timerStartedAt == const Object()
              ? this.timerStartedAt
              : timerStartedAt as DateTime?,
      timerElapsedSeconds: timerElapsedSeconds ?? this.timerElapsedSeconds,
      calendarId:
          calendarId == const Object()
              ? this.calendarId
              : calendarId as String?,
      calendarEventId:
          calendarEventId == const Object()
              ? this.calendarEventId
              : calendarEventId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

class FolderItem {
  final String id;
  String name;
  final bool isSystemStreak;
  String? parentFolderId;
  String? iconAsset;
  final DateTime createdAt;
  final DateTime updatedAt;
  bool isDeleted;

  FolderItem({
    required this.id,
    required this.name,
    this.isSystemStreak = false,
    this.parentFolderId,
    this.iconAsset,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isSystemStreak': isSystemStreak,
    'parentFolderId': parentFolderId,
    'iconAsset': iconAsset,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isDeleted': isDeleted,
  };

  factory FolderItem.fromJson(Map<String, dynamic> json) => FolderItem(
    id: json['id'],
    name: json['name'],
    isSystemStreak: json['isSystemStreak'] ?? false,
    parentFolderId: json['parentFolderId'],
    iconAsset: json['iconAsset'],
    createdAt:
        json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
    updatedAt:
        json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
    isDeleted: json['isDeleted'] ?? false,
  );

  FolderItem copyWith({
    String? id,
    String? name,
    bool? isSystemStreak,
    Object? parentFolderId = const Object(),
    Object? iconAsset = const Object(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return FolderItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isSystemStreak: isSystemStreak ?? this.isSystemStreak,
      parentFolderId:
          parentFolderId == const Object()
              ? this.parentFolderId
              : parentFolderId as String?,
      iconAsset:
          iconAsset == const Object() ? this.iconAsset : iconAsset as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
