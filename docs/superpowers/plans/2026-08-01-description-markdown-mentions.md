# Описание задачи: Markdown, mentions и единое меню вложений — план реализации

> **Для agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (рекомендуется) или `superpowers:executing-plans` для выполнения этого плана по задачам. Шаги используют чекбоксы (`- [ ]`) для отслеживания.

**Goal:** Добавить для блоков «Описание» безопасный Markdown-рендеринг, превью до 150 символов с отдельной прокручиваемой шторкой полного текста, единое меню добавления вложений и выбор вложений через `@`-mentions.

**Architecture:** Расширить `TaskInfoBlock` явным форматом описания, чтобы старые JSON без поля формата продолжили отображаться как обычный текст, а новые/отредактированные описания сохранялись как Markdown. Вынести Markdown-рендеринг, токены mentions и меню вложений в небольшие переиспользуемые компоненты, а `TaskEditorSheet` и `TaskDetailSheet` оставить координаторами состояния и действий. Упоминание будет храниться как обычный Markdown-link с безопасной схемой `attachment://<id>`, но в интерфейсе отображаться как акцентированный inline-chip с именем и типом вложения; нажатие будет открывать существующее вложение, а не внешний URL.

**Tech Stack:** Flutter/Dart 3.7+, Material widgets, Provider, существующие `TaskAttachment`/`TaskAttachmentService`, `flutter_markdown_plus` (после проверки совместимости актуальной версии) и пакет `markdown` для CommonMark/GFM extension set.

## Global Constraints

- Не ломать старые данные: отсутствие поля `format` в JSON означает `plainText`, а не Markdown.
- Под «Markdown v2» в этом плане понимается безопасный CommonMark/GFM-подобный Markdown-режим с поддержкой заголовков, списков, emphasis, code, blockquote, таблиц, зачёркивания и ссылок. Это не Telegram MarkdownV2. Если требуется именно Telegram MarkdownV2 с обязательным экранированием специальных символов, до начала реализации нужно выбрать отдельную грамматику и тест-кейсы.
- Разрешать внешние ссылки только со схемами `http` и `https`; `javascript:`, `file:`, `content:`, `intent:` и любые прочие схемы не открывать.
- Ссылки `attachment://<id>` разрешать только после поиска `id` среди вложений текущего блока; неизвестный id отображать как неактивный/обычный текст и не открывать.
- Ограничение хранения описания остаётся `kMaxTaskDescriptionLength = 10000`; срез 150 символов применяется только к превью в детальном просмотре.
- Не удалять старые отдельные ключи локализации `add_link`, `add_image`, `add_file`: они будут использоваться в выпадающем меню.
- Все три варианта добавления вложения должны иметь одинаковую ширину и одинаковую минимальную высоту 48 logical pixels.
- Сохранить текущую глобальную бизнес-валидацию `kMaxTaskAttachmentsPerTask = 20`.
- Не показывать системные пути к файлам пользователю в mention-тексте: пользователь видит безопасное имя вложения, а путь остаётся только в модели.
- Не заменять существующие функции открытия вложений; повторно использовать `_openAttachment`, `openTaskLink`, `openTaskAttachment` и `TaskAttachmentService`.
- После каждого крупного изменения запускать targeted tests; перед завершением — `flutter analyze` и полный `flutter test`.

---

## Design contract: как пользователь увидит вложенность

### 1. В редакторе

Под полем описания находится одна горизонтальная группа:

```text
┌─────────────────────────────────────────────┬────┐
│  Добавить ссылку                         ▾  │  + │
└─────────────────────────────────────────────┴────┘
```

- Левая часть — `DropdownButton`/кастомный segmented control фиксированной высоты 48; она занимает всё доступное место.
- По умолчанию выбрано «Добавить ссылку».
- Нажатие на левую часть открывает компактное меню из трёх одинаковых по ширине пунктов: «Добавить ссылку», «Добавить изображение», «Добавить файл».
- При выборе пункта меняется только выбранный тип; picker/dialog не запускается автоматически. Это позволяет сначала выбрать действие, затем нажать `+`.
- Нажатие `+` запускает действие выбранного типа для текущего блока.
- Уже добавленные вложения остаются ниже как `InputChip`: иконка типа, безопасное имя, удаление по `onDeleted`, открытие по нажатию.

