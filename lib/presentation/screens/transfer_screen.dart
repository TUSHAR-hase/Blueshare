import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app.dart';
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_job.dart';
import '../../domain/entities/transfer_status.dart';
import '../providers/app_providers.dart';

class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _exporting = false;

  Future<void> _exportLog() async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final path =
          await ref.read(transferControllerProvider).exportTransferLog();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Transfer log exported to $path')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(transferControllerProvider);
    final jobs = controller.jobs;
    final transferJobs =
        jobs.where((job) => !job.isRemoteTelemetry).toList(growable: false);
    final allBatches = _buildBatches(transferJobs);
    final visibleBatches = _applySearch(allBatches, _query);
    final visibleJobs = visibleBatches
        .expand((batch) => batch.jobs)
        .toList(growable: false);
    final visibleTransferIds = visibleBatches
        .map((batch) => batch.transferId)
        .toSet();
    final visibleTopologyJobs =
        jobs
            .where((job) => visibleTransferIds.contains(job.transferId))
            .toList(growable: false);
    final summary = _TransferSummary.fromJobs(visibleJobs, visibleBatches);
    final topology = _buildTopology(visibleTopologyJobs);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mesh Transfer Dashboard'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Mesh settings',
              onPressed:
                  () => Navigator.pushNamed(context, AppRoutes.meshSettings),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'Export log',
              onPressed: jobs.isEmpty || _exporting ? null : _exportLog,
              icon:
                  _exporting
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.download_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'All'),
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
              Tab(text: 'Failed'),
            ],
          ),
        ),
        body:
            jobs.isEmpty
                ? _EmptyState(
                  onSettings:
                      () =>
                          Navigator.pushNamed(context, AppRoutes.meshSettings),
                )
                : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText:
                              'Search by file, device, origin, address, or detail',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon:
                              _query.isEmpty
                                  ? null
                                  : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: <Widget>[
                          _DashboardView(
                            summary: summary,
                            topology: topology,
                            batches: visibleBatches,
                            query: _query,
                            emptyLabel: 'No mesh deliveries match this search.',
                          ),
                          _DashboardView(
                            summary: summary,
                            topology: topology,
                            batches: _filterBatches(visibleBatches, _isActive),
                            query: _query,
                            emptyLabel:
                                'No active transfers match this search.',
                          ),
                          _DashboardView(
                            summary: summary,
                            topology: topology,
                            batches: _filterBatches(
                              visibleBatches,
                              (job) => job.status == TransferStatus.completed,
                            ),
                            query: _query,
                            emptyLabel:
                                'No completed deliveries match this search.',
                          ),
                          _DashboardView(
                            summary: summary,
                            topology: topology,
                            batches: _filterBatches(
                              visibleBatches,
                              (job) => job.status == TransferStatus.failed,
                            ),
                            query: _query,
                            emptyLabel:
                                'No failed deliveries match this search.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Mesh dashboard is ready.',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Start a secure transfer from the MASTER node to monitor authorization, relay propagation, and device status here.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: onSettings,
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Mesh Settings'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            () => Navigator.pushNamed(context, AppRoutes.home),
                        icon: const Icon(Icons.hub_rounded),
                        label: const Text('Back To Devices'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.summary,
    required this.topology,
    required this.batches,
    required this.query,
    required this.emptyLabel,
  });

  final _TransferSummary summary;
  final _Topology topology;
  final List<_TransferBatch> batches;
  final String query;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _MetricCard(
              title: 'Active',
              value: '${summary.activeJobs}',
              subtitle: 'Device deliveries in progress',
              icon: Icons.sync_rounded,
            ),
            _MetricCard(
              title: 'Completed',
              value: '${summary.completedJobs}',
              subtitle: 'Successful device deliveries',
              icon: Icons.check_circle_rounded,
            ),
            _MetricCard(
              title: 'Failed',
              value: '${summary.failedJobs}',
              subtitle: 'Device deliveries needing attention',
              icon: Icons.error_rounded,
            ),
            _MetricCard(
              title: 'Transfers',
              value: '${summary.batchCount}',
              subtitle: 'Unique file distributions',
              icon: Icons.folder_copy_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _MetricCard(
              title: 'Coverage',
              value: '${summary.uniqueDevices} devices',
              subtitle: 'Visible in this dashboard view',
              icon: Icons.hub_rounded,
            ),
            _MetricCard(
              title: 'Deepest Level',
              value: 'L${summary.maxLevel}',
              subtitle: 'Highest relay depth reached',
              icon: Icons.stacked_line_chart_rounded,
            ),
            _MetricCard(
              title: 'Relay Jobs',
              value: '${summary.relayJobs}',
              subtitle: 'Forwarded deliveries in mesh',
              icon: Icons.share_rounded,
            ),
            _MetricCard(
              title: 'Success Rate',
              value: '${summary.successRate.toStringAsFixed(0)}%',
              subtitle: 'Completed vs terminal deliveries',
              icon: Icons.insights_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TopologyCard(topology: topology),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Text(
              query.isEmpty
                  ? '${batches.length} transfer groups'
                  : '${batches.length} transfer groups for "$query"',
              style: theme.textTheme.titleMedium,
            ),
            const Spacer(),
            Chip(label: Text(query.isEmpty ? 'Live view' : 'Filtered view')),
          ],
        ),
        const SizedBox(height: 12),
        if (batches.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(emptyLabel),
            ),
          )
        else
          ...batches.map(
            (batch) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _TransferBatchCard(batch: batch),
            ),
          ),
      ],
    );
  }
}

