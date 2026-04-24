import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../controllers/bluetooth_controller.dart';
import '../providers/app_providers.dart';
import 'file_picker_screen.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({required this.peerAddress, super.key});

  final String peerAddress;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    final peer = ref
        .read(bluetoothControllerProvider)
        .peerByAddress(widget.peerAddress);
    _nicknameController = TextEditingController(text: peer?.nickname ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetooth = ref.watch(bluetoothControllerProvider);
    final peer = bluetooth.peerByAddress(widget.peerAddress);

    if (peer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device details')),
        body: const Center(child: Text('Device not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(peer.displayName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Transfer queue',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.transfers),
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.min(constraints.maxWidth, 1160.0);
          final compact = contentWidth < 860;

          final detailsCard = _DetailsCard(
            controller: _nicknameController,
            peerAddress: widget.peerAddress,
          );
          final actionsCard = _ActionsCard(peerAddress: widget.peerAddress, peer: peer);

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: ListView(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 24),
                children: <Widget>[
                  _HeroCard(peer: peer, bluetooth: bluetooth),
                  const SizedBox(height: 16),
                  if (compact) ...<Widget>[
                    detailsCard,
                    const SizedBox(height: 16),
                    actionsCard,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: detailsCard),
                        const SizedBox(width: 16),
                        Expanded(child: actionsCard),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.peer, required this.bluetooth});

  final dynamic peer;
  final BluetoothController bluetooth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;

            final identity = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        peer.isConnected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Icon(
                      peer.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(peer.displayName, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        peer.address,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          Chip(label: Text(peer.isBonded ? 'Paired' : 'Open')),
                          Chip(
                            label: Text(
                              peer.isConnected ? 'Connected' : 'Disconnected',
                            ),
                          ),
                          Chip(label: Text(peer.signalLabel)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            final summary = _InsetBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Mesh state', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 14),
                  _DetailRow(
                    label: 'Active links',
                    value: '${bluetooth.connectedPeerCount}',
                  ),
                  _DetailRow(
                    label: 'Transfer ready',
                    value: peer.isConnected ? 'Yes' : 'Connect first',
                  ),
                  _DetailRow(
                    label: 'Peer type',
                    value: peer.isPhone ? 'Phone' : 'Device',
                    compact: true,
                  ),
                ],
              ),
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  identity,
                  const SizedBox(height: 16),
                  summary,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 7, child: identity),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({
    required this.controller,
    required this.peerAddress,
  });

  final TextEditingController controller;
  final String peerAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Device info', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('Saved nickname'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Kitchen tablet, office phone, etc.',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed:
                  () => ref
                      .read(bluetoothControllerProvider)
                      .saveNickname(peerAddress, controller.text),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save nickname'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsCard extends ConsumerWidget {
  const _ActionsCard({required this.peerAddress, required this.peer});

  final String peerAddress;
  final dynamic peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Actions', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                      () => ref.read(bluetoothControllerProvider).connect(peerAddress),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Connect'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      () => ref
                          .read(bluetoothControllerProvider)
                          .disconnect(peerAddress),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      peer.isBonded
                          ? () => ref
                              .read(bluetoothControllerProvider)
                              .unpairDevice(peerAddress)
                          : () => ref
                              .read(bluetoothControllerProvider)
                              .pairDevice(peerAddress),
                  icon: Icon(
                    peer.isBonded
                        ? Icons.heart_broken_rounded
                        : Icons.verified_rounded,
                  ),
                  label: Text(peer.isBonded ? 'Unpair' : 'Pair'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      peer.isConnected
                          ? () => Navigator.pushNamed(
                            context,
                            AppRoutes.files,
                            arguments: FilePickerArguments.single(peerAddress),
                          )
                          : null,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: const Text('Select files'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsetBox extends StatelessWidget {
  const _InsetBox({required this.child});

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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
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