После ввода `@` в описании над клавиатурой или непосредственно над нижней границей поля появляется suggestion popup. В нём:

```text
Вложения
┌──────────────────────────────┐
│ 🔗  Документация              │
│ 🖼  screenshot.png             │
│ 📎  contract.pdf              │
└──────────────────────────────┘
```

- В список попадают только вложения текущего блока.
- Текст после `@` используется как фильтр: `@scr` оставляет `screenshot.png`.
- Если сразу после `@` ничего не введено, показываются все вложения.
- Нажатие пальцем по строке заменяет диапазон от последнего `@` до текущего курсора на токен `[@Имя вложения](attachment://id) `.
- Внутри редактора токен визуально выделяется цветом акцента и подчёркиванием/полужирным стилем как mention; если нативный `TextField` не позволяет надёжно отрисовать chip, fallback — стилизованный Markdown-токен без изменения сохраняемого текста.
- Если вложений нет, popup не показывается; `@` остаётся обычным символом.
- Если пользователь нажал Backspace и удалил `@`, popup закрывается.
- Если пользователь нажал вне списка или изменил курсор в другой позиции, popup закрывается без изменения текста.

### 2. В детальном просмотре

Для каждого description-блока:

- Текст до 150 Unicode code points показывается полностью.
- Текст длиннее 150 code points показывается как Markdown-превью, вычисленное безопасным helper-ом: первые 150 code points после удаления только конечного незавершённого Markdown-фрагмента не должны приводить к падению рендера; визуальный суффикс — `…`.
- Отдельная кнопка `Показать полностью` не отображается.
- Если текст состоит только из whitespace, текстовая часть не отображается.
- Область самого preview является интерактивной; нажатие на неё открывает отдельную modal bottom sheet с заголовком «Описание»/`description_block`, drag handle и `isScrollControlled: true`. Для короткого текста шторка также открывается по нажатию, но показывает тот же полный текст.
- Внутри шторки — `SingleChildScrollView` и полный Markdown-рендеринг; длинные списки, таблицы и переносы прокручиваются вертикально.
- Inline mention рендерится как цветной pill: иконка `link`/`image`/`attach_file`, имя вложения, цвет акцента. Нажатие открывает соответствующий `TaskAttachment` текущего блока.
- Обычная Markdown-ссылка отображается как link-style text и проходит через проверку `normalizeTaskAttachmentLink` перед открытием.
- Сломанный или неизвестный `attachment://id` не вызывает исключение и не открывает ничего; отображается приглушённым текстом с tooltip/snackbar при нажатии.

---

## File map

**Create:**

- `lib/core/description_markdown.dart` — формат описания, safe URL policy, Markdown preview helper и общие функции разбора mention-токенов.
- `lib/features/tasks/widgets/attachment_action_menu.dart` — единая кнопка выбора типа вложения и правая кнопка `+`.
- `lib/features/tasks/widgets/attachment_mention_overlay.dart` — вычисление trigger range, фильтрация и popup выбора вложения.
- `lib/features/tasks/widgets/description_full_sheet.dart` — отдельная прокручиваемая шторка полного описания.
- `test/description_markdown_test.dart` — unit-тесты формата, preview, token parsing и safe URL policy.
- `test/attachment_mention_overlay_test.dart` — widget-тесты `@` autocomplete и вставки токена.
- `test/task_detail_sheet_test.dart` — widget-тесты превью и полной шторки.

**Modify:**

- `pubspec.yaml` — добавить проверенную Markdown-зависимость.
- `pubspec.lock` — обновить lockfile командой `flutter pub get`, не редактировать вручную.
- `lib/features/tasks/models/task_info_block.dart` — добавить формат описания и сериализацию с обратной совместимостью.
- `lib/features/tasks/widgets/task_editor_sheet.dart` — подключить Markdown editor behavior, mention overlay и единое меню вложений.
- `lib/features/tasks/widgets/task_detail_sheet.dart` — заменить plain `Text` на preview renderer и кнопку полной шторки.
- `lib/core/app_strings.dart` — добавить строки для preview, меню вложений, mention popup, неизвестного вложения и Markdown helper text на русском/английском.
- `test/task_model_test.dart` — расширить round-trip/migration проверки.
- `test/task_editor_sheet_test.dart` — заменить проверки трёх старых кнопок на единое меню и добавить тесты выбора действия.