class _TopologyCard extends StatelessWidget {
  const _TopologyCard({required this.topology});

  final _Topology topology;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                Text('Network Topology', style: theme.textTheme.titleLarge),
                Chip(label: Text('${topology.totalNodes} devices')),
                Chip(label: Text('${topology.levels.length} levels')),
                Chip(label: Text('${topology.activeNodes} active now')),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Live mesh view grouped by hop level so the MASTER can watch propagation across the area.',
            ),
            const SizedBox(height: 16),
            if (topology.levels.isEmpty)
              const Text('No device nodes available yet.')
            else
              ...topology.levels.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Level ${entry.key}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children:
                            entry.value
                                .map((node) => _TopologyNodeCard(node: node))
                                .toList(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopologyNodeCard extends StatelessWidget {
  const _TopologyNodeCard({required this.node});

  final _TopologyNode node;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, node.status);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.28)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                node.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(
                    label: Text(node.status.name),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: color.withOpacity(0.12),
                    side: BorderSide.none,
                  ),
                  if (node.isRelay)
                    const Chip(
                      label: Text('Relay'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (node.isTelemetry)
                    const Chip(
                      label: Text('Reported'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: node.progress),
              const SizedBox(height: 6),
              Text(
                '${(node.progress * 100).toStringAsFixed(0)}%  ${_sizeText(node.bytesTransferred)} / ${_sizeText(node.totalBytes)}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferBatchCard extends ConsumerWidget {
  const _TransferBatchCard({required this.batch});

  final _TransferBatch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outgoing =
        batch.jobs
            .where((job) => job.direction == TransferDirection.outgoing)
            .length;
    final incoming =
        batch.jobs
            .where((job) => job.direction == TransferDirection.incoming)
            .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(batch.fileName, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Transfer ${batch.transferId.substring(0, 8)}  |  ${_sizeText(batch.totalBytes)}',
                      ),
                    ],
                  ),
                ),
                _chip('$outgoing outgoing'),
                if (incoming > 0) _chip('$incoming incoming'),
                _chip('${batch.completed} complete'),
                if (batch.failed > 0) _chip('${batch.failed} failed'),
                if (batch.active > 0) _chip('${batch.active} active'),
                _chip('Delivered to ${batch.forwardedToCount}'),
                _chip('Max level L${batch.maxLevel}'),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 1120),
                child: DataTable(
                  columnSpacing: 20,
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Device')),
                    DataColumn(label: Text('Dir')),
                    DataColumn(label: Text('Level')),
                    DataColumn(label: Text('Progress')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Speed')),
                    DataColumn(label: Text('Updated')),
                    DataColumn(label: Text('Detail')),
                    DataColumn(label: Text('Action')),
                  ],
                  rows:
                      batch.jobs.map((job) => _row(context, ref, job)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) =>
      Chip(label: Text(label), visualDensity: VisualDensity.compact);

  DataRow _row(BuildContext context, WidgetRef ref, TransferJob job) {
    final updatedAt = job.updatedAt ?? job.startedAt;
    final updatedLabel =
        updatedAt == null ? '-' : DateFormat.Hm().format(updatedAt);
    final color = _statusColor(context, job.status);

    return DataRow(
      cells: <DataCell>[
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  job.remoteName ?? job.remoteAddress,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  job.remoteAddress,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Text(job.direction == TransferDirection.outgoing ? 'OUT' : 'IN'),
        ),
        DataCell(Text('L${job.hopCount}')),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 170),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(value: job.progress.clamp(0, 1)),
                const SizedBox(height: 6),
                Text(
                  '${(job.progress * 100).toStringAsFixed(0)}%  ${_sizeText(job.bytesTransferred)} / ${_sizeText(job.totalBytes)}',
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Chip(
            label: Text(job.status.name),
            backgroundColor: color.withOpacity(0.12),
            side: BorderSide.none,
            labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
        DataCell(
          Text(
            job.speedBytesPerSecond <= 0
                ? '-'
                : '${(job.speedBytesPerSecond / 1024).toStringAsFixed(1)} KB/s',
          ),
        ),
        DataCell(Text(updatedLabel)),
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              _detail(job),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ),
        DataCell(_ActionCell(job: job)),
      ],
    );
  }

  String _detail(TransferJob job) {
    if (job.errorMessage != null && job.errorMessage!.trim().isNotEmpty) {
      return job.errorMessage!;
    }
    final parts = <String>[];
    if (job.isRelay) {
      parts.add('Relay');
    }
    if (job.isRemoteTelemetry) {
      parts.add('Reported upstream');
    }
    if (job.originNode != null && job.originNode!.trim().isNotEmpty) {
      parts.add('Origin ${job.originNode}');
    }
    if (job.sourceName != null || job.sourceAddress != null) {
      parts.add('From ${job.sourceName ?? job.sourceAddress}');
    }
    if (job.statusDetail != null && job.statusDetail!.trim().isNotEmpty) {
      parts.add(job.statusDetail!);
    }
    if (job.totalChunks > 0) {
      parts.add('Chunk ${job.currentChunk}/${job.totalChunks}');
    }
    return parts.isEmpty ? '-' : parts.join(' - ');
  }
}

