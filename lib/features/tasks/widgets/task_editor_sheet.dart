import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/description_markdown.dart';
import '../../../core/drag_close_sheet.dart';
import '../../../core/input_utils.dart';
import '../../../core/task_attachment_service.dart';
import '../../../core/task_attachment_validation.dart' as attachment_validation;
import '../../../core/theme.dart';
import '../../browser/screens/in_app_browser_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import '../screens/task_image_viewer_screen.dart';
import '../screens/task_text_viewer_screen.dart';
import '../screens/task_pdf_viewer_screen.dart';
import '../screens/task_file_viewer_screen.dart';
import '../providers/task_provider.dart';
import 'attachment_action_menu.dart';
import 'attachment_mention_overlay.dart';
import 'description_editor.dart';

/// Lets tests or platform-specific integrations provide an attachment picker
/// without making the editor depend on a platform channel.
typedef TaskAttachmentPicker =
    Future<TaskAttachment?> Function(
      TaskAttachmentType type,
      int existingAttachmentCount,
    );

class _LinkInputSheet extends StatefulWidget {
  final String title;
  final String cancelLabel;
  final String addLabel;
  final String invalidLinkLabel;

  const _LinkInputSheet({
    required this.title,
    required this.cancelLabel,
    required this.addLabel,
    required this.invalidLinkLabel,
  });

  @override
  State<_LinkInputSheet> createState() => _LinkInputSheetState();
}

