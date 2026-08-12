import 'package:flutter/material.dart';

import '../../../core/description_markdown.dart';
import '../models/task_model.dart';

class DescriptionBacklinks extends StatelessWidget {
  final Set<String> tags;
  final List<TaskItem> backlinks;
  final List<TaskItem> relatedTasks;
  final ValueChanged<String> onTagTap;
  final ValueChanged<TaskItem> onTaskTap;
  final String tagsLabel;
  final String backlinksLabel;
  final String relatedLabel;
  final String Function(TaskItem task)? taskSubtitle;

  const DescriptionBacklinks({
    super.key,
    required this.tags,
    required this.backlinks,
    required this.relatedTasks,
    required this.onTagTap,
    required this.onTaskTap,
    required this.tagsLabel,
    required this.backlinksLabel,
    required this.relatedLabel,
    this.taskSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty && backlinks.isEmpty && relatedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isNotEmpty) ...[
            _sectionLabel(context, tagsLabel),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              label: tagsLabel,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final tag in tags)
                    InputChip(
                      key: ValueKey('description-tag-$tag'),
                      label: Text('#$tag'),
                      onPressed: () => onTagTap(tag),
                      avatar: Icon(
                        Icons.tag,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (backlinks.isNotEmpty) ...[
            if (tags.isNotEmpty) const SizedBox(height: 12),
            _sectionLabel(context, backlinksLabel),
            const SizedBox(height: 4),
            _taskList(context, backlinks, keyPrefix: 'backlink'),
          ],
          if (relatedTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionLabel(context, relatedLabel),
            const SizedBox(height: 4),
            _taskList(context, relatedTasks, keyPrefix: 'related'),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Text(
      label,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
    );
  }

  Widget _taskList(
    BuildContext context,
    List<TaskItem> tasks, {
    required String keyPrefix,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 224),
      child: ListView.builder(
        key: ValueKey('description-$keyPrefix-list'),
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          final subtitle = taskSubtitle?.call(task) ?? _defaultSubtitle(task);
          return Semantics(
            button: true,
            label: subtitle.isEmpty ? task.title : '${task.title}, $subtitle',
            child: ListTile(
              key: ValueKey('description-$keyPrefix-${task.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                task.isCompleted ? Icons.check_circle_outline : Icons.task_alt,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle:
                  subtitle.isEmpty
                      ? null
                      : Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              onTap: () => onTaskTap(task),
            ),
          );
        },
      ),
    );
  }

  String _defaultSubtitle(TaskItem task) {
    final source = task.infoBlocks
        .where((block) => block.text.trim().isNotEmpty)
        .map((block) => block.text.trim())
        .join(' ');
    return descriptionPreview(
      source,
      maxCodePoints: 96,
    ).replaceAll(RegExp(r'\s+'), ' ');
  }
}