class _ActionCell extends ConsumerWidget {
  const _ActionCell({required this.job});

  final TransferJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (job.isRemoteTelemetry) {
      return const Text('Live');
    }
    if (job.status == TransferStatus.completed ||
        job.status == TransferStatus.cancelled ||
        job.status == TransferStatus.failed) {
      return const Text('-');
    }
    if (job.status == TransferStatus.paused ||
        job.status == TransferStatus.waitingForPeer) {
      return TextButton(
        onPressed: () => ref.read(transferControllerProvider).resume(job.id),
        child: const Text('Retry'),
      );
    }
    if (job.status == TransferStatus.sending ||
        job.status == TransferStatus.receiving) {
      return TextButton(
        onPressed: () => ref.read(transferControllerProvider).pause(job.id),
        child: const Text('Pause'),
      );
    }
    return TextButton(
      onPressed: () => ref.read(transferControllerProvider).cancel(job.id),
      child: const Text('Stop'),
    );
  }
}

class _TransferBatch {
  const _TransferBatch({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.jobs,
    required this.completed,
    required this.failed,
    required this.active,
    required this.forwardedToCount,
    required this.maxLevel,
  });

  final String transferId;
  final String fileName;
  final int totalBytes;
  final List<TransferJob> jobs;
  final int completed;
  final int failed;
  final int active;
  final int forwardedToCount;
  final int maxLevel;
}

