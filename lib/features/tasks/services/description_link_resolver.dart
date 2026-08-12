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