---

## Task 1: Зафиксировать Markdown-зависимость и безопасную политику ссылок

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/core/description_markdown.dart`
- Create: `test/description_markdown_test.dart`

**Interfaces:**
- Produces `DescriptionFormat`, `descriptionPreview`, `extractAttachmentMention`, `replaceMentionTrigger`, `isSafeDescriptionHref` and `renderDescriptionMarkdown`.
- Consumes `normalizeTaskAttachmentLink` from `lib/core/task_attachment_validation.dart`.

- [ ] **Step 1: Проверить актуальную совместимую версию пакета**

Перед редактированием `pubspec.yaml` выполнить:

```bash
flutter pub outdated --show-all
flutter pub add flutter_markdown_plus
```

Если актуальная версия `flutter_markdown_plus` не совместима с SDK проекта, выбрать совместимый поддерживаемый пакет после проверки его API, а не фиксировать версию из памяти. После установки проверить:

```bash
flutter pub get
flutter analyze
```

Ожидаемый результат: зависимости разрешены, существующий проект анализируется без новых ошибок.

- [ ] **Step 2: Добавить формат описания и безопасные helper-ы**

В `lib/core/description_markdown.dart` определить:

```dart
enum DescriptionFormat { plainText, markdown }

const int kDescriptionPreviewLength = 150;
const String kAttachmentMentionScheme = 'attachment';

String descriptionFormatName(DescriptionFormat format) => format.name;

DescriptionFormat descriptionFormatFromName(Object? value) {
  return value == DescriptionFormat.markdown.name
      ? DescriptionFormat.markdown
      : DescriptionFormat.plainText;
}

