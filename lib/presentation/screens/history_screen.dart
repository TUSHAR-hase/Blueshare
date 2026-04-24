import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_history_entry.dart';
import '../../domain/entities/transfer_status.dart';
import '../providers/app_providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(transferControllerProvider).history;
    final formatter = DateFormat('MMM d, HH:mm');
    final outgoing =
        history.where((entry) => entry.direction == TransferDirection.outgoing).length;
    final incoming = history.length - outgoing;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer History')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.min(constraints.maxWidth, 1180.0);
          final compact = contentWidth < 760;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: ListView(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 24),
                children: <Widget>[
                  _HistoryHeader(
                    total: history.length,
                    outgoing: outgoing,
                    incoming: incoming,
                  ),
                  const SizedBox(height: 16),
                  if (history.isEmpty)
                    const _EmptyHistory()
                  else
                    _HistoryList(history: history, formatter: formatter),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.total,
    required this.outgoing,
    required this.incoming,
  });

  final int total;
  final int outgoing;
  final int incoming;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final summary = Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _HistoryStat(label: 'Transfers', value: '$total'),
                _HistoryStat(label: 'Sent', value: '$outgoing'),
                _HistoryStat(label: 'Received', value: '$incoming'),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Recent activity', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Completed and past transfer sessions in one clean view.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  summary,
                ],
              );
            }

            return Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Recent activity',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Completed and past transfer sessions in one clean view.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(child: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryStat extends StatelessWidget {
  const _HistoryStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.formatter,
  });

  final List<TransferHistoryEntry> history;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView.separated(
            itemCount: history.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _HistoryCard(entry: history[index], formatter: formatter);
            },
          );
        }

        return GridView.builder(
          itemCount: history.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.15,
          ),
          itemBuilder: (context, index) {
            return _HistoryCard(entry: history[index], formatter: formatter);
          },
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.formatter,
  });

  final TransferHistoryEntry entry;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context, entry.status);
    final isOutgoing = entry.direction == TransferDirection.outgoing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      isOutgoing
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.remoteName ?? entry.remoteAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(entry.status.name),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(isOutgoing ? 'Sent' : 'Received')),
                Chip(label: Text(_sizeText(entry.bytesTransferred))),
                if (entry.isRelay) Chip(label: Text('Relay L${entry.hopCount}')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatter.format(entry.startedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  Icons.history_rounded,
                  size: 30,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No transfer history yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Completed transfers will appear here.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, TransferStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case TransferStatus.completed:
      return Colors.green.shade700;
    case TransferStatus.failed:
    case TransferStatus.cancelled:
      return scheme.error;
    case TransferStatus.waitingForPeer:
    case TransferStatus.paused:
      return Colors.orange.shade700;
    case TransferStatus.sending:
    case TransferStatus.receiving:
      return scheme.primary;
    case TransferStatus.queued:
    case TransferStatus.preparing:
    case TransferStatus.awaitingAcceptance:
    case TransferStatus.connecting:
      return Colors.blueGrey.shade700;
  }
}

String _sizeText(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
