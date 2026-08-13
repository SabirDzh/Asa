import '../features/tasks/models/task_info_block.dart';
import '../features/tasks/services/description_link_resolver.dart';

/// Callbacks used by the description renderer without coupling it to a
/// provider or a particular navigation surface.
class DescriptionRenderContext {
  final DescriptionLinkResolution Function(String target)? resolveLink;
  final void Function(DescriptionLinkResolution resolution)? onWikilinkTap;
  final void Function(String tag)? onTagTap;
  final Future<void> Function(TaskAttachment attachment)? onAttachmentEmbedTap;
  final void Function(String blockId)? onBlockTap;
  final void Function(DescriptionLinkResolution resolution, String blockId)?
  onBlockLinkTap;
  final DescriptionEmbedContent? Function(String target)? resolveEmbed;
  final DescriptionBlockResolution Function(String blockId)? resolveBlock;

  const DescriptionRenderContext({
    this.resolveLink,
    this.onWikilinkTap,
    this.onTagTap,
    this.onAttachmentEmbedTap,
    this.onBlockTap,
    this.onBlockLinkTap,
    this.resolveEmbed,
    this.resolveBlock,
  });
}