class _LinkInputSheetState extends State<_LinkInputSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = attachment_validation.normalizeTaskAttachmentLink(
      sanitizeText(_controller.text),
    );
    if (url == null) {
      setState(() => _error = widget.invalidLinkLabel);
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('add-link-sheet'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('add-link-url-input'),
              controller: _controller,
              keyboardType: TextInputType.url,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'https://example.com',
                errorText: _error,
                prefixIcon: const Icon(Icons.link),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(widget.cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('add-link-confirm'),
                    onPressed: _submit,
                    child: Text(widget.addLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the task editor for a new task or an existing [task].
Future<void> showTaskEditorSheet(
  BuildContext context, {
  required String? folderId,
  TaskItem? task,
  TaskAttachmentPicker? attachmentPicker,
}) async {
  // Keep one stable editor widget instance. The route builder may rebuild
  // while the keyboard animates, but the expensive form subtree must not be
  // recreated on every inset frame.
  final editor = TaskEditorSheet(
    folderId: folderId,
    task: task,
    attachmentPicker: attachmentPicker,
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: false,
    builder:
        (ctx) => DragToCloseSheet(
          trackScrollableDrag: true,
          child: Padding(
            // Only this lightweight wrapper responds to keyboard insets.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: editor,
          ),
        ),
  );
}

class TaskEditorSheet extends StatefulWidget {
  final String? folderId;
  final TaskItem? task;
  final TaskAttachmentPicker? attachmentPicker;

  const TaskEditorSheet({
    super.key,
    required this.folderId,
    this.task,
    this.attachmentPicker,
  });

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  late final TextEditingController _titleController;
  final _labelControllers = <String, TextEditingController>{};
  final _currentControllers = <String, TextEditingController>{};
  final _targetControllers = <String, TextEditingController>{};
  final _unitControllers = <String, TextEditingController>{};
  final _descriptionControllers = <String, TextEditingController>{};
  final _descriptionFocusNodes = <String, FocusNode>{};
  final _fieldKeys = <String, Map<String, Key>>{};
  final _selectedAttachmentActions = <String, AttachmentAction>{};
  final _mentionSuggestions = <String, List<TaskAttachment>>{};
  final _mentionTriggers = <String, MentionTrigger?>{};
  late List<TaskInfoBlock> _blocks;
  String? _submitError;

  SettingsProvider get _settings => context.read<SettingsProvider>();
  bool get _isEditing => widget.task != null;
  bool get _hasDescriptionBlock =>
      _blocks.any((block) => block.type == TaskInfoBlockType.description);
  int get _quantityBlockCount =>
      _blocks.where((block) => block.type == TaskInfoBlockType.quantity).length;
  bool get _canAddQuantity =>
      _quantityBlockCount < kMaxTaskQuantityBlocksPerTask;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _blocks =
        widget.task == null
            ? <TaskInfoBlock>[]
            : normalizeTaskInfoBlocks(
              widget.task!.infoBlocks,
            ).map(_copyBlock).toList();
    for (final block in _blocks) {
      _createControllers(block);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in [
      ..._labelControllers.values,
      ..._currentControllers.values,
      ..._targetControllers.values,
      ..._unitControllers.values,
      ..._descriptionControllers.values,
    ]) {
      controller.dispose();
    }
    for (final focusNode in _descriptionFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  TaskInfoBlock _copyBlock(TaskInfoBlock block) {
    return block.copyWith(
      attachments: List<TaskAttachment>.of(block.attachments),
    );
  }

  void _createControllers(TaskInfoBlock block) {
    final blockIndex = _blocks.indexWhere(
      (candidate) => candidate.id == block.id,
    );
    final hasEarlierBlockOfSameType = _blocks
        .take(blockIndex)
        .any((candidate) => candidate.type == block.type);
    final suffix = hasEarlierBlockOfSameType ? '-${block.id}' : '';
    final fieldNames =
        block.type == TaskInfoBlockType.quantity
            ? const [
              'quantity-label-input',
              'quantity-current-input',
              'quantity-target-input',
              'quantity-unit-input',
            ]
            : const ['description-text-input'];
    _fieldKeys[block.id] = {
      for (final name in fieldNames) name: ValueKey('$name$suffix'),
    };

    if (block.type == TaskInfoBlockType.quantity) {
      _labelControllers[block.id] = TextEditingController(text: block.label);
      _currentControllers[block.id] = TextEditingController(
        text: _numberText(block.currentValue),
      );
      _targetControllers[block.id] = TextEditingController(
        text: _numberText(block.targetValue),
      );
      _unitControllers[block.id] = TextEditingController(
        text: displayQuantityUnit(block.unit, _settings.tr),
      );
    } else {
      final controller = TextEditingController(text: block.text);
      controller.addListener(() => _updateMentionSuggestions(block.id));
      _descriptionControllers[block.id] = controller;
      _descriptionFocusNodes[block.id] = FocusNode();
    }
  }

  void _updateMentionSuggestions(String blockId) {
    if (!mounted) return;
    final controller = _descriptionControllers[blockId];
    final blockIndex = _blocks.indexWhere((block) => block.id == blockId);
    if (controller == null || blockIndex == -1) return;
    final cursor = controller.selection.baseOffset;
    final trigger = findMentionTrigger(controller.text, cursor);
    final query = trigger?.query.toLowerCase() ?? '';
    final matches =
        trigger == null
            ? const <TaskAttachment>[]
            : _blocks[blockIndex].attachments
                .where(
                  (attachment) => attachment.name.toLowerCase().contains(query),
                )
                .toList();
    final previous = _mentionSuggestions[blockId] ?? const <TaskAttachment>[];
    final unchanged =
        _mentionTriggers[blockId] == trigger &&
        previous.length == matches.length &&
        previous.asMap().entries.every(
          (entry) => entry.value.id == matches[entry.key].id,
        );
    if (unchanged) return;
    setState(() {
      _mentionTriggers[blockId] = trigger;
      _mentionSuggestions[blockId] = matches;
    });
  }

  void _selectMention(String blockId, TaskAttachment attachment) {
    final controller = _descriptionControllers[blockId];
    final trigger = _mentionTriggers[blockId];
    if (controller == null || trigger == null) return;
    controller.value = replaceMentionTrigger(
      controller.value,
      trigger,
      attachment,
    );
    setState(() {
      _mentionTriggers.remove(blockId);
      _mentionSuggestions.remove(blockId);
    });
    final focusNode = _descriptionFocusNodes[blockId];
    if (focusNode != null) {
      FocusScope.of(context).requestFocus(focusNode);
    }
  }

  String _numberText(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  void _disposeControllers(String id, TaskInfoBlockType type) {
    _mentionSuggestions.remove(id);
    _mentionTriggers.remove(id);
    _selectedAttachmentActions.remove(id);
    if (type == TaskInfoBlockType.quantity) {
      for (final map in <Map<String, TextEditingController>>[
        _labelControllers,
        _currentControllers,
        _targetControllers,
        _unitControllers,
      ]) {
        map.remove(id)?.dispose();
      }
    } else {
      _descriptionControllers.remove(id)?.dispose();
    }
    _descriptionFocusNodes.remove(id)?.dispose();
  }

  Future<void> _showBlockChooser() async {
    if (!_canAddQuantity && _hasDescriptionBlock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_settings.tr('quantity_block_limit'))),
      );
      return;
    }
    // Do not animate the keyboard and the chooser route against each other.
    // The editor remains mounted while the nested sheet is open, but its
    // focused field should release focus before the route transition starts.
    FocusManager.instance.primaryFocus?.unfocus();
    final selectedType = await showModalBottomSheet<TaskInfoBlockType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final sheetColor = isDark ? AppColors.sheetDark : AppColors.sheetLight;
        final textColor = isDark ? AppColors.textDark : AppColors.textLight;
        return Container(
          key: const ValueKey('task-block-chooser-sheet'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: sheetColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_canAddQuantity)
                  _chooserTile(
                    ctx,
                    key: const ValueKey('add-quantity-block'),
                    icon: Iconsax.chart_2,
                    label: _settings.tr('quantity_block'),
                    color: textColor,
                    onTap: () {
                      Navigator.pop(ctx, TaskInfoBlockType.quantity);
                    },
                  ),
                if (!_hasDescriptionBlock)
                  _chooserTile(
                    ctx,
                    key: const ValueKey('add-description-block'),
                    icon: Iconsax.document_text,
                    label: _settings.tr('description_block'),
                    color: textColor,
                    onTap: () {
                      Navigator.pop(ctx, TaskInfoBlockType.description);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedType != null && mounted) {
      _addBlock(selectedType);
    }
  }

  Widget _chooserTile(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    // ListTile paints its ink splash on the nearest Material ancestor. The
    // chooser sheet wraps its content in a ColoredBox (Container color), so the
    // ListTile must own a Material above that colored box or the splash and
    // pressed highlight would be invisible.
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: key,
        minTileHeight: 56,
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: onTap,
      ),
    );
  }

  void _addBlock(TaskInfoBlockType type) {
    if (type == TaskInfoBlockType.description && _hasDescriptionBlock) {
      return;
    }
    if (type == TaskInfoBlockType.quantity && !_canAddQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_settings.tr('quantity_block_limit'))),
      );
      return;
    }
    final id = _uuid.v4();
    final block =
        type == TaskInfoBlockType.quantity
            ? TaskInfoBlock.quantity(
              id: id,
              targetValue: 1,
              unit: kQuantityUnitTimes,
            )
            : TaskInfoBlock.description(id: id);
    setState(() {
      _blocks.add(block);
      _createControllers(block);
      _submitError = null;
    });
  }

  void _removeBlock(TaskInfoBlock block) {
    setState(() {
      _blocks.removeWhere((candidate) => candidate.id == block.id);
      _disposeControllers(block.id, block.type);
      _submitError = null;
    });
  }

  Future<void> _addLink(TaskInfoBlock block) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: _LinkInputSheet(
              title: _settings.tr('add_link'),
              cancelLabel: _settings.tr('cancel'),
              addLabel: _settings.tr('add'),
              invalidLinkLabel: _settings.tr('invalid_link'),
            ),
          ),
    );
    if (value == null || !mounted) return;
    if (_attachmentCount >= kMaxTaskAttachmentsPerTask) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_settings.tr('attachment_limit'))));
      return;
    }

    final uri = Uri.parse(value);
    final attachment = TaskAttachment(
      id: _uuid.v4(),
      type: TaskAttachmentType.link,
      name: uri.host,
      value: value,
    );
    setState(() {
      _replaceBlock(
        block.copyWith(attachments: [...block.attachments, attachment]),
      );
    });
  }

  Future<void> _addPickedAttachment(
    TaskInfoBlock block,
    TaskAttachmentType type,
  ) async {
    if (_attachmentCount >= kMaxTaskAttachmentsPerTask) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_settings.tr('attachment_limit'))));
      return;
    }

    final picker = widget.attachmentPicker ?? _defaultAttachmentPicker;
    final attachment = await picker(type, _attachmentCount);
    if (!mounted) return;
    if (attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_settings.tr('attachment_unavailable'))),
      );
      return;
    }
    if (_attachmentCount >= kMaxTaskAttachmentsPerTask) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_settings.tr('attachment_limit'))));
      return;
    }
    setState(() {
      _replaceBlock(
        block.copyWith(attachments: [...block.attachments, attachment]),
      );
    });
  }

  Future<TaskAttachment?> _defaultAttachmentPicker(
    TaskAttachmentType type,
    int existingAttachmentCount,
  ) async {
    try {
      if (type == TaskAttachmentType.image) {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        );
        if (image == null || await image.length() > kMaxTaskAttachmentBytes) {
          return null;
        }
        final bytes = await image.readAsBytes();
        return storeTaskAttachment(
          type: type,
          name: image.name,
          bytes: bytes,
          mimeType: 'image/*',
          existingAttachmentCount: existingAttachmentCount,
        );
      }
      // Keep large files on disk while selecting. Only the bounded file
      // contents are read after the picker has reported its size.
      final result = await FilePicker.platform.pickFiles(
        withData: false,
        withReadStream: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.size <= 0 || file.size > kMaxTaskAttachmentBytes) return null;
      final bytes = await _readPickedFileBytes(file);
      if (bytes == null) return null;
      return storeTaskAttachment(
        type: type,
        name: file.name,
        bytes: bytes,
        mimeType: attachment_validation.taskAttachmentMimeForName(file.name),
        existingAttachmentCount: existingAttachmentCount,
      );
    } on Object {
      return null;
    }
  }

  Future<List<int>?> _readPickedFileBytes(PlatformFile file) async {
    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      var totalLength = 0;
      final iterator = StreamIterator<List<int>>(stream);
      try {
        while (await iterator.moveNext()) {
          final chunk = iterator.current;
          totalLength += chunk.length;
          if (totalLength > kMaxTaskAttachmentBytes) return null;
          builder.add(chunk);
        }
      } finally {
        // Explicitly cancel the picker stream on both success and early size
        // rejection so a platform file descriptor is not left open.
        await iterator.cancel();
      }
      if (totalLength == 0) return null;
      return builder.takeBytes();
    }
    final bytes = file.bytes;
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > kMaxTaskAttachmentBytes) {
      return null;
    }
    return bytes;
  }

  int get _attachmentCount =>
      _blocks.fold(0, (total, block) => total + block.attachments.length);

  void _replaceBlock(TaskInfoBlock replacement) {
    final index = _blocks.indexWhere((block) => block.id == replacement.id);
    if (index != -1) {
      _blocks[index] = replacement;
    }
  }

  Future<void> _openAttachment(TaskAttachment attachment) async {
    final opened =
        attachment.type == TaskAttachmentType.link
            ? await openTaskLink(
              context,
              attachment.value,
              title: attachment.name,
            )
            : attachment.type == TaskAttachmentType.image
            ? await openTaskImageViewer(context, attachment)
            : isTaskTextAttachment(attachment)
            ? await openTaskTextViewer(context, attachment)
            : isTaskPdfAttachment(attachment)
            ? await openTaskPdfViewer(context, attachment)
            : await openTaskFileFallback(context, attachment);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_settings.tr('attachment_unavailable'))),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final blocks = <TaskInfoBlock>[];
    try {
      for (final block in _blocks) {
        if (block.type == TaskInfoBlockType.quantity) {
          final current = double.tryParse(_currentControllers[block.id]!.text);
          final target = double.tryParse(_targetControllers[block.id]!.text);
          if (current == null ||
              target == null ||
              current > target ||
              !current.isFinite ||
              !target.isFinite) {
            throw FormatException(_settings.tr('invalid_quantity'));
          }
          blocks.add(
            TaskInfoBlock.quantity(
              id: block.id,
              label: sanitizeText(_labelControllers[block.id]!.text),
              currentValue: current,
              targetValue: target,
              unit: sanitizeText(_unitControllers[block.id]!.text),
            ),
          );
        } else {
          blocks.add(
            TaskInfoBlock.description(
              id: block.id,
              text: sanitizeText(_descriptionControllers[block.id]!.text),
              format: DescriptionFormat.markdown,
              attachments: block.attachments,
            ),
          );
        }
      }

      final title = sanitizeText(_titleController.text);
      final provider = context.read<TaskProvider>();
      if (_isEditing) {
        provider.updateTask(widget.task!.id, title, infoBlocks: blocks);
      } else {
        provider.addTask(title, folderId: widget.folderId, infoBlocks: blocks);
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _settings.tr('required_field');
    }
    return null;
  }

  String? _quantity(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return _settings.tr('invalid_quantity');
    }
    if (parsed > kMaxTaskInfoValue) return _settings.tr('invalid_quantity');
    return null;
  }

  String? _target(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null ||
        !parsed.isFinite ||
        parsed <= 0 ||
        parsed > kMaxTaskInfoValue) {
      return _settings.tr('invalid_quantity');
    }
    return null;
  }

  String? _title(String? value) {
    if (sanitizeText(value ?? '').isEmpty) {
      return _settings.tr('required_field');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondaryColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: secondaryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _settings.tr(_isEditing ? 'edit_task' : 'create_task'),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('task-title-input'),
                  controller: _titleController,
                  autofocus: true,
                  maxLength: kMaxTextInputLength,
                  inputFormatters: [textInputFormatter()],
                  validator: _title,
                  decoration: InputDecoration(
                    hintText: _settings.tr('new_task'),
                    filled: true,
                    fillColor:
                        isDark
                            ? AppColors.surfaceSecondaryDark
                            : AppColors.surfaceSecondaryLight,
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('add-task-information'),
                  onPressed: _showBlockChooser,
                  icon: const Icon(Icons.add),
                  label: Text(_settings.tr('add_information')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    alignment: Alignment.centerLeft,
                  ),
                ),
                if (!_canAddQuantity)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _settings.tr('quantity_block_limit'),
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  ),
                if (_blocks.isNotEmpty) const SizedBox(height: 12),
                for (final block in _blocks) _buildBlock(block, textColor),
                if (_submitError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _submitError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        key: const ValueKey('cancel-task-editor'),
                        onPressed: () => Navigator.pop(context),
                        child: Text(_settings.tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('save-task-editor'),
                        onPressed: _submit,
                        child: Text(_settings.tr('save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(TaskInfoBlock block, Color textColor) {
    final isQuantity = block.type == TaskInfoBlockType.quantity;
    return Card(
      key: ValueKey('info-block-${block.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isQuantity ? Iconsax.chart_2 : Iconsax.document_text,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _settings.tr(
                      isQuantity ? 'quantity_block' : 'description_block',
                    ),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-info-block-${block.id}'),
                  tooltip: _settings.tr('remove'),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => _removeBlock(block),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (isQuantity) ...[
              TextFormField(
                key: _fieldKey('quantity-label-input', block.id),
                controller: _labelControllers[block.id],
                decoration: InputDecoration(
                  labelText: _settings.tr('quantity_label'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: _fieldKey('quantity-current-input', block.id),
                      controller: _currentControllers[block.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [numericInputFormatter()],
                      validator: _quantity,
                      decoration: InputDecoration(
                        labelText: _settings.tr('quantity_current'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: _fieldKey('quantity-target-input', block.id),
                      controller: _targetControllers[block.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [numericInputFormatter()],
                      validator: _target,
                      decoration: InputDecoration(
                        labelText: _settings.tr('quantity_target'),
                      ),
                    ),
                  ),
                ],
              ),
              TextFormField(
                key: _fieldKey('quantity-unit-input', block.id),
                controller: _unitControllers[block.id],
                maxLength: 24,
                validator: _required,
                decoration: InputDecoration(
                  labelText: _settings.tr('quantity_unit'),
                  helperText: _settings.tr('quantity_unit_hint'),
                  counterText: '',
                ),
              ),
            ] else ...[
              if (_mentionSuggestions[block.id]?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                AttachmentMentionSuggestions(
                  attachments: _mentionSuggestions[block.id]!,
                  typeLinkLabel: _settings.tr('attachment_type_link'),
                  typeImageLabel: _settings.tr('attachment_type_image'),
                  typeFileLabel: _settings.tr('attachment_type_file'),
                  onSelected:
                      (attachment) => _selectMention(block.id, attachment),
                ),
              ],
              DescriptionEditor(
                fieldKey: _fieldKey('description-text-input', block.id),
                controller: _descriptionControllers[block.id]!,
                focusNode: _descriptionFocusNodes[block.id],
                attachments: block.attachments,
                maxLength: kMaxTaskDescriptionLength,
                onChanged: (_) => _updateMentionSuggestions(block.id),
                labelText: _settings.tr('description_text'),
              ),
              const SizedBox(height: 8),
              AttachmentActionMenu(
                selectedAction:
                    _selectedAttachmentActions[block.id] ??
                    AttachmentAction.link,
                linkLabel: _settings.tr('add_link'),
                imageLabel: _settings.tr('add_image'),
                fileLabel: _settings.tr('add_file'),
                addLabel: _settings.tr('add'),
                onActionChanged: (action) {
                  setState(() => _selectedAttachmentActions[block.id] = action);
                },
                onAdd: () {
                  final action =
                      _selectedAttachmentActions[block.id] ??
                      AttachmentAction.link;
                  if (action == AttachmentAction.link) {
                    _addLink(block);
                  } else if (action == AttachmentAction.image) {
                    _addPickedAttachment(block, TaskAttachmentType.image);
                  } else {
                    _addPickedAttachment(block, TaskAttachmentType.file);
                  }
                },
              ),
              if (block.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final attachment in block.attachments)
                      InputChip(
                        key: ValueKey('attachment-chip-${attachment.id}'),
                        label: Text(attachment.name),
                        onPressed: () => _openAttachment(attachment),
                        onDeleted: () {
                          setState(() {
                            _replaceBlock(
                              block.copyWith(
                                attachments:
                                    block.attachments
                                        .where(
                                          (item) => item.id != attachment.id,
                                        )
                                        .toList(),
                              ),
                            );
                          });
                        },
                        deleteButtonTooltipMessage: _settings.tr(
                          'remove_attachment',
                        ),
                        avatar: Icon(
                          attachment.type == TaskAttachmentType.link
                              ? Icons.link
                              : Icons.attach_file,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Key _fieldKey(String base, String blockId) {
    return _fieldKeys[blockId]![base]!;
  }
}
