import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/download/download_storage.dart';
import '../../domain/models/download.dart';
import '../../domain/models/media.dart';
import '../common/widgets.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});
  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  int? _bytesOnDisk;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final storage = await DownloadStorage.instance();
    final total = await storage.totalBytes();
    if (mounted) setState(() => _bytesOnDisk = total);
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(downloadManagerProvider);
    final tasks = manager.tasks;
    final active = manager.activeCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (active > 0)
            IconButton(
              tooltip: manager.isPaused ? 'Resume all' : 'Pause all',
              icon: Icon(manager.isPaused ? Icons.play_arrow : Icons.pause),
              onPressed: () => manager.isPaused
                  ? manager.resumeAll()
                  : manager.pauseAll(),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear') {
                await manager.clearFinished();
              } else if (v == 'delete') {
                final ok = await _confirm(
                  'Delete all downloads?',
                  'Every downloaded chapter and episode will be removed from '
                      'this device. This cannot be undone.',
                );
                if (ok) {
                  await manager.deleteEverything();
                  await _measure();
                }
              }
              await _measure();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear finished')),
              PopupMenuItem(value: 'delete', child: Text('Delete all downloads')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _StorageBar(bytes: _bytesOnDisk, active: active),
          const Hairline(),
          Expanded(
            child: tasks.isEmpty
                ? const EmptyState(
                    icon: Icons.download_outlined,
                    title: 'Nothing downloaded',
                    message:
                        'Open a title and tap the download icon on a chapter '
                        'or episode to save it for offline.',
                  )
                : RefreshIndicator(
                    onRefresh: _measure,
                    child: ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const Hairline(indent: 16),
                      itemBuilder: (_, i) => _TaskTile(
                        task: tasks[i],
                        onChanged: _measure,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.bytes, required this.active});
  final int? bytes;
  final int active;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.sd_storage_outlined, size: 18, color: muted),
          const SizedBox(width: 8),
          Text(
            bytes == null
                ? 'Measuring…'
                : '${DownloadStorage.formatBytes(bytes!)} on device',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const Spacer(),
          if (active > 0)
            Text('$active in queue',
                style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.onChanged});
  final DownloadTask task;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color color) = switch (task.status) {
      DownloadStatus.completed => (Icons.check_circle, scheme.primary),
      DownloadStatus.failed => (Icons.error_outline, scheme.error),
      DownloadStatus.downloading => (Icons.downloading, scheme.primary),
      DownloadStatus.paused => (Icons.pause_circle_outline, scheme.outline),
      DownloadStatus.cancelled => (Icons.cancel_outlined, scheme.outline),
      DownloadStatus.queued => (Icons.schedule, scheme.outline),
    };

    final subtitle = switch (task.status) {
      DownloadStatus.failed => task.error ?? 'Failed',
      DownloadStatus.completed =>
        '${task.itemTitle} · ${DownloadStorage.formatBytes(task.bytes)}',
      DownloadStatus.downloading => task.type == MediaType.manga
          ? '${task.itemTitle} · page ${task.completedParts}/${task.totalParts}'
          : '${task.itemTitle} · ${DownloadStorage.formatBytes(task.bytes)}',
      _ => task.itemTitle,
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(task.unitName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: task.status == DownloadStatus.failed
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (task.status == DownloadStatus.downloading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 3,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
      isThreeLine: task.status == DownloadStatus.downloading,
      trailing: switch (task.status) {
        DownloadStatus.failed => IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry',
            onPressed: () => manager.retry(task),
          ),
        DownloadStatus.completed => IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete from device',
            onPressed: () async {
              await manager.deleteDownloaded(task);
              onChanged();
            },
          ),
        _ => IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => manager.cancel(task),
          ),
      },
    );
  }
}
