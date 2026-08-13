import '../../../core/description_format.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';

/// The result of resolving a user-authored `[[target]]` reference.
class DescriptionLinkResolution {
  final String target;
  final TaskItem? task;
  final List<TaskItem> candidates;

  const DescriptionLinkResolution({
    required this.target,
    required this.task,
    required this.candidates,
  });

  bool get isAmbiguous => task == null && candidates.length > 1;
  bool get isUnresolved => task == null && candidates.isEmpty;
  bool get isResolved => task != null;
}

/// The result of resolving a `^block-id` reference to the task and paragraph
/// that defines it.
class DescriptionBlockResolution {
  final String blockId;
  final TaskItem? task;
  final String text;

  const DescriptionBlockResolution({
    required this.blockId,
    required this.task,
    required this.text,
  });

  bool get isResolved => task != null;
}

/// Content ready to be transcluded inline via `![[Task]]`.
class DescriptionEmbedContent {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;

  const DescriptionEmbedContent({
    required this.text,
    required this.format,
    required this.attachments,
  });
}

/// A task that links to another task, with the sentence around the link.
class DescriptionBacklinkContext {
  final TaskItem task;
  final String snippet;

  const DescriptionBacklinkContext({required this.task, required this.snippet});
}
