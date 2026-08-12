import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/screens/knowledge_search_screen.dart';
import 'package:asa/features/tasks/widgets/description_backlinks.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders tags, backlinks, and related tasks with navigation', (
    tester,
  ) async {
    final source = TaskItem(
      id: 'source',
      title: 'Write report',
      infoBlocks: [
        TaskInfoBlock.description(id: 'description', text: 'Notes about #work'),
      ],
    );
    final related = TaskItem(id: 'related', title: 'Review report');
    TaskItem? selectedTask;
    String? selectedTag;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DescriptionBacklinks(
              tags: const {'work'},
              backlinks: [source],
              relatedTasks: [related],
              tagsLabel: 'Tags',
              backlinksLabel: 'Backlinks',
              relatedLabel: 'Related tasks',
              onTagTap: (tag) => selectedTag = tag,
              onTaskTap: (task) => selectedTask = task,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tags'), findsOneWidget);
    expect(find.byKey(const ValueKey('description-tag-work')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('description-backlink-source')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('description-related-related')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('description-tag-work')));
    await tester.tap(find.byKey(const ValueKey('description-backlink-source')));
    await tester.pump();

    expect(selectedTag, 'work');
    expect(selectedTask?.id, 'source');
  });

  testWidgets('closes the knowledge sheet before opening a task detail', (
    tester,
  ) async {
    final provider = TaskProvider();
    await provider.ready;
    provider.addTaskRaw(
      TaskItem(
        id: 'sheet-task',
        title: 'Read book',
        infoBlocks: [
          TaskInfoBlock.description(id: 'description', text: '#reading'),
        ],
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create:
                (_) => SettingsProvider(systemLanguageCodeProvider: () => 'en'),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: ElevatedButton(
                    key: const ValueKey('open-knowledge-search'),
                    onPressed:
                        () => showKnowledgeSearchSheet(
                          context,
                          initialQuery: 'reading',
                        ),
                    child: const Text('Search'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-knowledge-search')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('knowledge-search-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-result-sheet-task')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('knowledge-result-sheet-task')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('knowledge-search-input')), findsNothing);
    provider.dispose();
  });

  testWidgets('stays usable on a narrow viewport with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DescriptionBacklinks(
                tags: const {'long-project-tag'},
                backlinks: [
                  TaskItem(
                    id: 'backlink',
                    title: 'A task with a deliberately long title',
                  ),
                ],
                relatedTasks: const [],
                tagsLabel: 'Tags',
                backlinksLabel: 'Backlinks',
                relatedLabel: 'Related tasks',
                onTagTap: (_) {},
                onTaskTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backlinks'), findsOneWidget);
  });

  testWidgets('shows ranked knowledge results and opens the selected task', (
    tester,
  ) async {
    final provider = TaskProvider();
    await provider.ready;
    provider.addTaskRaw(
      TaskItem(
        id: 'knowledge-task',
        title: 'Read book',
        infoBlocks: [
          TaskInfoBlock.description(
            id: 'description',
            text: 'A note about #reading',
          ),
        ],
      ),
    );
    TaskItem? selected;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider(
            create:
                (_) => SettingsProvider(systemLanguageCodeProvider: () => 'en'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: KnowledgeSearchScreen(
              initialQuery: 'reading',
              showSearchField: false,
              onTaskTap: (task) => selected = task,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('knowledge-result-knowledge-task')),
      findsOneWidget,
    );
    expect(
      provider.searchKnowledge('reading').single.matchedFields,
      contains('tag'),
    );

    await tester.tap(
      find.byKey(const ValueKey('knowledge-result-knowledge-task')),
    );
    expect(selected?.id, 'knowledge-task');
    provider.dispose();
  });
}