bool isSafeDescriptionHref(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

String descriptionPreview(String source, {int maxCodePoints = 150}) {
  final value = source.trim();
  final characters = value.runes.toList();
  if (characters.length <= maxCodePoints) return value;
  return '${String.fromCharCodes(characters.take(maxCodePoints))}…';
}

class AttachmentMention {
  final String id;
  final String label;

  const AttachmentMention({required this.id, required this.label});
}
```

`descriptionPreview` должен считать Unicode code points через `runes`, а не UTF-16 `substring`, чтобы не разрезать emoji/суррогатную пару. Markdown-превью можно строить из исходного текста, но оно обязано быть только preview; полный документ рендерится отдельно.

- [ ] **Step 3: Добавить разбор и замену mention-токена**

Использовать формат `[@safeLabel](attachment://uuid)`; label экранировать как минимум для `]`, `\` и control characters. ID проверять регулярным выражением UUID-safe значения или искать среди текущих вложений перед использованием.

```dart
final attachmentMentionPattern = RegExp(
  r'\[@([^\]]{1,128})\]\(attachment://([A-Za-z0-9_-]{1,128})\)',
);

AttachmentMention? extractAttachmentMention(String href, String label) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.scheme != kAttachmentMentionScheme) return null;
  final id = uri.path;
  if (id.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
    return null;
  }
  return AttachmentMention(id: id, label: label.trim());
}
```

Для `replaceMentionTrigger` входом сделать `TextEditingValue`, trigger range и `TaskAttachment`; результатом вернуть новый `TextEditingValue` с выделением после вставленного токена. Тестировать вставку в начале, середине, после пробела и при фильтре `@scr`.

- [ ] **Step 4: Добавить Markdown renderer wrapper**

`renderDescriptionMarkdown` должен принимать `source`, `format`, список вложений и callback `onAttachmentTap`. Для `plainText` возвращать `SelectableText`/`Text` с сохранением переносов; для `markdown` использовать `MarkdownBody` с GFM extension set.

Обработчик ссылок:

```dart
onTapLink: (text, href, title) {
  if (href == null) return;
  final mention = extractAttachmentMention(href, text);
  if (mention != null) {
    final attachment = attachments
        .where((item) => item.id == mention.id)
        .firstOrNull;
    if (attachment != null) onAttachmentTap(attachment);
    return;
  }
  if (isSafeDescriptionHref(href)) {
    onExternalLinkTap(href, title: title);
  }
}
```

Если выбранный Markdown-пакет не позволяет кастомно отобразить `attachment://` link как pill через документированный builder API, оставить ссылку семантически корректной, но использовать стилизованный link builder; не добавлять неподдерживаемый внутренний API. Проверка builder API должна быть частью этого шага.

- [ ] **Step 5: Написать unit-тесты до интеграции**

В `test/description_markdown_test.dart` добавить проверки:

```dart
test('preview uses 150 Unicode code points and ellipsis', () {
  final value = '😀' * 151;
  final preview = descriptionPreview(value);
  expect(preview.runes.length, 151); // 150 emoji + ellipsis
  expect(preview.endsWith('…'), isTrue);
});

test('short text is not truncated', () {
  expect(descriptionPreview('a' * 150), 'a' * 150);
});

test('unsafe URL schemes are rejected', () {
  expect(isSafeDescriptionHref('javascript:alert(1)'), isFalse);
  expect(isSafeDescriptionHref('file:///secret'), isFalse);
  expect(isSafeDescriptionHref('https://example.com'), isTrue);
});

test('attachment mention accepts only safe ids', () {
  expect(
    extractAttachmentMention('attachment://file-1', 'contract.pdf')!.id,
    'file-1',
  );
  expect(extractAttachmentMention('attachment://../secret', 'bad'), isNull);
});
```

- [ ] **Step 6: Запустить тесты**

```bash
flutter test test/description_markdown_test.dart
```

Ожидаемый результат: PASS. Если пакет не собирается или API отличается, исправить wrapper на основании установленной версии до перехода к следующим задачам.

---

## Task 2: Расширить модель `TaskInfoBlock` с обратной совместимостью

**Files:**
- Modify: `lib/features/tasks/models/task_info_block.dart`
- Modify: `lib/features/tasks/widgets/task_editor_sheet.dart`
- Modify: `test/task_model_test.dart`

**Interfaces:**
- `TaskInfoBlock` получает `final DescriptionFormat descriptionFormat`.
- `TaskInfoBlock.description` принимает `DescriptionFormat format = DescriptionFormat.markdown` для новых блоков.
- `TaskInfoBlock.fromJson` при отсутствии `format` передаёт `DescriptionFormat.plainText`.
- `copyWith` сохраняет текущий `descriptionFormat`, если новый формат не передан.

- [ ] **Step 1: Добавить поле и конструкторный параметр**

В `TaskInfoBlock` импортировать `description_markdown.dart`, добавить:

```dart
final DescriptionFormat descriptionFormat;
```

Для quantity использовать `DescriptionFormat.plainText`; для description сохранять переданный формат.

- [ ] **Step 2: Сделать JSON-миграцию детерминированной**

В `toJson` для description добавить:

```dart
if (type == TaskInfoBlockType.description)
  'format': descriptionFormatName(descriptionFormat),
```

В `fromJson`:

```dart
final format =
    json.containsKey('format')
        ? descriptionFormatFromName(json['format'])
        : DescriptionFormat.plainText;
```

Передавать `format` в `TaskInfoBlock.description`. Не менять текст старого блока и не пытаться автоматически трактовать его `*`, `_` или `[]` как Markdown.

- [ ] **Step 3: Обновить `copyWith`**

Добавить параметр:

```dart
DescriptionFormat? descriptionFormat,
```

При description передавать `descriptionFormat ?? this.descriptionFormat`; при quantity игнорировать его.

- [ ] **Step 4: При сохранении в новом редакторе включать Markdown**

В ветке description в `_submit` передавать:

```dart
TaskInfoBlock.description(
  id: block.id,
  text: sanitizeText(_descriptionControllers[block.id]!.text),
  format: DescriptionFormat.markdown,
  attachments: block.attachments,
)
```

Это означает: старые неоткрытые/неизменённые JSON остаются plain text, а любой блок, сохранённый через обновлённый редактор, получает Markdown-режим.

- [ ] **Step 5: Добавить model tests**

В `test/task_model_test.dart` проверить:

```dart
test('legacy description without format remains plain text', () {
  final block = TaskInfoBlock.fromJson({
    'id': 'legacy',
    'type': 'description',
    'text': '*literal*',
  });
  expect(block.descriptionFormat, DescriptionFormat.plainText);
});

test('markdown format survives JSON round trip', () {
  final block = TaskInfoBlock.description(
    id: 'notes',
    format: DescriptionFormat.markdown,
    text: '**bold**',
  );
  final restored = TaskInfoBlock.fromJson(block.toJson());
  expect(restored.descriptionFormat, DescriptionFormat.markdown);
  expect(restored.text, '**bold**');
});
```

- [ ] **Step 6: Запустить model/editor regression tests**

```bash
flutter test test/task_model_test.dart test/task_editor_sheet_test.dart
```

Ожидаемый результат: PASS; старые тесты на round-trip и plain-text sanitation не должны измениться по смыслу.

---

## Task 3: Реализовать единое меню добавления вложений

**Files:**
- Create: `lib/features/tasks/widgets/attachment_action_menu.dart`
- Modify: `lib/features/tasks/widgets/task_editor_sheet.dart`
- Modify: `lib/core/app_strings.dart`
- Modify: `test/task_editor_sheet_test.dart`

**Interfaces:**

```dart
enum AttachmentAction { link, image, file }

class AttachmentActionMenu extends StatelessWidget {
  final AttachmentAction selectedAction;
  final ValueChanged<AttachmentAction> onActionChanged;
  final VoidCallback onAdd;
  final bool enabled;
}
```

- [ ] **Step 1: Создать компонент с фиксированной высотой и единой шириной пунктов**

Компонент должен рендерить `Row`:

```dart
Expanded(child: _ActionSelector(...)),
const SizedBox(width: 8),
SizedBox(width: 48, height: 48, child: IconButton(...)),
```

Каждый пункт dropdown строить через `SizedBox(width: double.infinity, height: 48)` внутри `ConstrainedBox(minWidth: 240)`, чтобы три названия не создавали три разные ширины. Использовать локализованные label/icon для `link`, `image`, `file`.

- [ ] **Step 2: Подключить в `TaskEditorSheet`**

Заменить Wrap из трёх `_attachmentButton` на один `AttachmentActionMenu` в `_buildBlock`. В состоянии sheet добавить:

```dart
final _selectedAttachmentActions = <String, AttachmentAction>{};
```

Для каждого блока default — `AttachmentAction.link`. На `onActionChanged` вызвать `setState`; на `onAdd` вызвать существующий `_addLink`, `_addPickedAttachment(...image)` или `_addPickedAttachment(...file)`.

Не запускать picker при выборе пункта меню. Проверку лимита оставить в существующих `_addLink`/`_addPickedAttachment`, чтобы UI и тестовый picker сохраняли текущую защиту.

- [ ] **Step 3: Добавить локализацию**

Добавить русские и английские строки:

```dart
'attachment_action': 'Тип вложения',
'attachment_add_selected': 'Добавить выбранное',
'attachment_mention_title': 'Вложения',
'attachment_mention_empty': 'Вложений не найдено',
'full_description': 'Полное описание',
'unknown_attachment': 'Вложение недоступно',
```

- [ ] **Step 4: Обновить widget tests**

Сохранить compatibility keys только для подтверждения действий через новые semantics/keys, например:

```dart
expect(find.byKey(const ValueKey('attachment-action-menu')), findsOneWidget);
expect(find.byKey(const ValueKey('attachment-action-add')), findsOneWidget);
```

Проверить сценарии:

1. default label — «Добавить ссылку»;
2. открытие меню показывает ровно три пункта;
3. выбор «Добавить файл» меняет label, но не вызывает picker;
4. `+` вызывает picker ровно один раз;
5. при лимите 20 `+` не вызывает picker и показывает существующее сообщение;
6. кнопка `+` и selector имеют одинаковую высоту 48, а пункты меню — одинаковую ширину.

- [ ] **Step 5: Запустить тесты**

```bash
flutter test test/task_editor_sheet_test.dart
```

Ожидаемый результат: PASS.

---

## Task 4: Реализовать `@` autocomplete и вставку attachment mentions

**Files:**
- Create: `lib/features/tasks/widgets/attachment_mention_overlay.dart`
- Modify: `lib/features/tasks/widgets/task_editor_sheet.dart`
- Create: `test/attachment_mention_overlay_test.dart`

**Interfaces:**

```dart
class AttachmentMentionOverlay extends StatelessWidget {
  final List<TaskAttachment> attachments;
  final String query;
  final ValueChanged<TaskAttachment> onSelected;
  final VoidCallback onDismiss;
}

class MentionTrigger {
  final int start;
  final int end;
  final String query;

  const MentionTrigger({required this.start, required this.end, required this.query});
}

MentionTrigger? findMentionTrigger(String text, int cursorOffset);
```

- [ ] **Step 1: Реализовать поиск trigger range**

`findMentionTrigger` ищет последний `@` в текущей строке/после whitespace до курсора. Не считать `@` частью email/слова, если перед ним не начало текста и не whitespace. Не включать newline в query. Примеры:

```dart
expect(findMentionTrigger('@sc', 3), MentionTrigger(start: 0, end: 3, query: 'sc'));
expect(findMentionTrigger('text @sc', 8), MentionTrigger(start: 5, end: 8, query: 'sc'));
expect(findMentionTrigger('mail@test.com', 13), isNull);
```

- [ ] **Step 2: Создать overlay с keyboard-safe размещением**

В `TaskEditorSheet` получить `RenderBox` поля описания через `GlobalKey`, вычислить позицию и показать `OverlayEntry`. Popup разместить над полем/клавиатурой; если сверху недостаточно места, разместить под полем, но не за пределами `MediaQuery`.

Список должен быть `Material` с темой приложения, ограничением высоты 240 и `ListView.builder`. Строка вложения содержит:

```dart
Icon(_iconForAttachment(attachment.type)),
const SizedBox(width: 10),
Expanded(child: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
Text(_typeLabel(attachment.type)),
```

У каждого элемента `ValueKey('attachment-mention-${attachment.id}')` и минимум 48 px высоты.

- [ ] **Step 3: Подключить listener к description controller**

Для каждого description controller добавить listener и отслеживать `controller.selection.baseOffset`. При каждом изменении:

1. вычислить `MentionTrigger`;
2. отфильтровать `block.attachments` по `attachment.name.toLowerCase().contains(query.toLowerCase())`;
3. если trigger и результаты есть — обновить/создать OverlayEntry;
4. иначе удалить entry.

В `dispose` удалить listener и OverlayEntry для каждого блока, чтобы не оставить stale overlay после закрытия sheet.

- [ ] **Step 4: Реализовать выбор вложения**

При выборе вызвать `replaceMentionTrigger` и присвоить controller новое `TextEditingValue`, сохранив selection после пробела. Затем закрыть popup и вернуть фокус в поле. Сохраняемый текст должен иметь вид:

```text
Проверить [@Документация](attachment://link-1) перед встречей
```

- [ ] **Step 5: Добавить editor widget tests**

В `test/attachment_mention_overlay_test.dart` проверить:

```dart
testWidgets('typing @ opens attachment suggestions', (tester) async { ... });
testWidgets('typing query filters suggestions', (tester) async { ... });
testWidgets('tapping suggestion inserts safe markdown mention', (tester) async { ... });
testWidgets('removing @ closes suggestions', (tester) async { ... });
testWidgets('unknown attachment id is never opened', (tester) async { ... });
```

Тестовый task должен содержать link, image и file, чтобы проверить иконки/label. Для вставки проверять точное значение `controller.text` через доступный test key/обёртку, а не только наличие popup.

- [ ] **Step 6: Запустить тесты**

```bash
flutter test test/attachment_mention_overlay_test.dart test/task_editor_sheet_test.dart
```

Ожидаемый результат: PASS без зависших OverlayEntry и без `setState() called after dispose`.

---

## Task 5: Добавить детальное preview и отдельную шторку полного описания

**Files:**
- Create: `lib/features/tasks/widgets/description_full_sheet.dart`
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart`
- Modify: `lib/core/description_markdown.dart`
- Modify: `lib/core/app_strings.dart`
- Create: `test/task_detail_sheet_test.dart`

**Interfaces:**

```dart
Future<void> showFullDescriptionSheet(
  BuildContext context, {
  required String text,
  required DescriptionFormat format,
  required List<TaskAttachment> attachments,
});

class DescriptionPreview extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final ValueChanged<TaskAttachment> onAttachmentTap;
  final VoidCallback onTap;
}
```

- [ ] **Step 1: Создать `DescriptionPreview`**

Компонент:

- не строит никакой кнопки раскрытия;
- для короткого текста показывает полный текст;
- для длинного текста использует `descriptionPreview(text)` и делает всю область preview tappable;
- для `plainText` использует `Text`/`SelectableText` с сохранением переносов;
- для `markdown` использует тот же renderer wrapper, что и full sheet;
- вызывает `onTap` при нажатии на сам preview, чтобы открыть full sheet.

Важно: нельзя просто обрезать Markdown source и считать его отдельным валидным документом без защиты. Если срез заканчивается внутри `[label](url)`, code fence или emphasis, preview должен использовать plain-text fallback/безопасный text extraction; полный документ всегда рендерится из исходного `block.text`.

- [ ] **Step 2: Создать full description bottom sheet**

`showFullDescriptionSheet` вызывает:

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => DescriptionFullSheet(...),
);
```

`DescriptionFullSheet` должен иметь:

- высоту до `MediaQuery.sizeOf(context).height * 0.9`;
- верхний handle, заголовок и кнопку закрытия;
- `Expanded(child: SingleChildScrollView(...))`, чтобы полный текст реально скроллился;
- SafeArea и отступы, совпадающие с текущими `TaskDetailSheet`;
- callbacks для открытия link/image/file, используя текущие `openTaskLink` и `openTaskAttachment`.

- [ ] **Step 3: Подключить в `_TaskDetailSheet`**

В `_buildInfoBlock` для description заменить:

```dart
Text(block.text.trim(), style: TextStyle(color: textColor)),
```

на `DescriptionPreview`. Список вложений под description сохранить как отдельные ActionChip: mention в тексте — быстрый inline-доступ, chips — полный список и fallback для тех вложений, которые не упомянуты.

Для `onShowFull` передать `block.text`, `block.descriptionFormat` и `block.attachments`. Для quantity-потока ничего не менять.

- [ ] **Step 4: Отрисовать mention как inline attachment chip**

В Markdown wrapper добавить builder/callback для `attachment://`. На выходе использовать `WidgetSpan`/документированный inline builder выбранного Markdown-пакета с:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: AppColors.primary.withValues(alpha: 0.14),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(typeIcon, size: 14),
    const SizedBox(width: 4),
    Text('@$label'),
  ]),
)
```

Если package renderer поддерживает только `TextSpan`, использовать `TextSpan(text: '@$label', style: accentStyle)` и сохранять доступность через link semantics; не вставлять `WidgetSpan` через неподдержанный API.

- [ ] **Step 5: Добавить detail sheet tests**

В `test/task_detail_sheet_test.dart` создать MaterialApp с `TaskProvider`, `SettingsProvider` и задачей с description blocks. Проверить:

1. 150 символов отображаются полностью и не показывают отдельную кнопку;
2. 151 символ отображается со срезом и `…`, также без отдельной кнопки;
3. нажатие непосредственно на preview открывает отдельную шторку с заголовком полного описания;
4. полный текст присутствует внутри `SingleChildScrollView` и длинный контент не обрезается;
5. Markdown `**bold**` отображается как форматированный текст;
6. legacy block без `format` остаётся plain text;
7. валидный mention имеет имя/иконку вложения и открывается через callback;
8. неизвестный `attachment://id` не падает и не запускает открытие файла;
9. `javascript:` link не открывается.

