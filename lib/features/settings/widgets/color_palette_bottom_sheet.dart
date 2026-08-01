import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../providers/settings_provider.dart';

String colorPaletteLabel(SettingsProvider settings) {
  switch (settings.colorPalette) {
    case ColorPalette.base:
      return settings.tr('palette_base');
    case ColorPalette.ocean:
      return settings.tr('palette_ocean');
    case ColorPalette.custom:
      return settings.tr('palette_custom');
  }
}

void showColorPaletteSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBackground = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final secondaryColor =
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    builder: (sheetContext) {
      return Container(
        key: const ValueKey('palette-sheet'),
        decoration: BoxDecoration(
          color: sheetBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final hasCustom = settings.hasCustomPalette;
            return SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tr('color_palette'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    settings.tr('color_palette_hint'),
                    style: TextStyle(color: secondaryColor, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  _paletteTile(
                    sheetContext,
                    settings,
                    palette: ColorPalette.base,
                    title: settings.tr('palette_base'),
                    subtitle: settings.tr('palette_base_description'),
                    colors: AppPalette.base.customColors,
                    icon: Iconsax.paintbucket,
                    textColor: textColor,
                  ),
                  _paletteTile(
                    sheetContext,
                    settings,
                    palette: ColorPalette.ocean,
                    title: settings.tr('palette_ocean'),
                    subtitle: settings.tr('palette_ocean_description'),
                    colors: AppPalette.ocean.customColors,
                    icon: Iconsax.drop,
                    textColor: textColor,
                  ),
                  if (hasCustom) ...[
                    Divider(
                      color: textColor.withValues(alpha: 0.12),
                      height: 20,
                    ),
                    _paletteTile(
                      sheetContext,
                      settings,
                      palette: ColorPalette.custom,
                      title: settings.tr('palette_custom'),
                      subtitle: settings.tr('palette_custom_description'),
                      colors: settings.customPaletteColors,
                      icon: Iconsax.colorfilter,
                      textColor: textColor,
                    ),
                  ],
                  Divider(color: textColor.withValues(alpha: 0.12), height: 20),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      key: const ValueKey('add-custom-palette'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Iconsax.add, color: textColor, size: 24),
                      title: Text(
                        hasCustom
                            ? settings.tr('edit_custom_palette')
                            : settings.tr('add_custom_palette'),
                        style: TextStyle(color: textColor, fontSize: 16),
                      ),
                      subtitle: Text(
                        settings.tr('palette_custom_limit'),
                        style: TextStyle(color: secondaryColor, fontSize: 13),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showCustomPaletteEditor(context, settings);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

Widget _paletteTile(
  BuildContext sheetContext,
  SettingsProvider settings, {
  required ColorPalette palette,
  required String title,
  required String subtitle,
  required List<Color> colors,
  required IconData icon,
  required Color textColor,
}) {
  final selected = settings.colorPalette == palette;
  return Material(
    color: Colors.transparent,
    child: ListTile(
      key: ValueKey('palette-${palette.name}-option'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: textColor, size: 24),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 16)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ColorDots(colors: colors),
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(Icons.check, color: AppColors.primary, size: 22),
          ],
        ],
      ),
      onTap: () async {
        if (!selected) await settings.setColorPalette(palette);
        if (sheetContext.mounted) Navigator.pop(sheetContext);
      },
    ),
  );
}

class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < colors.length; index++)
          Container(
            key: ValueKey('palette-color-dot-$index'),
            width: 22,
            height: 22,
            margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
            decoration: BoxDecoration(
              color: colors[index],
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              ),
            ),
          ),
      ],
    );
  }
}

void _showCustomPaletteEditor(BuildContext context, SettingsProvider settings) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CustomPaletteEditor(settings: settings),
  );
}

class _CustomPaletteEditor extends StatefulWidget {
  const _CustomPaletteEditor({required this.settings});

  final SettingsProvider settings;

  @override
  State<_CustomPaletteEditor> createState() => _CustomPaletteEditorState();
}

class _CustomPaletteEditorState extends State<_CustomPaletteEditor> {
  late final List<({int id, TextEditingController controller})> _fields;
  var _nextFieldId = 0;
  String? _error;

  SettingsProvider get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    final initialColors =
        settings.hasCustomPalette ? settings.customPaletteColors : <Color>[];
    _fields = [
      for (final color in initialColors)
        (
          id: _nextFieldId++,
          controller: TextEditingController(
            text: '#${AppPalette.colorToHex(color)}',
          ),
        ),
    ];
    if (_fields.isEmpty) {
      _fields.add((id: _nextFieldId++, controller: TextEditingController()));
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.controller.dispose();
    }
    super.dispose();
  }

  void _addColorField() {
    if (_fields.length >= 3) return;
    setState(() {
      _error = null;
      _fields.add((id: _nextFieldId++, controller: TextEditingController()));
    });
  }

  void _removeColorField(int index) {
    if (_fields.length <= 1) return;
    final removed = _fields[index];
    setState(() {
      _error = null;
      _fields.removeAt(index);
    });
    removed.controller.dispose();
  }

  Future<void> _save() async {
    final values = <Color>[];
    final seen = <int>{};
    for (final field in _fields) {
      final value = field.controller.text.trim();
      if (value.isEmpty) continue;
      final color = AppPalette.tryParseHex(value);
      if (color == null) {
        setState(() => _error = settings.tr('palette_invalid_color'));
        return;
      }
      if (!seen.add(color.toARGB32())) {
        setState(() => _error = settings.tr('palette_duplicate_color'));
        return;
      }
      values.add(color);
    }
    if (values.isEmpty) {
      setState(() => _error = settings.tr('palette_min_colors'));
      return;
    }

    await settings.setCustomPalette(values);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBackground = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondaryColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        key: const ValueKey('custom-palette-editor'),
        decoration: BoxDecoration(
          color: sheetBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tr('custom_palette_title'),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  settings.tr('custom_palette_hint'),
                  style: TextStyle(color: secondaryColor, fontSize: 14),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < _fields.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: ValueKey(
                              'custom-color-input-${_fields[index].id}',
                            ),
                            controller: _fields[index].controller,
                            autofocus: index == 0,
                            maxLength: 7,
                            textCapitalization: TextCapitalization.characters,
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration: InputDecoration(
                              labelText:
                                  '${settings.tr('color_hex')} ${index + 1}',
                              hintText: '#24AC09',
                              counterText: '',
                              prefixIcon: const Icon(Iconsax.color_swatch),
                              suffixIcon:
                                  ValueListenableBuilder<TextEditingValue>(
                                    valueListenable: _fields[index].controller,
                                    builder: (context, value, _) {
                                      final color = AppPalette.tryParseHex(
                                        value.text,
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: CircleAvatar(
                                          radius: 10,
                                          backgroundColor:
                                              color ?? Colors.transparent,
                                        ),
                                      );
                                    },
                                  ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        if (_fields.length > 1)
                          IconButton(
                            key: ValueKey(
                              'remove-custom-color-${_fields[index].id}',
                            ),
                            tooltip: settings.tr('remove'),
                            icon: Icon(Iconsax.trash, color: secondaryColor),
                            onPressed: () => _removeColorField(index),
                          ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    if (_fields.length < 3)
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('add-custom-color'),
                          onPressed: _addColorField,
                          icon: const Icon(Iconsax.add, size: 18),
                          label: Text(settings.tr('add_color')),
                        ),
                      ),
                    if (_fields.length < 3) const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        key: const ValueKey('save-custom-palette'),
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(settings.tr('save')),
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
}
