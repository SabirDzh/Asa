class TaskItem {
  final String id;
  String title;
  bool isCompleted;
  String? folderId;
  DateTime? dueDate;
  DateTime? startTime;
  DateTime? endTime;
  int? expectedDuration;
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
    this.calendarId,
    this.calendarEventId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  })  : createdAt = createdAt ?? DateTime.now(),
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
        startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
        endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
        expectedDuration: json['expectedDuration'],
        calendarId: json['calendarId'],
        calendarEventId: json['calendarEventId'],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
        isDeleted: json['isDeleted'] ?? false,
      );

  TaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    Object? folderId = const Object(),
    Object? dueDate = const Object(),
    Object? startTime = const Object(),
    Object? endTime = const Object(),
    Object? expectedDuration = const Object(),
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
      folderId: folderId == const Object() ? this.folderId : folderId as String?,
      dueDate: dueDate == const Object() ? this.dueDate : dueDate as DateTime?,
      startTime: startTime == const Object() ? this.startTime : startTime as DateTime?,
      endTime: endTime == const Object() ? this.endTime : endTime as DateTime?,
      expectedDuration: expectedDuration == const Object() ? this.expectedDuration : expectedDuration as int?,
      calendarId: calendarId == const Object() ? this.calendarId : calendarId as String?,
      calendarEventId: calendarEventId == const Object() ? this.calendarEventId : calendarEventId as String?,
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
  final DateTime createdAt;
  final DateTime updatedAt;
  bool isDeleted;

  FolderItem({
    required this.id,
    required this.name,
    this.isSystemStreak = false,
    this.parentFolderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isDeleted = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isSystemStreak': isSystemStreak,
        'parentFolderId': parentFolderId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory FolderItem.fromJson(Map<String, dynamic> json) => FolderItem(
        id: json['id'],
        name: json['name'],
        isSystemStreak: json['isSystemStreak'] ?? false,
        parentFolderId: json['parentFolderId'],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
        isDeleted: json['isDeleted'] ?? false,
      );

  FolderItem copyWith({
    String? id,
    String? name,
    bool? isSystemStreak,
    Object? parentFolderId = const Object(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return FolderItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isSystemStreak: isSystemStreak ?? this.isSystemStreak,
      parentFolderId: parentFolderId == const Object()
          ? this.parentFolderId
          : parentFolderId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
