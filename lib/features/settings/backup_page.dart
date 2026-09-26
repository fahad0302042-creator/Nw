import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/backup/backup_service.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _status;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = 'Building backup…';
    });
    try {
      final service = ref.read(backupServiceProvider);
      final file = await service.writeBackup();
      final bytes = await file.readAsBytes();

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Kurayomi backup',
        fileName: file.uri.pathSegments.last,
        bytes: bytes,
      );

      setState(() => _status = saved == null
          ? 'Export cancelled'
          : 'Saved ${_size(bytes.length)} to $saved');
    } catch (e) {
      setState(() => _status = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a Kurayomi backup',
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Reading backup…';
    });

    try {
      final f = picked.files.first;
      final content = f.bytes != null
          ? utf8.decode(f.bytes!)
          : await File(f.path!).readAsString();

      final data = (jsonDecode(content) as Map).cast<String, dynamic>();

      // Validate before touching anything, and tell the user what they are
      // about to merge in.
      final problem = BackupService.validate(data);
      if (problem != null) throw FormatException(problem);

      final count = (data['items'] as List).length;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text(
            'This backup holds $count titles, made on '
            '${data['createdAt'] ?? 'an unknown date'}.\n\n'
            'It will be merged into your current library — nothing is '
            'deleted. Extensions are not installed automatically; only their '
            'repositories are restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        setState(() => _status = 'Restore cancelled');
        return;
      }

      setState(() => _status = 'Restoring…');
      final summary = await ref.read(backupServiceProvider).restore(data);

      ref.invalidate(libraryProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(historyProvider);

      setState(() => _status = 'Restored $summary');
    } catch (e) {
      setState(() => _status = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'A backup is a single JSON file holding your library, read '
              'progress, categories and tracker links, plus the list of '
              'repositories and extensions you use.\n\n'
              'Covers and downloaded chapters are not included — they can be '
              'fetched again, and a multi-gigabyte backup is one nobody makes.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const Hairline(),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Create backup'),
            subtitle: const Text('Save a .json file anywhere on your device'),
            enabled: !_busy,
            onTap: _export,
          ),
          const Hairline(indent: 16),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from backup'),
            subtitle: const Text('Merges into your library; nothing is deleted'),
            enabled: !_busy,
            onTap: _import,
          ),
          const Hairline(),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _status!,
                style: TextStyle(
                  fontSize: 13,
                  color: _status!.contains('failed')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