class _TransferSummary {
  const _TransferSummary({
    required this.activeJobs,
    required this.completedJobs,
    required this.failedJobs,
    required this.uniqueDevices,
    required this.batchCount,
    required this.maxLevel,
    required this.relayJobs,
    required this.successRate,
  });

  final int activeJobs;
  final int completedJobs;
  final int failedJobs;
  final int uniqueDevices;
  final int batchCount;
  final int maxLevel;
  final int relayJobs;
  final double successRate;

  factory _TransferSummary.fromJobs(
    List<TransferJob> jobs,
    List<_TransferBatch> batches,
  ) {
    final completed =
        jobs.where((job) => job.status == TransferStatus.completed).length;
    final failed =
        jobs.where((job) => job.status == TransferStatus.failed).length;
    final terminal = completed + failed;
    return _TransferSummary(
      activeJobs: jobs.where(_isActive).length,
      completedJobs: completed,
      failedJobs: failed,
      uniqueDevices: jobs.map((job) => job.remoteAddress).toSet().length,
      batchCount: batches.length,
      maxLevel:
          jobs.isEmpty
              ? 0
              : jobs.map((job) => job.hopCount).reduce((a, b) => a > b ? a : b),
      relayJobs: jobs.where((job) => job.isRelay).length,
      successRate: terminal == 0 ? 0 : (completed / terminal) * 100,
    );
  }
}

class _Topology {
  const _Topology({
    required this.levels,
    required this.totalNodes,
    required this.activeNodes,
  });

  final Map<int, List<_TopologyNode>> levels;
  final int totalNodes;
  final int activeNodes;
}

class _TopologyNode {
  const _TopologyNode({
    required this.address,
    required this.name,
    required this.status,
    required this.progress,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.isRelay,
    required this.isTelemetry,
  });

  final String address;
  final String name;
  final TransferStatus status;
  final double progress;
  final int bytesTransferred;
  final int totalBytes;
  final bool isRelay;
  final bool isTelemetry;
}

List<_TransferBatch> _buildBatches(List<TransferJob> jobs) {
  final grouped = <String, List<TransferJob>>{};
  for (final job in jobs) {
    grouped.putIfAbsent(job.transferId, () => <TransferJob>[]).add(job);
  }
  return grouped.entries.map((entry) {
      final sorted = [...entry.value]..sort((a, b) {
        final hop = a.hopCount.compareTo(b.hopCount);
        if (hop != 0) {
          return hop;
        }
        return (a.remoteName ?? a.remoteAddress).compareTo(
          b.remoteName ?? b.remoteAddress,
        );
      });
      return _TransferBatch(
        transferId: entry.key,
        fileName: sorted.first.fileName,
        totalBytes: sorted
            .map((job) => job.totalBytes)
            .fold<int>(0, (best, value) => value > best ? value : best),
        jobs: sorted,
        completed:
            sorted
                .where((job) => job.status == TransferStatus.completed)
                .length,
        failed:
            sorted.where((job) => job.status == TransferStatus.failed).length,
        active: sorted.where(_isActive).length,
        forwardedToCount: sorted.fold<int>(
          0,
          (best, job) =>
              job.forwardedToCount > best ? job.forwardedToCount : best,
        ),
        maxLevel: sorted
            .map((job) => job.hopCount)
            .reduce((a, b) => a > b ? a : b),
      );
    }).toList()
    ..sort((a, b) {
      final left = a.jobs.first.startedAt ?? DateTime(1970);
      final right = b.jobs.first.startedAt ?? DateTime(1970);
      return right.compareTo(left);
    });
}

