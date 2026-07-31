const int kMaxTaskInfoValue = 1000000000;
const int kMaxTaskDescriptionLength = 10000;
const int kMaxTaskAttachmentsPerTask = 20;

/// The kinds of structured information a task can contain.
enum TaskInfoBlockType { quantity, description }

/// The kinds of references that can be attached to a description.
enum TaskAttachmentType { link, image, file }

class TaskAttachment {
  final String id;
  final TaskAttachmentType type;
  final String name;
  final String value;
  final String? mimeType;

  const TaskAttachment({
    required this.id,
    required this.type,
    required this.name,
    required this.value,
    this.mimeType,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    final value = _requiredString(json, 'value');
    final typeName = _requiredString(json, 'type');
    final type = TaskAttachmentType.values.asNameMap()[typeName];
    if (type == null) {
      throw FormatException('Unknown attachment type: $typeName');
    }
    if (type == TaskAttachmentType.link &&
        !isAllowedTaskAttachmentLink(value)) {
      throw const FormatException('Only http and https links are allowed');
    }

    return TaskAttachment(
      id: id,
      type: type,
      name: name,
      value: value,
      mimeType: json['mimeType'] is String ? json['mimeType'] as String : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'value': value,
    if (mimeType != null) 'mimeType': mimeType,
  };

  TaskAttachment copyWith({
    String? id,
    TaskAttachmentType? type,
    String? name,
    String? value,
    Object? mimeType = const Object(),
  }) {
    final nextType = type ?? this.type;
    final nextValue = value ?? this.value;
    if (nextType == TaskAttachmentType.link &&
        !isAllowedTaskAttachmentLink(nextValue)) {
      throw const FormatException('Only http and https links are allowed');
    }
    return TaskAttachment(
      id: id ?? this.id,
      type: nextType,
      name: name ?? this.name,
      value: nextValue,
      mimeType:
          mimeType == const Object() ? this.mimeType : mimeType as String?,
    );
  }
}

class TaskInfoBlock {
  final String id;
  final TaskInfoBlockType type;
  final String label;
  final double currentValue;
  final double targetValue;
  final String unit;
  final String text;
  final List<TaskAttachment> attachments;

  const TaskInfoBlock._({
    required this.id,
    required this.type,
    required this.label,
    required this.currentValue,
    required this.targetValue,
    required this.unit,
    required this.text,
    required this.attachments,
  });

  factory TaskInfoBlock.quantity({
    required String id,
    String label = '',
    double currentValue = 0,
    required double targetValue,
    required String unit,
  }) {
    _validateQuantity(currentValue, targetValue, unit);
    return TaskInfoBlock._(
      id: id,
      type: TaskInfoBlockType.quantity,
      label: label,
      currentValue: currentValue,
      targetValue: targetValue,
      unit: unit,
      text: '',
      attachments: const [],
    );
  }

  factory TaskInfoBlock.description({
    required String id,
    String text = '',
    List<TaskAttachment> attachments = const [],
  }) {
    if (text.length > kMaxTaskDescriptionLength) {
      throw const FormatException('Description is too long');
    }
    if (attachments.length > kMaxTaskAttachmentsPerTask) {
      throw const FormatException('Too many description attachments');
    }
    return TaskInfoBlock._(
      id: id,
      type: TaskInfoBlockType.description,
      label: '',
      currentValue: 0,
      targetValue: 0,
      unit: '',
      text: text,
      attachments: List.unmodifiable(attachments),
    );
  }

  factory TaskInfoBlock.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final typeName = _requiredString(json, 'type');
    final type = TaskInfoBlockType.values.asNameMap()[typeName];
    if (type == null) {
      throw FormatException('Unknown task information block type: $typeName');
    }

    switch (type) {
      case TaskInfoBlockType.quantity:
        final currentValue = _number(json, 'currentValue');
        final targetValue = _number(json, 'targetValue');
        final unit = _requiredString(json, 'unit');
        return TaskInfoBlock.quantity(
          id: id,
          label: json['label'] is String ? json['label'] as String : '',
          currentValue: currentValue,
          targetValue: targetValue,
          unit: unit,
        );
      case TaskInfoBlockType.description:
        final rawAttachments = json['attachments'];
        final attachments = <TaskAttachment>[];
        if (rawAttachments != null) {
          if (rawAttachments is! List) {
            throw const FormatException(
              'Description attachments must be a list',
            );
          }
          if (rawAttachments.length > kMaxTaskAttachmentsPerTask) {
            throw const FormatException('Too many description attachments');
          }
          for (final entry in rawAttachments) {
            if (entry is! Map) {
              continue;
            }
            try {
              attachments.add(
                TaskAttachment.fromJson(Map<String, dynamic>.from(entry)),
              );
            } on Object {
              // One malformed attachment must not hide the valid description.
            }
          }
        }
        return TaskInfoBlock.description(
          id: id,
          text: json['text'] is String ? json['text'] as String : '',
          attachments: attachments,
        );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'label': label,
    'currentValue': currentValue,
    'targetValue': targetValue,
    'unit': unit,
    'text': text,
    'attachments':
        attachments.map((attachment) => attachment.toJson()).toList(),
  };

  TaskInfoBlock copyWith({
    String? id,
    TaskInfoBlockType? type,
    String? label,
    double? currentValue,
    double? targetValue,
    String? unit,
    String? text,
    List<TaskAttachment>? attachments,
  }) {
    final nextType = type ?? this.type;
    if (nextType == TaskInfoBlockType.quantity) {
      return TaskInfoBlock.quantity(
        id: id ?? this.id,
        label: label ?? this.label,
        currentValue: currentValue ?? this.currentValue,
        targetValue: targetValue ?? this.targetValue,
        unit: unit ?? this.unit,
      );
    }
    return TaskInfoBlock.description(
      id: id ?? this.id,
      text: text ?? this.text,
      attachments: attachments ?? this.attachments,
    );
  }

  static void _validateQuantity(
    double currentValue,
    double targetValue,
    String unit,
  ) {
    if (!currentValue.isFinite ||
        !targetValue.isFinite ||
        currentValue < 0 ||
        targetValue <= 0 ||
        currentValue > targetValue ||
        currentValue > kMaxTaskInfoValue ||
        targetValue > kMaxTaskInfoValue ||
        unit.trim().isEmpty) {
      throw const FormatException('Invalid quantity information block');
    }
  }
}

bool isAllowedTaskAttachmentLink(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

double _number(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('$key must be a number');
  }
  return value.toDouble();
}
