/// Built-in SVG icon assets available for folders.
const List<String> folderIconAssets = [
  'assets/icons/study.svg',
  'assets/icons/shopping.svg',
  'assets/icons/work.svg',
  'assets/icons/home.svg',
  'assets/icons/health.svg',
  'assets/icons/travel.svg',
  'assets/icons/sport.svg',
];

/// Maps each built-in folder icon asset to a localized label.
///
/// [tr] is a translation function (e.g. `settings.tr`) that accepts a key.
Map<String, String> folderIconLabels(String Function(String) tr) {
  return {
    for (final asset in folderIconAssets)
      asset: tr('icon_${asset.split('/').last.replaceAll('.svg', '')}'),
  };
}