List<_TransferBatch> _filterBatches(
  List<_TransferBatch> batches,
  bool Function(TransferJob job) test,
) {
  final result = <_TransferBatch>[];
  for (final batch in batches) {
    final jobs = batch.jobs.where(test).toList();
    if (jobs.isEmpty) {
      continue;
    }
    result.add(
      _TransferBatch(
        transferId: batch.transferId,
        fileName: batch.fileName,
        totalBytes: batch.totalBytes,
        jobs: jobs,
        completed:
            jobs.where((job) => job.status == TransferStatus.completed).length,
        failed: jobs.where((job) => job.status == TransferStatus.failed).length,
        active: jobs.where(_isActive).length,
        forwardedToCount: jobs.fold<int>(
          0,
          (best, job) =>
              job.forwardedToCount > best ? job.forwardedToCount : best,
        ),
        maxLevel: jobs
            .map((job) => job.hopCount)
            .reduce((a, b) => a > b ? a : b),
      ),
    );
  }
  return result;
}

List<_TransferBatch> _applySearch(List<_TransferBatch> batches, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return batches;
  }
  return batches.where((batch) {
    if (batch.fileName.toLowerCase().contains(needle) ||
        batch.transferId.toLowerCase().contains(needle)) {
      return true;
    }
    return batch.jobs.any((job) {
      final fields = <String?>[
        job.remoteName,
        job.remoteAddress,
        job.originNode,
        job.sourceName,
        job.sourceAddress,
        job.statusDetail,
        job.errorMessage,
        job.status.name,
      ];
      return fields.any(
        (value) => value != null && value.toLowerCase().contains(needle),
      );
    });
  }).toList();
}

_Topology _buildTopology(List<TransferJob> jobs) {
  final grouped = <int, Map<String, List<TransferJob>>>{};
  for (final job in jobs) {
    grouped
        .putIfAbsent(job.hopCount, () => <String, List<TransferJob>>{})
        .putIfAbsent(job.remoteAddress, () => <TransferJob>[])
        .add(job);
  }

  final levels = <int, List<_TopologyNode>>{};
  grouped.forEach((level, nodes) {
    levels[level] =
        nodes.entries.map((entry) {
            final ordered = [...entry.value]..sort(
              (a, b) => _priority(a.status).compareTo(_priority(b.status)),
            );
            final lead = ordered.first;
            final totalBytes = ordered
                .map((job) => job.totalBytes)
                .fold<int>(0, (best, value) => value > best ? value : best);
            final transferred = ordered
                .map((job) => job.bytesTransferred)
                .fold<int>(0, (best, value) => value > best ? value : best);
            return _TopologyNode(
              address: entry.key,
              name: lead.remoteName ?? entry.key,
              status: lead.status,
              progress: totalBytes <= 0 ? 0 : transferred / totalBytes,
              bytesTransferred: transferred,
              totalBytes: totalBytes,
              isRelay: ordered.any((job) => job.isRelay),
              isTelemetry: ordered.any((job) => job.isRemoteTelemetry),
            );
          }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
  });

  final totalNodes = levels.values.fold<int>(
    0,
    (sum, nodes) => sum + nodes.length,
  );
  final activeNodes = levels.values.fold<int>(
    0,
    (sum, nodes) =>
        sum + nodes.where((node) => _isActiveStatus(node.status)).length,
  );
  return _Topology(
    levels: levels,
    totalNodes: totalNodes,
    activeNodes: activeNodes,
  );
}

bool _isActive(TransferJob job) => _isActiveStatus(job.status);

bool _isActiveStatus(TransferStatus status) {
  return status != TransferStatus.completed &&
      status != TransferStatus.failed &&
      status != TransferStatus.cancelled;
}

int _priority(TransferStatus status) {
  switch (status) {
    case TransferStatus.failed:
      return 0;
    case TransferStatus.sending:
    case TransferStatus.receiving:
      return 1;
    case TransferStatus.waitingForPeer:
    case TransferStatus.paused:
      return 2;
    case TransferStatus.completed:
      return 3;
    case TransferStatus.queued:
    case TransferStatus.preparing:
    case TransferStatus.awaitingAcceptance:
    case TransferStatus.connecting:
    case TransferStatus.cancelled:
      return 4;
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
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