- [ ] **Step 6: Запустить tests**

```bash
flutter test test/task_detail_sheet_test.dart test/description_markdown_test.dart
```

Ожидаемый результат: PASS.

---

## Task 6: Интеграционная проверка, accessibility и регрессии

**Files:**
- Modify: `lib/features/tasks/widgets/task_editor_sheet.dart` — только для исправления focus/overlay и accessibility после интеграционных тестов.
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart` — только для исправления layout/accessibility после интеграционных тестов.
- Modify: `lib/features/tasks/widgets/description_full_sheet.dart` — только для исправления прокрутки/доступности после интеграционных тестов.
- Modify: `test/task_editor_sheet_test.dart` — добавить регрессионные проверки keyboard/focus, если они выявлены тестами.
- Modify: `test/folder_detail_screen_test.dart` — обновить только при изменении публичного поведения открытия detail sheet.

- [ ] **Step 1: Проверить keyboard/focus сценарии**

Проверить вручную на Android/iOS simulator:

1. открыть редактор, добавить description;
2. набрать `@`, выбрать вложение пальцем;
3. открыть selector, выбрать image, нажать `+`, вернуться в описание;
4. закрыть клавиатуру, прокрутить editor;
5. сохранить, открыть detail sheet, нажать mention;
6. нажать на preview описания, прокрутить полный Markdown.

Проверить, что popup не перекрывает системную клавиатуру, кнопки не становятся недоступными при app scale и overlay удаляется при закрытии editor.

- [ ] **Step 2: Добавить semantics и доступные зоны нажатия**

Для selector, `+`, mention rows и `Показать полностью` задать tooltip/semantic label, минимум 48x48 touch target и уникальные keys. У mention дополнительно сообщать имя вложения и тип через `Semantics(label: ...)`.

- [ ] **Step 3: Выполнить targeted regression suite**

```bash
flutter test \
  test/task_model_test.dart \
  test/task_editor_sheet_test.dart \
  test/attachment_mention_overlay_test.dart \
  test/task_detail_sheet_test.dart \
  test/folder_detail_screen_test.dart \
  test/export_import_service_test.dart \
  test/sync_service_test.dart
