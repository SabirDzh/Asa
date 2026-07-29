import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/sync_service.dart';
import '../../../core/theme.dart';
import '../providers/settings_provider.dart';
import '../../tasks/providers/task_provider.dart';

void showSyncBottomSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final taskProvider = Provider.of<TaskProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SyncBottomSheet(
      settings: settings,
      taskProvider: taskProvider,
      sheetBg: sheetBg,
      textColor: textColor,
      textSecondary: textSecondary,
    ),
  );
}

class _SyncBottomSheet extends StatefulWidget {
  final SettingsProvider settings;
  final TaskProvider taskProvider;
  final Color sheetBg;
  final Color textColor;
  final Color textSecondary;

  const _SyncBottomSheet({
    required this.settings,
    required this.taskProvider,
    required this.sheetBg,
    required this.textColor,
    required this.textSecondary,
  });

  @override
  State<_SyncBottomSheet> createState() => _SyncBottomSheetState();
}

class _SyncBottomSheetState extends State<_SyncBottomSheet> {
  List<SyncPeer> _peers = [];
  StreamSubscription<List<SyncPeer>>? _peerSub;
  final _nameController = TextEditingController();
  final _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.settings.syncDeviceName;
    _secretController.text = widget.settings.syncSecret ?? '';
    _peerSub = SyncService.instance.peers.listen((peers) {
      if (mounted) setState(() => _peers = peers);
    });
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _nameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.settings.tr('sync'),
              style: TextStyle(color: widget.textColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              style: TextStyle(color: widget.textColor),
              decoration: InputDecoration(
                labelText: widget.settings.tr('sync_device_name'),
                labelStyle: TextStyle(color: widget.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (value) => _updateDeviceName(value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              style: TextStyle(color: widget.textColor),
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'PIN / Shared secret',
                labelStyle: TextStyle(color: widget.textSecondary),
                hintText: 'Leave empty for open network',
                hintStyle: TextStyle(color: widget.textSecondary.withValues(alpha: 0.6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (value) => _updateSecret(value),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.settings.tr('sync_peers'),
                  style: TextStyle(color: widget.textColor, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Iconsax.refresh, size: 18),
                  label: Text(widget.settings.tr('refresh')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _peers.isEmpty
                ? Text(
                    widget.settings.tr('no_peers'),
                    style: TextStyle(color: widget.textSecondary),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _peers.length,
                    itemBuilder: (_, index) {
                      final peer = _peers[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(peer.name, style: TextStyle(color: widget.textColor)),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text('${peer.host}:${peer.port}', style: TextStyle(color: widget.textSecondary)),
                        ),
                        trailing: IconButton(
                          icon: Icon(Iconsax.send_2, color: widget.textSecondary),
                          onPressed: () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final ok = await SyncService.instance.sendToPeer(widget.taskProvider, peer);
                            if (!mounted) return;
                            scaffoldMessenger.showSnackBar(
                              SnackBar(content: Text(ok ? 'Sent to ${peer.name}' : 'Send failed')),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateDeviceName(String value) async {
    await widget.settings.setSyncDeviceName(value);
    SyncService.instance.setDeviceName(widget.settings.syncDeviceName);
  }

  Future<void> _updateSecret(String value) async {
    await widget.settings.setSyncSecret(value);
    SyncService.instance.setSecret(widget.settings.syncSecret);
  }

  Future<void> _refresh() async {
    await SyncService.instance.stop();
    await SyncService.instance.start();
  }
}
