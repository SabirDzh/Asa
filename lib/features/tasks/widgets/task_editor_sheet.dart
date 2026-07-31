import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/input_utils.dart';
import '../../../core/task_attachment_service.dart';
import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';

/// Lets tests or platform-specific integrations provide an attachment picker
/// without making the editor depend on a platform channel.
typedef TaskAttachmentPicker =
    Future<TaskAttachment?> Function(
      TaskAttachmentType type,
      int existingAttachmentCount,
    );

/// Opens the task editor for a new task or an existing [task].
Future<void> showTaskEditorSheet(
  BuildContext context, {
  required String? folderId,
  TaskItem? task,
  TaskAttachmentPicker? attachmentPicker,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => TaskEditorSheet(
          folderId: folderId,
          task: task,
          attachmentPicker: attachmentPicker,
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
  final _fieldKeys = <String, Map<String, Key>>{};
  late List<TaskInfoBlock> _blocks;
  String? _submitError;

  SettingsProvider get _settings => context.read<SettingsProvider>();
  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _blocks =
        widget.task == null
            ? <TaskInfoBlock>[]
            : widget.task!.infoBlocks.map(_copyBlock).toList();
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
      _unitControllers[block.id] = TextEditingController(text: block.unit);
    } else {
      _descriptionControllers[block.id] = TextEditingController(
        text: block.text,
      );
    }
  }

  String _numberText(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  void _disposeControllers(String id, TaskInfoBlockType type) {
    final maps =
        type == TaskInfoBlockType.quantity
            ? <Map<String, TextEditingController>>[
              _labelControllers,
              _currentControllers,
              _targetControllers,
              _unitControllers,
            ]
            : <Map<String, TextEditingController>>[_descriptionControllers];
    for (final map in maps) {
      map.remove(id)?.dispose();
    }
  }

  Future<void> _showBlockChooser() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final sheetColor = isDark ? AppColors.sheetDark : AppColors.sheetLight;
        final textColor = isDark ? AppColors.textDark : AppColors.textLight;
        return Container(
          color: sheetColor,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _chooserTile(
                  ctx,
                  key: const ValueKey('add-quantity-block'),
                  icon: Iconsax.chart_2,
                  label: _settings.tr('quantity_block'),
                  color: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _addBlock(TaskInfoBlockType.quantity);
                  },
                ),
                _chooserTile(
                  ctx,
                  key: const ValueKey('add-description-block'),
                  icon: Iconsax.document_text,
                  label: _settings.tr('description_block'),
                  color: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _addBlock(TaskInfoBlockType.description);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chooserTile(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: key,
      minTileHeight: 56,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }

  void _addBlock(TaskInfoBlockType type) {
    final id = _uuid.v4();
    final block =
        type == TaskInfoBlockType.quantity
            ? TaskInfoBlock.quantity(id: id, targetValue: 1, unit: 'unit')
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
    final urlController = TextEditingController();
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text(_settings.tr('add_link')),
                  content: TextField(
                    key: const ValueKey('add-link-url-input'),
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'https://example.com',
                      errorText: error,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(_settings.tr('cancel')),
                    ),
                    FilledButton(
                      key: const ValueKey('add-link-confirm'),
                      onPressed: () {
                        final url = sanitizeText(urlController.text);
                        if (!isAllowedTaskLink(url)) {
                          setDialogState(
                            () => error = _settings.tr('invalid_link'),
                          );
                          return;
                        }
                        Navigator.pop(ctx, url);
                      },
                      child: Text(_settings.tr('add')),
                    ),
                  ],
                ),
          ),
    );
    urlController.dispose();
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
      name: uri.host.isEmpty ? value : uri.host,
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
        );
        if (image == null) return null;
        if (await image.length() > kMaxTaskAttachmentBytes) return null;
        final bytes = await image.readAsBytes();
        return storeTaskAttachment(
          type: type,
          name: image.name,
          bytes: bytes,
          mimeType: 'image/*',
          existingAttachmentCount: existingAttachmentCount,
        );
      }
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      if (file.size > kMaxTaskAttachmentBytes) return null;
      final bytes = file.bytes;
      if (bytes == null) return null;
      return storeTaskAttachment(
        type: type,
        name: file.name,
        bytes: bytes,
        existingAttachmentCount: existingAttachmentCount,
      );
    } on Object {
      return null;
    }
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
    final opened = await openTaskAttachment(attachment);
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

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
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
                        borderRadius: BorderRadius.circular(
                          AppTheme.pillRadius,
                        ),
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
                validator: _required,
                decoration: InputDecoration(
                  labelText: _settings.tr('quantity_unit'),
                ),
              ),
            ] else ...[
              TextFormField(
                key: _fieldKey('description-text-input', block.id),
                controller: _descriptionControllers[block.id],
                maxLength: kMaxTaskDescriptionLength,
                maxLines: 5,
                minLines: 3,
                inputFormatters: [
                  textInputFormatter(maxLength: kMaxTaskDescriptionLength),
                ],
                decoration: InputDecoration(
                  labelText: _settings.tr('description_text'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _attachmentButton(
                    key: const ValueKey('add-description-link'),
                    icon: Icons.link,
                    label: _settings.tr('add_link'),
                    onPressed: () => _addLink(block),
                  ),
                  _attachmentButton(
                    key: const ValueKey('add-description-image'),
                    icon: Icons.image_outlined,
                    label: _settings.tr('add_image'),
                    onPressed:
                        () => _addPickedAttachment(
                          block,
                          TaskAttachmentType.image,
                        ),
                  ),
                  _attachmentButton(
                    key: const ValueKey('add-description-file'),
                    icon: Icons.attach_file,
                    label: _settings.tr('add_file'),
                    onPressed:
                        () => _addPickedAttachment(
                          block,
                          TaskAttachmentType.file,
                        ),
                  ),
                ],
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

  Widget _attachmentButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
