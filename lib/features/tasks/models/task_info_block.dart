import '../../../core/description_format.dart';
import '../../../core/task_attachment_validation.dart';

const int kMaxTaskInfoValue = 1000000000;
const int kMaxTaskDescriptionLength = 10000;

/// Built-in quantity units shown to users who do not need to invent a unit.
/// The stored keys are language-independent so the display can follow the
/// current app language without changing saved task data.
const String kQuantityUnitTimes = 'unit_times';
const String kQuantityUnitMinutes = 'unit_minutes';
const String kQuantityUnitHours = 'unit_hours';
const String kQuantityUnitPages = 'unit_pages';
const String kQuantityUnitSteps = 'unit_steps';
const String kQuantityUnitGlasses = 'unit_glasses';
const String kQuantityUnitKilograms = 'unit_kilograms';
const String kQuantityUnitKilometers = 'unit_kilometers';
const String kQuantityUnitCustom = 'unit_custom';

class QuantityUnitOption {
  final String value;
  final String labelKey;

  const QuantityUnitOption(this.value, this.labelKey);
}

const quantityUnitOptions = <QuantityUnitOption>[
  QuantityUnitOption(kQuantityUnitTimes, 'quantity_unit_times'),
  QuantityUnitOption(kQuantityUnitMinutes, 'quantity_unit_minutes'),
  QuantityUnitOption(kQuantityUnitHours, 'quantity_unit_hours'),
  QuantityUnitOption(kQuantityUnitPages, 'quantity_unit_pages'),
  QuantityUnitOption(kQuantityUnitSteps, 'quantity_unit_steps'),
  QuantityUnitOption(kQuantityUnitGlasses, 'quantity_unit_glasses'),
  QuantityUnitOption(kQuantityUnitKilograms, 'quantity_unit_kilograms'),
  QuantityUnitOption(kQuantityUnitKilometers, 'quantity_unit_kilometers'),
];

bool isQuantityUnitOption(String value) =>
    quantityUnitOptions.any((option) => option.value == value);

const _legacyQuantityUnitValues = <String, String>{
  'unit': kQuantityUnitTimes,
  'units': kQuantityUnitTimes,
  'раз': kQuantityUnitTimes,
  'раза': kQuantityUnitTimes,
  'times': kQuantityUnitTimes,
  'time': kQuantityUnitTimes,
  'минуты': kQuantityUnitMinutes,
  'минут': kQuantityUnitMinutes,
  'minutes': kQuantityUnitMinutes,
  'minute': kQuantityUnitMinutes,
  'часы': kQuantityUnitHours,
  'часов': kQuantityUnitHours,
  'hours': kQuantityUnitHours,
  'hour': kQuantityUnitHours,
  'страницы': kQuantityUnitPages,
  'страниц': kQuantityUnitPages,
  'pages': kQuantityUnitPages,
  'page': kQuantityUnitPages,
  'шаги': kQuantityUnitSteps,
  'шагов': kQuantityUnitSteps,
  'steps': kQuantityUnitSteps,
  'step': kQuantityUnitSteps,
  'стаканы': kQuantityUnitGlasses,
  'стаканов': kQuantityUnitGlasses,
  'glasses': kQuantityUnitGlasses,
  'glass': kQuantityUnitGlasses,
  'кг': kQuantityUnitKilograms,
  'kg': kQuantityUnitKilograms,
  'км': kQuantityUnitKilometers,
  'km': kQuantityUnitKilometers,
};

/// Returns a built-in key for a saved unit, including legacy free-text values.
String? quantityUnitOptionValue(String value) {
  final normalized = value.trim();
  if (isQuantityUnitOption(normalized)) return normalized;
  return _legacyQuantityUnitValues[normalized.toLowerCase()];
}

/// Translates built-in units while preserving old/custom free-text values.
String displayQuantityUnit(String value, String Function(String) translate) {
  final optionValue = quantityUnitOptionValue(value);
  if (optionValue == null) return value.trim();
  final option = quantityUnitOptions.firstWhere(
    (item) => item.value == optionValue,
  );
  return translate(option.labelKey);
}

