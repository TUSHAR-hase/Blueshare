import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../domain/entities/bluetooth_peer.dart';
import '../../domain/entities/mesh_node_role.dart';
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_job.dart';
import '../../domain/entities/transfer_status.dart';
import '../providers/app_providers.dart';
import 'file_picker_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bluetooth = ref.watch(bluetoothControllerProvider);
    final transfer = ref.watch(transferControllerProvider);
    final themeController = ref.watch(themeControllerProvider);
    final levels = _buildLevelSummaries(transfer.jobs);
    final peers = bluetooth.peers as List<BluetoothPeer>;
    final activeJobs = transfer.jobs.where(_isLiveStatus).length;
    final connectedPeers = peers.where((peer) => peer.isConnected).length;
    final pairedPeers = peers.where((peer) => peer.isBonded).length;
    final completedJobs =
        transfer.jobs.where((job) => job.status == TransferStatus.completed).length;
    final failedJobs =
        transfer.jobs
            .where(
              (job) =>
                  job.status == TransferStatus.failed ||
                  job.status == TransferStatus.cancelled,
            )
            .length;
    final deepestLevel =
        levels.isEmpty ? 0 : levels.map((e) => e.level).reduce(_maxInt);
    final sendEnabled =
        bluetooth.meshRole == MeshNodeRole.master &&
        peers.any((peer) => peer.isTransferCandidate && peer.isConnected);
    final scanToggle =
        bluetooth.isScanning
            ? ref.read(bluetoothControllerProvider).stopScan
            : ref.read(bluetoothControllerProvider).startScan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BlueShare'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Mesh settings',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.meshSettings),
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.transfers),
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'History',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.history),
            icon: const Icon(Icons.history_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: themeController.toggle,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.min(constraints.maxWidth, 1320.0);
            final compact = contentWidth < 760;
            final wide = contentWidth >= 1120;
            final listHeight = wide ? 660.0 : (compact ? 540.0 : 600.0);
            final horizontalPadding = compact ? 16.0 : 24.0;

            final sidePanel = _SidePanel(
              bluetooth: bluetooth,
              activeJobs: activeJobs,
              completedJobs: completedJobs,
              failedJobs: failedJobs,
              totalJobs: transfer.jobs.length,
              levels: levels,
            );

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: contentWidth,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12,
                    horizontalPadding,
                    24,
                  ),
                  children: <Widget>[
                    _HeaderCard(
                      bluetooth: bluetooth,
                      connectedPeers: connectedPeers,
                      sendEnabled: sendEnabled,
                      onScanToggle: scanToggle,
                      onTransfers:
                          () => Navigator.pushNamed(context, AppRoutes.transfers),
                      onDiscoverable:
                          ref.read(bluetoothControllerProvider).makeDiscoverable,
                      onSend:
                          () => Navigator.pushNamed(
                            context,
                            AppRoutes.files,
                            arguments: const FilePickerArguments.allNearby(),
                          ),
                    ),
                    const SizedBox(height: 16),
                    _MetricsSection(
                      items: <_MetricCard>[
                        _MetricCard(
                          title: 'Nearby',
                          value: '${peers.length}',
                          caption: '$pairedPeers paired devices',
                          icon: Icons.devices_rounded,
                        ),
                        _MetricCard(
                          title: 'Connected',
                          value: '$connectedPeers',
                          caption: 'Live Bluetooth links',
                          icon: Icons.link_rounded,
                        ),
                        _MetricCard(
                          title: 'Active',
                          value: '$activeJobs',
                          caption: '${transfer.jobs.length} total transfer jobs',
                          icon: Icons.sync_rounded,
                        ),
                        _MetricCard(
                          title: 'Depth',
                          value: 'L$deepestLevel',
                          caption: '${levels.length} mesh levels tracked',
                          icon: Icons.account_tree_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (wide)
                      SizedBox(
                        height: listHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 7,
                              child: _DeviceListCard(
                                peers: peers,
                                scanRunning: bluetooth.isScanning,
                                onScanToggle: scanToggle,
                                onTap:
                                    (peer) => Navigator.pushNamed(
                                      context,
                                      AppRoutes.device,
                                      arguments: peer.address,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(width: 360, child: sidePanel),
                          ],
                        ),
                      )
                    else ...<Widget>[
                      sidePanel,
                      const SizedBox(height: 16),
                      SizedBox(
                        height: listHeight,
                        child: _DeviceListCard(
                          peers: peers,
                          scanRunning: bluetooth.isScanning,
                          onScanToggle: scanToggle,
                          onTap:
                              (peer) => Navigator.pushNamed(
                                context,
                                AppRoutes.device,
                                arguments: peer.address,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.bluetooth,
    required this.connectedPeers,
    required this.sendEnabled,
    required this.onScanToggle,
    required this.onTransfers,
    required this.onDiscoverable,
    required this.onSend,
  });

  final dynamic bluetooth;
  final int connectedPeers;
  final bool sendEnabled;
  final VoidCallback onScanToggle;
  final VoidCallback onTransfers;
  final VoidCallback onDiscoverable;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;

            final primary = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _Badge(
                      icon:
                          bluetooth.meshRole == MeshNodeRole.master
                              ? Icons.flag_rounded
                              : Icons.share_rounded,
                      label:
                          bluetooth.meshRole == MeshNodeRole.master
                              ? 'Master node'
                              : 'Client node',
                    ),
                    _Badge(
                      icon:
                          bluetooth.isBluetoothEnabled
                              ? Icons.bluetooth_connected_rounded
                              : Icons.bluetooth_disabled_rounded,
                      label:
                          bluetooth.isBluetoothEnabled
                              ? 'Bluetooth on'
                              : 'Bluetooth off',
                    ),
                    _Badge(
                      icon:
                          bluetooth.isServerRunning
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                      label:
                          bluetooth.isServerRunning
                              ? 'Receiver ready'
                              : 'Receiver off',
                    ),
                    _Badge(
                      icon:
                          bluetooth.isScanning
                              ? Icons.radar_rounded
                              : Icons.pause_circle_outline_rounded,
                      label: bluetooth.isScanning ? 'Scanning' : 'Idle',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  bluetooth.localDeviceName,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Fast, simple mesh file sharing with a cleaner control surface.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onScanToggle,
                      icon: Icon(
                        bluetooth.isScanning
                            ? Icons.stop_circle_outlined
                            : Icons.radar_rounded,
                      ),
                      label: Text(
                        bluetooth.isScanning ? 'Stop scan' : 'Scan devices',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: sendEnabled ? onSend : null,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send files'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onTransfers,
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Transfers'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDiscoverable,
                      icon: const Icon(Icons.wifi_tethering_rounded),
                      label: const Text('Discoverable'),
                    ),
                  ],
                ),
                if (bluetooth.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      bluetooth.errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            );

            final summary = _InsetPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Session', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 14),
                  _InfoRow(
                    label: 'Role',
                    value:
                        bluetooth.meshRole == MeshNodeRole.master
                            ? 'Master'
                            : 'Client',
                  ),
                  _InfoRow(label: 'Connected', value: '$connectedPeers'),
                  _InfoRow(
                    label: 'Status',
                    value: bluetooth.isScanning ? 'Scanning' : 'Ready',
                  ),
                  _InfoRow(
                    label: 'Transfer',
                    value: sendEnabled ? 'Ready to send' : 'Needs connected phone',
                    compact: true,
                  ),
                ],
              ),
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  primary,
                  const SizedBox(height: 16),
                  summary,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 7, child: primary),
                const SizedBox(width: 18),
                Expanded(flex: 3, child: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.bluetooth,
    required this.activeJobs,
    required this.completedJobs,
    required this.failedJobs,
    required this.totalJobs,
    required this.levels,
  });

  final dynamic bluetooth;
  final int activeJobs;
  final int completedJobs;
  final int failedJobs;
  final int totalJobs;
  final List<_LevelSummary> levels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Overview', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _InsetPanel(
                child: Column(
                  children: <Widget>[
                    _InfoRow(label: 'Active', value: '$activeJobs'),
                    _InfoRow(label: 'Completed', value: '$completedJobs'),
                    _InfoRow(label: 'Failed', value: '$failedJobs'),
                    _InfoRow(label: 'Tracked', value: '$totalJobs', compact: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Mesh levels', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (levels.isEmpty)
                const _InsetPanel(child: Text('No live transfer right now'))
              else
                ...levels.map(
                  (level) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InsetPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Level ${level.level}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${level.nodeCount} nodes',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value:
                                  level.nodeCount == 0
                                      ? 0
                                      : level.completedCount / level.nodeCount,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              Chip(
                                label: Text(
                                  '${level.completedCount} completed',
                                ),
                              ),
                              if (level.activeCount > 0)
                                Chip(label: Text('${level.activeCount} active')),
                              if (level.failedCount > 0)
                                Chip(label: Text('${level.failedCount} failed')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const Divider(height: 28),
              Text('Mode', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<MeshNodeRole>(
                segments: const <ButtonSegment<MeshNodeRole>>[
                  ButtonSegment<MeshNodeRole>(
                    value: MeshNodeRole.master,
                    label: Text('Master'),
                    icon: Icon(Icons.flag_rounded),
                  ),
                  ButtonSegment<MeshNodeRole>(
                    value: MeshNodeRole.client,
                    label: Text('Client'),
                    icon: Icon(Icons.share_rounded),
                  ),
                ],
                selected: <MeshNodeRole>{bluetooth.meshRole},
                onSelectionChanged:
                    (selection) => ref
                        .read(bluetoothControllerProvider)
                        .setMeshRole(selection.first),
              ),
              const SizedBox(height: 16),
              _InfoRow(
                label: 'Receiver',
                value: bluetooth.isServerRunning ? 'Ready' : 'Stopped',
              ),
              _InfoRow(
                label: 'Bluetooth',
                value: bluetooth.isBluetoothEnabled ? 'On' : 'Off',
              ),
              _InfoRow(
                label: 'Last check',
                value: _timeAgo(bluetooth.lastBluetoothCheckAt as DateTime?),
              ),
              _InfoRow(
                label: 'Peer update',
                value: _timeAgo(bluetooth.lastPeerUpdateAt as DateTime?),
              ),
              _InfoRow(
                label: 'Scan finish',
                value: _timeAgo(bluetooth.lastScanFinishedAt as DateTime?),
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({
    required this.peers,
    required this.scanRunning,
    required this.onScanToggle,
    required this.onTap,
  });

  final List<BluetoothPeer> peers;
  final bool scanRunning;
  final VoidCallback onScanToggle;
  final ValueChanged<BluetoothPeer> onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;

                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Nearby devices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${peers.length} visible now',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );

                final actions = Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    Chip(
                      label: Text(
                        '${peers.where((peer) => peer.isConnected).length} connected',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onScanToggle,
                      icon: Icon(
                        scanRunning
                            ? Icons.stop_circle_outlined
                            : Icons.radar_rounded,
                      ),
                      label: Text(scanRunning ? 'Stop scan' : 'Scan'),
                    ),
                  ],
                );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      title,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    Expanded(child: title),
                    actions,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: peers.isEmpty
                ? _EmptyPanel(
                    label:
                        scanRunning ? 'Scanning in progress' : 'No devices found',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: peers.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final peer = peers[index];
                            return _DeviceTile(peer: peer, onTap: onTap);
                          },
                        );
                      }

                      final columns = constraints.maxWidth >= 1120 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.4,
                        ),
                        itemCount: peers.length,
                        itemBuilder: (context, index) {
                          final peer = peers[index];
                          return _DeviceGridTile(peer: peer, onTap: onTap);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsSection extends StatelessWidget {
  const _MetricsSection({required this.items});

  final List<_MetricCard> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 4 : (width >= 720 ? 2 : 1);
        const spacing = 12.0;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              items
                  .map((item) => SizedBox(width: itemWidth, child: item))
                  .toList(growable: false),
        );
      },
    );
  }
}

class _InsetPanel extends StatelessWidget {
  const _InsetPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.devices_rounded,
                  size: 28,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.peer, required this.onTap});

  final BluetoothPeer peer;
  final ValueChanged<BluetoothPeer> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onTap(peer),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            _PeerAvatar(peer: peer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    peer.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peer.signalLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Chip(label: Text(_peerState(peer)), visualDensity: VisualDensity.compact),
                const SizedBox(height: 8),
                Text(
                  _timeAgo(peer.lastSeen),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceGridTile extends StatelessWidget {
  const _DeviceGridTile({required this.peer, required this.onTap});

  final BluetoothPeer peer;
  final ValueChanged<BluetoothPeer> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onTap(peer),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _PeerAvatar(peer: peer),
                const Spacer(),
                Chip(label: Text(_peerState(peer)), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              peer.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              peer.signalLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              'Seen ${_timeAgo(peer.lastSeen)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.peer});

  final BluetoothPeer peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            peer.isConnected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          peer.isConnected
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_rounded,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _LevelSummary {
  const _LevelSummary({
    required this.level,
    required this.nodeCount,
    required this.completedCount,
    required this.activeCount,
    required this.failedCount,
  });

  final int level;
  final int nodeCount;
  final int completedCount;
  final int activeCount;
  final int failedCount;
}

List<_LevelSummary> _buildLevelSummaries(List<TransferJob> jobs) {
  final grouped = <int, Map<String, List<TransferJob>>>{};
  for (final job in jobs) {
    if (job.direction != TransferDirection.outgoing) {
      continue;
    }
    grouped
        .putIfAbsent(job.hopCount, () => <String, List<TransferJob>>{})
        .putIfAbsent(job.remoteAddress, () => <TransferJob>[])
        .add(job);
  }

  return grouped.entries.map((entry) {
      var completedCount = 0;
      var activeCount = 0;
      var failedCount = 0;
      for (final jobsForNode in entry.value.values) {
        final lead = [...jobsForNode]..sort(
          (left, right) => _statusRank(left.status) - _statusRank(right.status),
        );
        final status = lead.first.status;
        if (status == TransferStatus.completed) {
          completedCount += 1;
        } else if (status == TransferStatus.failed ||
            status == TransferStatus.cancelled) {
          failedCount += 1;
        } else {
          activeCount += 1;
        }
      }
      return _LevelSummary(
        level: entry.key,
        nodeCount: entry.value.length,
        completedCount: completedCount,
        activeCount: activeCount,
        failedCount: failedCount,
      );
    }).toList()
    ..sort((left, right) => left.level.compareTo(right.level));
}

bool _isLiveStatus(TransferJob job) {
  return job.status != TransferStatus.completed &&
      job.status != TransferStatus.failed &&
      job.status != TransferStatus.cancelled;
}

String _peerState(BluetoothPeer peer) {
  if (peer.isConnected) {
    return 'Live';
  }
  if (peer.isBonded) {
    return 'Paired';
  }
  return 'Open';
}

int _statusRank(TransferStatus status) {
  switch (status) {
    case TransferStatus.failed:
    case TransferStatus.cancelled:
      return 0;
    case TransferStatus.sending:
    case TransferStatus.receiving:
      return 1;
    case TransferStatus.preparing:
    case TransferStatus.connecting:
    case TransferStatus.awaitingAcceptance:
    case TransferStatus.waitingForPeer:
    case TransferStatus.paused:
      return 2;
    case TransferStatus.completed:
      return 3;
    case TransferStatus.queued:
      return 4;
  }
}

int _maxInt(int left, int right) => left > right ? left : right;

String _timeAgo(DateTime? value) {
  if (value == null) {
    return 'Not yet';
  }
  final elapsed = DateTime.now().difference(value);
  if (elapsed.inSeconds < 5) {
    return 'Now';
  }
  if (elapsed.inSeconds < 60) {
    return '${elapsed.inSeconds}s ago';
  }
  if (elapsed.inMinutes < 60) {
    return '${elapsed.inMinutes}m ago';
  }
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours}h ago';
  }
  return '${elapsed.inDays}d ago';
}
