class TaskItem {
  final String id;
  String title;
  bool isCompleted;
  String? folderId;
  final DateTime createdAt;

  TaskItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.folderId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'folderId': folderId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id'],
        title: json['title'],
        isCompleted: json['isCompleted'] ?? false,
        folderId: json['folderId'],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
      );

  TaskItem copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    String? folderId,
    DateTime? createdAt,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class FolderItem {
  final String id;
  String name;
  final bool isSystemStreak;
  String? parentFolderId;
  final DateTime createdAt;

  FolderItem({
    required this.id,
    required this.name,
    this.isSystemStreak = false,
    this.parentFolderId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isSystemStreak': isSystemStreak,
        'parentFolderId': parentFolderId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FolderItem.fromJson(Map<String, dynamic> json) => FolderItem(
        id: json['id'],
        name: json['name'],
        isSystemStreak: json['isSystemStreak'] ?? false,
        parentFolderId: json['parentFolderId'],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
      );

  FolderItem copyWith({
    String? id,
    String? name,
    bool? isSystemStreak,
    String? parentFolderId,
    DateTime? createdAt,
  }) {
    return FolderItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isSystemStreak: isSystemStreak ?? this.isSystemStreak,
      parentFolderId: parentFolderId ?? this.parentFolderId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
