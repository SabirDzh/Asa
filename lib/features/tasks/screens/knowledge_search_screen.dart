import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/input_utils.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../services/description_index.dart';
import '../widgets/task_detail_sheet.dart';

Future<void> showKnowledgeSearchSheet(
  BuildContext context, {
  String initialQuery = '',
}) async {
  var openingTask = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final mediaQuery = MediaQuery.of(sheetContext);
      final keyboardInset = mediaQuery.viewInsets.bottom;
      final availableHeight = math.max(
        0.0,
        mediaQuery.size.height - keyboardInset,
      );
      final sheetHeight = math.min(
        mediaQuery.size.height * 0.86,
        availableHeight,
      );
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: KnowledgeSearchScreen(
              initialQuery: initialQuery,
              showSearchField: true,
              onTaskTap: (task) {
                if (openingTask) return;
                openingTask = true;
                Navigator.of(sheetContext).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    unawaited(showTaskDetailSheet(context, task));
                  }
                });
              },
            ),
          ),
        ),
      );
    },
  );
}

class KnowledgeSearchScreen extends StatefulWidget {
  final String initialQuery;
  final bool showSearchField;
  final ValueChanged<TaskItem>? onTaskTap;

  const KnowledgeSearchScreen({
    super.key,
    this.initialQuery = '',
    this.showSearchField = true,
    this.onTaskTap,
  });

  @override
  State<KnowledgeSearchScreen> createState() => _KnowledgeSearchScreenState();
}

class _KnowledgeSearchScreenState extends State<KnowledgeSearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant KnowledgeSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.showSearchField &&
        oldWidget.initialQuery != widget.initialQuery &&
        _controller.text != widget.initialQuery) {
      _controller.value = TextEditingValue(
        text: widget.initialQuery,
        selection: TextSelection.collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _query => _controller.text.trim();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final provider = context.watch<TaskProvider>();
    final results = provider.searchKnowledge(_query);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showSearchField) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('knowledge-search-input'),
                    controller: _controller,
                    autofocus: true,
                    inputFormatters: [textInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: settings.tr('knowledge_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon:
                          _query.isEmpty
                              ? null
                              : IconButton(
                                tooltip: settings.tr('clear'),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              settings.tr('knowledge_search'),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Expanded(
          child:
              results.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        settings.tr('knowledge_search_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  )
                  : ListView.builder(
                    key: const ValueKey('knowledge-search-results'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: results.length,
                    itemBuilder:
                        (context, index) => _KnowledgeResultTile(
                          result: results[index],
                          onTap:
                              () => (widget.onTaskTap ??
                                  (task) => showTaskDetailSheet(context, task))(
                                results[index].task,
                              ),
                        ),
                  ),
        ),
      ],
    );
  }
}

class _KnowledgeResultTile extends StatelessWidget {
  final DescriptionSearchResult result;
  final VoidCallback onTap;

  const _KnowledgeResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final matchLabels = result.matchedFields
        .map((field) => _matchLabel(settings, field))
        .where((label) => label.isNotEmpty)
        .join(' · ');
    final description = result.task.infoBlocks
        .where((block) => block.text.trim().isNotEmpty)
        .map((block) => block.text.trim())
        .join(' ');

    return Semantics(
      button: true,
      label:
          '${result.task.title}${matchLabels.isEmpty ? '' : ', $matchLabels'}',
      child: Card(
        key: ValueKey('knowledge-result-${result.task.id}'),
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          onTap: onTap,
          leading: Icon(
            result.task.isCompleted
                ? Icons.check_circle_outline
                : Icons.task_alt,
            color: colorScheme.primary,
          ),
          title: Text(
            result.task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (matchLabels.isNotEmpty)
                Text(
                  matchLabels,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.primary, fontSize: 12),
                ),
              if (description.isNotEmpty)
                Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  String _matchLabel(SettingsProvider settings, String field) {
    return switch (field) {
      'title' => settings.tr('knowledge_match_title'),
      'folder' => settings.tr('knowledge_match_folder'),
      'tag' => settings.tr('knowledge_match_tag'),
      'description' => settings.tr('knowledge_match_description'),
      _ => '',
    };
  }
}

// Keep this import-independent helper available to widget callers that need a
// predictable task type without exposing the result tile implementation.
TaskItem knowledgeResultTask(DescriptionSearchResult result) => result.task;