const int kMaxTaskAttachmentsPerTask = 20;
const int kMaxTaskDescriptionBlocksPerTask = 1;
const int kMaxTaskQuantityBlocksPerTask = 3;

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
    final mimeType =
        json['mimeType'] is String
            ? (json['mimeType'] as String).trim().toLowerCase()
            : null;
    final normalizedValue =
        type == TaskAttachmentType.link
            ? normalizeTaskAttachmentLink(value)
            : value;
    if (normalizedValue == null ||
        (type != TaskAttachmentType.link &&
            !isSafeTaskAttachmentMetadata(name, mimeType))) {
      throw const FormatException('Invalid task attachment metadata');
    }

    return TaskAttachment(
      id: id,
      type: type,
      name: attachmentDisplayName(name),
      value: normalizedValue,
      mimeType: mimeType,
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
    final nextMimeType =
        mimeType == const Object() ? this.mimeType : mimeType as String?;
    final normalizedValue =
        nextType == TaskAttachmentType.link
            ? normalizeTaskAttachmentLink(nextValue)
            : nextValue;
    if (normalizedValue == null ||
        (nextType != TaskAttachmentType.link &&
            !isSafeTaskAttachmentMetadata(name ?? this.name, nextMimeType))) {
      throw const FormatException('Invalid task attachment metadata');
    }
    return TaskAttachment(
      id: id ?? this.id,
      type: nextType,
      name: attachmentDisplayName(name ?? this.name),
      value: normalizedValue,
      mimeType: nextMimeType,
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
  final DescriptionFormat descriptionFormat;
  final List<TaskAttachment> attachments;

  const TaskInfoBlock._({
    required this.id,
    required this.type,
    required this.label,
    required this.currentValue,
    required this.targetValue,
    required this.unit,
    required this.text,
    required this.descriptionFormat,
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
      descriptionFormat: DescriptionFormat.plainText,
      attachments: const [],
    );
  }

  factory TaskInfoBlock.description({
    required String id,
    String text = '',
    DescriptionFormat format = DescriptionFormat.markdown,
    List<TaskAttachment> attachments = const [],
  }) {
    final safeText = sanitizeTaskDescription(text);
    if (safeText.length > kMaxTaskDescriptionLength) {
      throw const FormatException('Description is too long');
    }
    final safeAttachments = <TaskAttachment>[];
    for (final attachment in attachments) {
      if (attachment.type == TaskAttachmentType.link) {
        final normalized = normalizeTaskAttachmentLink(attachment.value);
        if (normalized == null) {
          throw const FormatException(
            'Only safe http and https links are allowed',
          );
        }
        safeAttachments.add(attachment.copyWith(value: normalized));
      } else if (!isSafeTaskAttachmentMetadata(
            attachment.name,
            attachment.mimeType,
          ) ||
          !isSafeStoredTaskAttachmentValue(attachment.value)) {
        throw const FormatException('Invalid task attachment metadata');
      } else {
        safeAttachments.add(
          attachment.copyWith(name: attachmentDisplayName(attachment.name)),
        );
      }
    }
    return TaskInfoBlock._(
      id: id,
      type: TaskInfoBlockType.description,
      label: '',
      currentValue: 0,
      targetValue: 0,
      unit: '',
      text: safeText,
      descriptionFormat: format,
      attachments: List.unmodifiable(safeAttachments),
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
          format: descriptionFormatFromName(
            json.containsKey('format') ? json['format'] : null,
          ),
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
    if (type == TaskInfoBlockType.description)
      'format': descriptionFormatName(descriptionFormat),
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
    DescriptionFormat? descriptionFormat,
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
      format: descriptionFormat ?? this.descriptionFormat,
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

/// Merges legacy/imported duplicate description blocks into the first one.
/// New task creation is still guarded by [TaskProvider], but old data must be
/// normalized without losing text or attachment references when it is loaded.
List<TaskInfoBlock> normalizeTaskInfoBlocks(List<TaskInfoBlock> blocks) {
  final normalized = <TaskInfoBlock>[];
  TaskInfoBlock? description;
  var descriptionIndex = -1;

  for (final block in blocks) {
    if (block.type != TaskInfoBlockType.description) {
      normalized.add(block);
      continue;
    }

    if (description == null) {
      description = block;
      descriptionIndex = normalized.length;
      normalized.add(block);
      continue;
    }

    final parts =
        [
          description.text.trim(),
          block.text.trim(),
        ].where((part) => part.isNotEmpty).toList();
    final combinedText = String.fromCharCodes(
      parts.join('\n\n').runes.take(kMaxTaskDescriptionLength),
    );
    description = description.copyWith(
      text: combinedText,
      descriptionFormat:
          description.descriptionFormat == DescriptionFormat.markdown ||
                  block.descriptionFormat == DescriptionFormat.markdown
              ? DescriptionFormat.markdown
              : DescriptionFormat.plainText,
      attachments: [...description.attachments, ...block.attachments],
    );
    normalized[descriptionIndex] = description;
  }

  return normalized;
}
