import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';

import '../../app/app.dart';
import '../../domain/entities/local_file_item.dart';
import '../../domain/entities/mesh_node_role.dart';
import '../providers/app_providers.dart';

class FilePickerArguments {
  const FilePickerArguments.single(this.peerAddress) : sendToAllNearby = false;

  const FilePickerArguments.allNearby()
    : peerAddress = null,
      sendToAllNearby = true;

  final String? peerAddress;
  final bool sendToAllNearby;
}

class FilePickerScreen extends ConsumerStatefulWidget {
  const FilePickerScreen({required this.arguments, super.key});

  final FilePickerArguments arguments;

  @override
  ConsumerState<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends ConsumerState<FilePickerScreen> {
  final List<LocalFileItem> _selectedFiles = <LocalFileItem>[];
  bool _submitting = false;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) {
      return;
    }

    final files = <LocalFileItem>[];
    for (final item in result.files) {
      final path = item.path;
      if (path == null) {
        continue;
      }
      final file = File(path);
      if (!await file.exists()) {
        continue;
      }
      files.add(
        LocalFileItem(
          path: path,
          name: item.name,
          size: item.size,
          mimeType: lookupMimeType(path),
        ),
      );
    }

    setState(() {
      _selectedFiles
        ..clear()
        ..addAll(files);
    });
  }

  Future<void> _queueTransfer() async {
    final bluetooth = ref.read(bluetoothControllerProvider);
    final peerAddress = widget.arguments.peerAddress;
    final peer =
        peerAddress == null ? null : bluetooth.peerByAddress(peerAddress);
    final targetPeers =
        bluetooth.peers
            .where((item) => item.isTransferCandidate && item.isConnected)
            .toList();

    if (_selectedFiles.isEmpty) {
      return;
    }

    if (widget.arguments.sendToAllNearby) {
      if (bluetooth.meshRole != MeshNodeRole.master) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Switch this device to MASTER mode first.'),
          ),
        );
        return;
      }
      if (targetPeers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connect at least one BlueShare phone with the same mesh passkey before sending files.',
            ),
          ),
        );
        return;
      }
    } else if (peer == null || !peer.isTransferCandidate || !peer.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect this phone first. BlueShare sends only to connected phones with the same mesh passkey.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (widget.arguments.sendToAllNearby ||
          bluetooth.meshRole == MeshNodeRole.master) {
        if (targetPeers.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'MASTER mode requires at least one connected phone with the same mesh passkey before distribution starts.',
                ),
              ),
            );
          }
          setState(() => _submitting = false);
          return;
        }
        await ref
            .read(transferControllerProvider)
            .queueMeshFiles(peers: targetPeers, files: _selectedFiles);
      } else {
        await ref
            .read(transferControllerProvider)
            .queueFiles(peer: peer!, files: _selectedFiles);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    Navigator.pushReplacementNamed(context, AppRoutes.transfers);
  }

  @override
  Widget build(BuildContext context) {
    final bluetooth = ref.watch(bluetoothControllerProvider);
    final peerAddress = widget.arguments.peerAddress;
    final peer =
        peerAddress == null ? null : bluetooth.peerByAddress(peerAddress);
    final targetPeers =
        bluetooth.peers
            .where((item) => item.isTransferCandidate && item.isConnected)
            .toList();
    final allNearbyMode = widget.arguments.sendToAllNearby;
    final canSend =
        _selectedFiles.isNotEmpty &&
        !_submitting &&
        (allNearbyMode
            ? bluetooth.meshRole == MeshNodeRole.master &&
                targetPeers.isNotEmpty
            : peer?.isTransferCandidate == true && peer?.isConnected == true);

    return Scaffold(
      appBar: AppBar(
        title: Text(allNearbyMode ? 'Send to connected phones' : 'Select files'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    allNearbyMode
                        ? 'All connected phones'
                        : (peer?.displayName ??
                            peerAddress ??
                            'Unknown device'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    allNearbyMode
                        ? 'This shortcut starts the same file transfer only on '
                            'connected BlueShare phones that share the mesh passkey.'
                        : bluetooth.meshRole == MeshNodeRole.master
                            ? 'MASTER mode queues every selected file only for connected '
                                'phones using the same mesh passkey.'
                            : 'CLIENT mode sends only to the selected connected peer, '
                                'with relay metadata preserved for the mesh.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    allNearbyMode
                        ? bluetooth.meshRole == MeshNodeRole.master
                            ? '${targetPeers.length} connected phones ready right now.'
                            : 'Switch to MASTER mode to start a secure distribution.'
                        : peer?.isTransferCandidate == true &&
                                peer?.isConnected == true
                            ? bluetooth.meshRole == MeshNodeRole.master
                                ? '${targetPeers.length} connected phones ready right now.'
                                : peer?.isBonded == true
                                    ? 'This connected device is paired and ready for secure transfer.'
                                    : 'This connected device can receive if BlueShare is active there and the same mesh passkey is configured.'
                            : 'Connect this phone first. BlueShare sends only to connected phones with the same mesh passkey.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Choose files'),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child:
                _selectedFiles.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No files selected yet.'),
                    )
                    : Column(
                      children:
                          _selectedFiles
                              .map(
                                (file) => ListTile(
                                  leading: const Icon(
                                    Icons.insert_drive_file_rounded,
                                  ),
                                  title: Text(file.name),
                                  subtitle: Text(
                                    '${(file.size / 1024).toStringAsFixed(1)} KB - ${file.mimeType ?? 'Unknown type'}',
                                  ),
                                ),
                              )
                              .toList(),
                    ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: FilledButton.icon(
          onPressed: canSend ? _queueTransfer : null,
          icon:
              _submitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.send_rounded),
          label: Text(
            allNearbyMode || bluetooth.meshRole == MeshNodeRole.master
                ? 'Start secure mesh distribution'
                : 'Queue transfer',
          ),
        ),
      ),
    );
  }
}