```

Ожидаемый результат: все перечисленные тесты PASS.

- [ ] **Step 4: Выполнить анализ и полный suite**

```bash
flutter analyze
flutter test
```

Ожидаемый результат: `No issues found!` и завершение полного тестового набора с нулевым кодом.

- [ ] **Step 5: Провести финальный review**

Проверить diff на отсутствие:

- ручного редактирования `pubspec.lock`;
- небезопасных `Uri.parse` без схемной проверки;
- `substring(0, 150)` по UTF-16;
- открытия вложения до проверки принадлежности текущему блоку;
- дублирования логики picker/attachment validation;
- изменений в quantity-блоках, не связанных с задачей;
- hardcoded русских строк вне `app_strings.dart`.

---

## Acceptance criteria

- [ ] В detail sheet description длиннее 150 символов имеет `…`, без отдельной кнопки; нажатие на сам preview открывает полную шторку.
- [ ] Полный текст открывается в отдельной нижней шторке и прокручивается.
- [ ] Markdown форматируется в новых/сохранённых через новый editor описаниях; legacy JSON без format остаётся plain text.
- [ ] Внешние ссылки ограничены `http/https`; небезопасные схемы не открываются.
- [ ] Mentions вызываются символом `@`, фильтруются по имени и вставляют `[@label](attachment://id)` с одним пробелом после токена.
- [ ] В детальном просмотре mention выглядит как акцентированный inline attachment chip и открывает именно вложение текущего блока.
- [ ] Три действия вложений заменены одной кнопкой выбора и правой `+`.
- [ ] По умолчанию выбран «Добавить ссылку»; выбор типа не запускает picker до нажатия `+`.
- [ ] Все варианты меню имеют одинаковую ширину/высоту и доступную touch area.
- [ ] Существующие лимиты, валидация и открытие вложений продолжают работать.
- [ ] `flutter analyze` и `flutter test` проходят.

## Execution handoff

План сохранён в `docs/superpowers/plans/2026-08-01-description-markdown-mentions.md`.

Варианты выполнения:

1. **Subagent-driven (рекомендуется):** отдельный исполнитель на каждую Task 1–6 с review после каждой границы.
2. **Inline execution:** выполнить задачи последовательно в текущей сессии с targeted tests после каждой задачи.
