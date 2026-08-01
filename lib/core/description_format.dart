/// Storage/rendering mode for a task description block.
enum DescriptionFormat { plainText, markdown }

String descriptionFormatName(DescriptionFormat format) => format.name;

DescriptionFormat descriptionFormatFromName(Object? value) {
  return value == DescriptionFormat.markdown.name
      ? DescriptionFormat.markdown
      : DescriptionFormat.plainText;
}
