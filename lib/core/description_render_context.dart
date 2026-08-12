import '../features/tasks/models/task_info_block.dart';
import '../features/tasks/services/description_link_resolver.dart';

/// Callbacks used by the description renderer without coupling it to a
/// provider or a particular navigation surface.
class DescriptionRenderContext {
  final DescriptionLinkResolution Function(String target)? resolveLink;
  final void Function(DescriptionLinkResolution resolution)? onWikilinkTap;
  final void Function(String tag)? onTagTap;
  final Future<void> Function(TaskAttachment attachment)? onAttachmentEmbedTap;

  const DescriptionRenderContext({
    this.resolveLink,
    this.onWikilinkTap,
    this.onTagTap,
    this.onAttachmentEmbedTap,
  });
}
