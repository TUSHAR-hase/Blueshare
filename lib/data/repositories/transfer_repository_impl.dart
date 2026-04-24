import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/bluetooth_peer.dart';
import '../../domain/entities/local_file_item.dart';
import '../../domain/entities/mesh_security_settings.dart';
import '../../domain/entities/mesh_transfer_tuning.dart';
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_history_entry.dart';
import '../../domain/entities/transfer_job.dart';
import '../../domain/entities/transfer_status.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../models/protocol_message.dart';
import '../services/background_transfer_service.dart';
import '../services/checksum_service.dart';
import '../services/classic_transport_service.dart';
import '../services/file_chunker.dart';
import '../services/file_storage_service.dart';
import '../services/history_store.dart';
import '../services/public_file_publish_service.dart';
import '../services/transfer_crypto_service.dart';

class TransferRepositoryImpl implements TransferRepository {
  TransferRepositoryImpl({
    required ClassicTransportService transportService,
    required ChecksumService checksumService,
    required FileChunker fileChunker,
    required FileStorageService fileStorageService,
    required HistoryStore historyStore,
    required BackgroundTransferService backgroundTransferService,
    required PublicFilePublishService publicFilePublishService,
    required TransferCryptoService transferCryptoService,
    required SettingsRepository settingsRepository,
  }) : _transportService = transportService,
       _checksumService = checksumService,
       _fileChunker = fileChunker,
       _fileStorageService = fileStorageService,
       _historyStore = historyStore,
       _backgroundTransferService = backgroundTransferService,
       _publicFilePublishService = publicFilePublishService,
       _transferCryptoService = transferCryptoService,
       _settingsRepository = settingsRepository;

  final ClassicTransportService _transportService;
  final ChecksumService _checksumService;
  final FileChunker _fileChunker;
  final FileStorageService _fileStorageService;
  final HistoryStore _historyStore;
  final BackgroundTransferService _backgroundTransferService;
  final PublicFilePublishService _publicFilePublishService;
  final TransferCryptoService _transferCryptoService;
  final SettingsRepository _settingsRepository;
  final Uuid _uuid = const Uuid();

  final StreamController<List<TransferJob>> _jobsController =
      StreamController<List<TransferJob>>.broadcast();
  final StreamController<List<TransferHistoryEntry>> _historyController =
      StreamController<List<TransferHistoryEntry>>.broadcast();

  final List<TransferJob> _jobs = <TransferJob>[];
  final List<TransferHistoryEntry> _history = <TransferHistoryEntry>[];
  final Map<String, Completer<Map<String, dynamic>>> _replyWaiters =
      <String, Completer<Map<String, dynamic>>>{};
  final Map<String, _OutgoingDeliverySession> _outgoingSessions =
      <String, _OutgoingDeliverySession>{};
  final Map<String, _IncomingTransferSession> _incomingSessions =
      <String, _IncomingTransferSession>{};
  final Map<String, Map<String, dynamic>> _finalizedIncomingReplies =
      <String, Map<String, dynamic>>{};
  final Map<String, _MeshTransferRecord> _meshTransfers =
      <String, _MeshTransferRecord>{};
  final Map<String, Future<_MeshTransferRecord>> _recordPreparationFutures =
      <String, Future<_MeshTransferRecord>>{};
  final Set<String> _activeOutgoingJobIds = <String>{};
  final Set<String> _activeOutgoingAddresses = <String>{};

  StreamSubscription<TransportMessageEvent>? _messageSubscription;
  StreamSubscription<TransportConnectionEvent>? _connectionSubscription;
  bool _initialized = false;
  bool _processingQueue = false;
  String _localNodeName = 'Unknown Device';
  MeshTransferTuning _tuning = const MeshTransferTuning();
  MeshSecuritySettings _securitySettings = const MeshSecuritySettings();

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _history
      ..clear()
      ..addAll(await _historyStore.load());
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
    _jobsController.add(const []);
    await _backgroundTransferService.initialize();
    await _refreshTuning();
    await _refreshSecuritySettings();
    try {
      _localNodeName = await _transportService.getLocalDeviceName();
    } catch (_) {
      _localNodeName = 'Unknown Device';
    }
    _messageSubscription = _transportService.messages.listen(
      _handleIncomingMessage,
    );
    _connectionSubscription = _transportService.connectionEvents.listen(
      _handleConnectionEvent,
    );
  }

  @override
  Future<void> queueFiles({
    required BluetoothPeer peer,
    required List<LocalFileItem> files,
  }) async {
    await queueMeshFiles(peers: <BluetoothPeer>[peer], files: files);
  }

  @override
  Future<void> queueMeshFiles({
    required List<BluetoothPeer> peers,
    required List<LocalFileItem> files,
  }) async {
    await _refreshTuning();
    await _refreshSecuritySettings();
    if (!_securitySettings.isEnabled) {
      throw StateError(
        'Configure the same mesh passkey on every device before starting a transfer.',
      );
    }
    final uniquePeers = peers
        .where((peer) => peer.isTransferCandidate && peer.isConnected)
        .fold<Map<String, BluetoothPeer>>(<String, BluetoothPeer>{}, (
          map,
          peer,
        ) {
          map[peer.address] = peer;
          return map;
        });

    if (uniquePeers.isEmpty) {
      throw StateError(
        'File transfer needs at least one connected BlueShare phone with the same mesh passkey.',
      );
    }

    for (final file in files) {
      final record = _MeshTransferRecord(
        transferId: _uuid.v4(),
        fileName: file.name,
        filePath: file.path,
        mimeType: file.mimeType ?? lookupMimeType(file.path),
        totalBytes: file.size,
        originNode: _localNodeName,
        hopCount: 0,
        isLocalOrigin: true,
      );
      _meshTransfers[record.transferId] = record;

      for (final peer in uniquePeers.values) {
        _enqueueDeliveryJob(
          record: record,
          peerAddress: peer.address,
          peerName: peer.displayName,
          hopCount: 0,
          isRelay: false,
          statusDetail:
              uniquePeers.length > 1
                  ? 'Seed delivery for mesh distribution.'
                  : 'Direct delivery.',
        );
      }
    }

    _emitJobs();
    unawaited(_processQueue());
  }

  @override
  Future<List<TransferHistoryEntry>> loadHistory() async {
    return List<TransferHistoryEntry>.unmodifiable(_history);
  }

  @override
  Stream<List<TransferHistoryEntry>> watchHistory() =>
      _historyController.stream;

  @override
  Stream<List<TransferJob>> watchTransfers() => _jobsController.stream;

  @override
  Future<String> exportTransferLog() async {
    final payload = <String, dynamic>{
      'generatedAt': DateTime.now().toIso8601String(),
      'localNodeName': _localNodeName,
      'tuning': {
        'chunkRetries': _tuning.chunkRetries,
        'controlRetries': _tuning.controlRetries,
        'reconnectAttempts': _tuning.reconnectAttempts,
        'parallelOutgoingPerWave': _tuning.parallelOutgoingPerWave,
        'retryBackoffSeconds': _tuning.retryBackoffSeconds,
      },
      'security': {
        'passkeyEnabled': _securitySettings.isEnabled,
        'transportEncryption': _securitySettings.isEnabled,
      },
      'jobs':
          _jobs
              .map(
                (job) => <String, dynamic>{
                  'id': job.id,
                  'transferId': job.transferId,
                  'fileName': job.fileName,
                  'remoteAddress': job.remoteAddress,
                  'remoteName': job.remoteName,
                  'direction': job.direction.name,
                  'status': job.status.name,
                  'hopCount': job.hopCount,
                  'progress': job.progress,
                  'bytesTransferred': job.bytesTransferred,
                  'totalBytes': job.totalBytes,
                  'isRelay': job.isRelay,
                  'originNode': job.originNode,
                  'sourceAddress': job.sourceAddress,
                  'sourceName': job.sourceName,
                  'isRemoteTelemetry': job.isRemoteTelemetry,
                  'statusDetail': job.statusDetail,
                  'errorMessage': job.errorMessage,
                  'startedAt': job.startedAt?.toIso8601String(),
                  'updatedAt': job.updatedAt?.toIso8601String(),
                  'completedAt': job.completedAt?.toIso8601String(),
                },
              )
              .toList(),
      'history': _history.map((entry) => entry.toMap()).toList(),
    };

    final stamp = DateTime.now().millisecondsSinceEpoch;
    return _fileStorageService.writeExportFile(
      folderName: 'exports',
      fileName: 'mesh_transfer_log_$stamp.json',
      contents: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  @override
  Future<void> pause(String jobId) async {
    final session = _outgoingSessions[jobId];
    if (session != null) {
      session.pause();
    }
    _replaceJob(
      jobId,
      (job) => job.copyWith(
        status: TransferStatus.paused,
        updatedAt: DateTime.now(),
        statusDetail: 'Paused by user.',
      ),
    );
  }

  @override
  Future<void> resume(String jobId) async {
    final session = _outgoingSessions[jobId];
    if (session != null) {
      session.resume();
      _replaceJob(
        jobId,
        (job) => job.copyWith(
          status: TransferStatus.sending,
          updatedAt: DateTime.now(),
          clearStatusDetail: true,
        ),
      );
      return;
    }

    _replaceJob(
      jobId,
      (job) => job.copyWith(
        status: TransferStatus.queued,
        updatedAt: DateTime.now(),
        clearStatusDetail: true,
      ),
    );
    unawaited(_processQueue());
  }

  @override
  Future<void> cancel(String jobId) async {
    final job = _jobById(jobId);
    if (job == null) {
      return;
    }

    final outgoing = _outgoingSessions[jobId];
    if (outgoing != null) {
      outgoing.cancel();
      await _safeSend(
        address: job.remoteAddress,
        message: ProtocolMessage(
          type: ProtocolMessageType.cancel,
          payload: {'transferId': job.transferId},
        ),
      );
    }

    if (job.direction == TransferDirection.incoming) {
      final incoming = _incomingSessions.remove(job.transferId);
      if (incoming != null) {
        final tempFile = File(incoming.tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    _replaceJob(
      jobId,
      (current) => current.copyWith(
        status: TransferStatus.cancelled,
        updatedAt: DateTime.now(),
        completedAt: DateTime.now(),
        statusDetail: 'Cancelled.',
      ),
    );
    await _persistHistoryFor(jobId);
  }

  @override
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _jobsController.close();
    await _historyController.close();
  }

  Future<void> _processQueue() async {
    if (_processingQueue) {
      return;
    }
    _processingQueue = true;

    try {
      await _refreshTuning();
      final candidates = _nextQueuedJobs();
      if (candidates.isEmpty) {
        return;
      }

      for (final job in candidates) {
        _activeOutgoingJobIds.add(job.id);
        _activeOutgoingAddresses.add(job.remoteAddress);
        unawaited(_runOutgoingJob(job));
      }
    } finally {
      _processingQueue = false;
      await _refreshForegroundState();
    }
  }

  List<TransferJob> _nextQueuedJobs() {
    final reservedAddresses = <String>{..._activeOutgoingAddresses};
    final schedulableJobs = _prioritizedSchedulableJobs(reservedAddresses);
    if (schedulableJobs.isEmpty) {
      return <TransferJob>[];
    }
    final prioritizedWave = schedulableJobs.first;
    final selected = <TransferJob>[];

    for (final job in schedulableJobs) {
      if (!_isSameMeshWave(job, prioritizedWave)) {
        continue;
      }

      selected.add(job);
      reservedAddresses.add(job.remoteAddress);
    }

    return selected;
  }

  List<TransferJob> _prioritizedSchedulableJobs(Set<String> reservedAddresses) {
    final connectedAddresses = _transportService.connectedAddresses.toSet();
    final jobs =
        _jobs
            .where((job) => _isSchedulableOutgoingJob(job, reservedAddresses))
            .toList()
          ..sort(
            (left, right) => _compareOutgoingPriority(
              left,
              right,
              connectedAddresses,
            ),
          );
    return jobs;
  }

  bool _isSameMeshWave(TransferJob job, TransferJob waveLead) {
    return job.transferId == waveLead.transferId &&
        job.hopCount == waveLead.hopCount &&
        job.isRelay == waveLead.isRelay;
  }

  int _compareOutgoingPriority(
    TransferJob left,
    TransferJob right,
    Set<String> connectedAddresses,
  ) {
    final leftBucket = _priorityBucket(left, connectedAddresses);
    final rightBucket = _priorityBucket(right, connectedAddresses);
    if (leftBucket != rightBucket) {
      return leftBucket.compareTo(rightBucket);
    }

    final leftUpdated = left.updatedAt ?? left.startedAt ?? DateTime(1970);
    final rightUpdated = right.updatedAt ?? right.startedAt ?? DateTime(1970);
    final timeCompare = leftUpdated.compareTo(rightUpdated);
    if (timeCompare != 0) {
      return timeCompare;
    }

    final nameCompare = (left.remoteName ?? left.remoteAddress).compareTo(
      right.remoteName ?? right.remoteAddress,
    );
    if (nameCompare != 0) {
      return nameCompare;
    }

    return left.id.compareTo(right.id);
  }

  int _priorityBucket(TransferJob job, Set<String> connectedAddresses) {
    final isConnected = connectedAddresses.contains(job.remoteAddress);
    if (job.hopCount == 0 && isConnected) {
      return 0;
    }
    if (job.hopCount == 0) {
      return 1;
    }
    if (isConnected) {
      return 2;
    }
    return 3 + job.hopCount;
  }

  bool _isSchedulableOutgoingJob(
    TransferJob job,
    Set<String> reservedAddresses,
  ) {
    if (job.direction != TransferDirection.outgoing ||
        job.isRemoteTelemetry ||
        _activeOutgoingJobIds.contains(job.id) ||
        reservedAddresses.contains(job.remoteAddress)) {
      return false;
    }

    return job.status == TransferStatus.queued ||
        job.status == TransferStatus.connecting ||
        job.status == TransferStatus.preparing ||
        job.status == TransferStatus.awaitingAcceptance;
  }

  Future<void> _runOutgoingJob(TransferJob job) async {
    try {
      await _sendJob(job);
    } catch (_) {
      // Job state already updated in _sendJob.
    } finally {
      _activeOutgoingJobIds.remove(job.id);
      final hasOtherActiveForAddress = _jobs.any(
        (item) =>
            item.id != job.id &&
            _activeOutgoingJobIds.contains(item.id) &&
            item.remoteAddress == job.remoteAddress,
      );
      if (!hasOtherActiveForAddress) {
        _activeOutgoingAddresses.remove(job.remoteAddress);
      }
      await _refreshForegroundState();
      unawaited(_processQueue());
    }
  }

  Future<void> _sendJob(TransferJob sourceJob) async {
    await _refreshSecuritySettings();
    final record = await _prepareTransferRecord(sourceJob.transferId);
    final file = File(record.filePath);
    if (!await file.exists()) {
      await _failTransfer(sourceJob.id, 'File no longer exists.');
      return;
    }

    if (record.deliveredPeers.contains(sourceJob.remoteAddress)) {
      await _markDeliveryComplete(
        sourceJob.id,
        bytesTransferred: record.totalBytes,
        detail: 'Peer already confirmed.',
      );
      return;
    }

    _replaceJob(
      sourceJob.id,
      (job) => job.copyWith(
        status: TransferStatus.connecting,
        updatedAt: DateTime.now(),
        clearErrorMessage: true,
        statusDetail: 'Connecting to ${job.remoteName ?? job.remoteAddress}.',
      ),
      reportUpstream: true,
    );

    final connected = await _ensureConnected(sourceJob.remoteAddress);
    if (!connected) {
      await _deferTransfer(
        sourceJob.id,
        'Waiting for ${sourceJob.remoteName ?? sourceJob.remoteAddress} to come online.',
      );
      return;
    }

    final totalBytes = record.totalBytes;
    final totalChunks = record.totalChunks;
    final checksum = record.checksum!;

    final session = _OutgoingDeliverySession(
      jobId: sourceJob.id,
      transferId: sourceJob.transferId,
      remoteAddress: sourceJob.remoteAddress,
      checksum: checksum,
      totalChunks: totalChunks,
    );
    _outgoingSessions[sourceJob.id] = session;

    _replaceJob(
      sourceJob.id,
      (job) => job.copyWith(
        status: TransferStatus.preparing,
        totalBytes: totalBytes,
        checksum: checksum,
        totalChunks: totalChunks,
        startedAt: job.startedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        statusDetail:
            job.isRelay
                ? 'Relaying hop ${job.hopCount + 1}.'
                : 'Negotiating transfer.',
      ),
      reportUpstream: true,
    );

    try {
      final offerPayload = <String, dynamic>{
        'transferId': sourceJob.transferId,
        'version': AppConstants.protocolVersion,
        'fileName': record.fileName,
        'fileSize': totalBytes,
        'mimeType': record.mimeType,
        'checksum': checksum,
        'totalChunks': totalChunks,
        'encrypted': _transferCryptoService.isEnabled,
        'originNode': record.originNode,
        'previousHop': _localNodeName,
        'hopCount': sourceJob.hopCount,
        'securityMode': _securitySettings.isEnabled ? 'passkey' : 'open',
      };
      offerPayload['authorization'] = await _signOfferPayload(offerPayload);

      final offerReply = await _sendAndAwaitWithRetry(
        key: _replyKey('offer', sourceJob.transferId, sourceJob.remoteAddress),
        timeout: AppConstants.transferOfferTimeout,
        attempts: _tuning.controlRetries,
        message: ProtocolMessage(
          type: ProtocolMessageType.offer,
          payload: offerPayload,
        ),
        onRetry: (attempt, error) async {
          _log(
            'Retrying offer for ${sourceJob.transferId} '
            '($attempt/${_tuning.controlRetries}): $error',
          );
          final reconnected = await _ensureConnected(sourceJob.remoteAddress);
          if (!reconnected) {
            throw Exception('Connection lost while negotiating transfer.');
          }
        },
      );

      if (offerReply['alreadyReceived'] == true) {
        record.deliveredPeers.add(sourceJob.remoteAddress);
        await _markDeliveryComplete(
          sourceJob.id,
          bytesTransferred: totalBytes,
          detail: 'Peer already has this transfer.',
        );
        return;
      }

      if (offerReply['duplicate'] == true) {
        await _deferTransfer(
          sourceJob.id,
          'Peer is already receiving this transfer from another relay.',
        );
        unawaited(
          Future<void>.delayed(
            Duration(seconds: max(4, _tuning.retryBackoffSeconds * 4)),
            () {
              final job = _jobById(sourceJob.id);
              if (job == null || job.status != TransferStatus.waitingForPeer) {
                return;
              }
              _replaceJob(
                sourceJob.id,
                (current) => current.copyWith(
                  status: TransferStatus.queued,
                  updatedAt: DateTime.now(),
                  clearStatusDetail: true,
                ),
                reportUpstream: true,
              );
              unawaited(_processQueue());
            },
          ),
        );
        return;
      }

      if (offerReply['accepted'] != true) {
        throw Exception(
          offerReply['reason'] as String? ??
              'The remote device declined the transfer.',
        );
      }

      final resumeFromChunk = ((offerReply['resumeFromChunk'] as int?) ?? 0)
          .clamp(0, totalChunks);
      final resumedBytes = min(
        totalBytes,
        resumeFromChunk * AppConstants.transferChunkSize,
      );
      session.acknowledgedChunks = resumeFromChunk;

      _replaceJob(
        sourceJob.id,
        (job) => job.copyWith(
          status: TransferStatus.sending,
          bytesTransferred: resumedBytes,
          currentChunk: resumeFromChunk,
          updatedAt: DateTime.now(),
          statusDetail:
              resumeFromChunk > 0
                  ? 'Resuming from chunk ${resumeFromChunk + 1}.'
                  : (job.isRelay ? 'Forwarding to next hop.' : 'Sending.'),
        ),
        reportUpstream: true,
      );

      final transferStart = DateTime.now();
      for (
        var chunkIndex = resumeFromChunk;
        chunkIndex < totalChunks;
        chunkIndex++
      ) {
        if (session.cancelled) {
          throw Exception('Transfer cancelled.');
        }

        await session.waitIfPaused();
        final stillConnected = await _ensureConnected(sourceJob.remoteAddress);
        if (!stillConnected) {
          throw Exception('Bluetooth connection dropped before sending data.');
        }

        final chunk = await _fileChunker.readChunk(
          path: record.filePath,
          chunkIndex: chunkIndex,
          chunkSize: AppConstants.transferChunkSize,
        );

        final encryptedPayload = await _transferCryptoService.encrypt(
          chunk.bytes,
        );
        Map<String, dynamic> reply = const <String, dynamic>{};
        var retriesForChunk = 0;
        for (var attempt = 1; attempt <= _tuning.chunkRetries; attempt++) {
          try {
            reply = await _sendAndAwait(
              key: _replyKey(
                'chunk',
                sourceJob.transferId,
                sourceJob.remoteAddress,
                chunkIndex,
              ),
              timeout: AppConstants.transferAckTimeout,
              address: sourceJob.remoteAddress,
              message: ProtocolMessage(
                type: ProtocolMessageType.chunk,
                payload: {
                  'transferId': sourceJob.transferId,
                  'sequence': chunkIndex,
                  'length': chunk.bytes.length,
                  'payload': base64Encode(encryptedPayload.bytes),
                  'encrypted': encryptedPayload.encrypted,
                  'nonce': encryptedPayload.nonce,
                  'mac': encryptedPayload.mac,
                },
              ),
            );
            if (reply['accepted'] == true) {
              retriesForChunk = attempt - 1;
              break;
            }
            final reason =
                reply['reason'] as String? ?? 'Remote device rejected chunk.';
            if (attempt == _tuning.chunkRetries) {
              throw Exception(reason);
            }
            retriesForChunk = attempt;
          } catch (error) {
            if (attempt == _tuning.chunkRetries) {
              rethrow;
            }
            retriesForChunk = attempt;
            final reconnected = await _ensureConnected(sourceJob.remoteAddress);
            if (!reconnected) {
              throw Exception(
                'Bluetooth connection dropped while retrying chunk '
                '${chunkIndex + 1}.',
              );
            }
          }
        }

        if (reply['accepted'] != true) {
          throw Exception(
            reply['reason'] as String? ?? 'Chunk $chunkIndex was rejected.',
          );
        }

        session.retryCount = retriesForChunk;
        session.acknowledgedChunks = chunkIndex + 1;
        final transferredBytes = min(
          totalBytes,
          (chunkIndex + 1) * AppConstants.transferChunkSize,
        );
        final elapsedMs = max(
          DateTime.now().difference(transferStart).inMilliseconds,
          1,
        );
        final speed = transferredBytes / (elapsedMs / 1000);

        _replaceJob(
          sourceJob.id,
          (job) => job.copyWith(
            bytesTransferred: transferredBytes,
            status: TransferStatus.sending,
            retryCount: session.retryCount,
            currentChunk: chunkIndex + 1,
            speedBytesPerSecond: speed,
            updatedAt: DateTime.now(),
            statusDetail:
                job.isRelay
                    ? 'Forwarding to ${job.remoteName ?? job.remoteAddress}.'
                    : 'Sending to ${job.remoteName ?? job.remoteAddress}.',
          ),
          reportUpstream: true,
        );
        await _refreshForegroundState();
      }

      final completionReply = await _sendAndAwaitWithRetry(
        key: _replyKey(
          'complete',
          sourceJob.transferId,
          sourceJob.remoteAddress,
        ),
        timeout: AppConstants.transferCompleteTimeout,
        attempts: _tuning.controlRetries,
        message: ProtocolMessage(
          type: ProtocolMessageType.complete,
          payload: {
            'transferId': sourceJob.transferId,
            'checksum': checksum,
            'hopCount': sourceJob.hopCount,
          },
        ),
        onRetry: (attempt, error) async {
          final reconnected = await _ensureConnected(sourceJob.remoteAddress);
          if (!reconnected) {
            throw Exception('Connection lost while finalizing transfer.');
          }
        },
      );

      if (completionReply['accepted'] != true &&
          completionReply['alreadyReceived'] != true) {
        throw Exception(
          completionReply['reason'] as String? ??
              'The remote device failed integrity validation.',
        );
      }

      record.deliveredPeers.add(sourceJob.remoteAddress);
      await _markDeliveryComplete(
        sourceJob.id,
        bytesTransferred: totalBytes,
        detail:
            sourceJob.isRelay
                ? 'Forwarded successfully.'
                : 'Delivered successfully.',
      );
    } catch (error) {
      if (_shouldDeferFailure(error)) {
        await _deferTransfer(
          sourceJob.id,
          'Paused until ${sourceJob.remoteName ?? sourceJob.remoteAddress} reconnects.',
        );
      } else {
        await _failTransfer(
          sourceJob.id,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      _outgoingSessions.remove(sourceJob.id);
    }
  }

  Future<void> _handleIncomingMessage(TransportMessageEvent event) async {
    ProtocolMessage message;
    try {
      message = ProtocolMessage.decode(event.message);
    } catch (_) {
      _log('Ignored non-protocol message from ${event.address}.');
      return;
    }

    final payload = message.payload;
    final transferId = payload['transferId'] as String?;
    if (transferId == null) {
      return;
    }

    switch (message.type) {
      case ProtocolMessageType.offer:
        await _handleOffer(transferId, payload, event);
        break;
      case ProtocolMessageType.offerAck:
        _completeReply(_replyKey('offer', transferId, event.address), payload);
        break;
      case ProtocolMessageType.chunk:
        await _handleChunk(transferId, payload, event);
        break;
      case ProtocolMessageType.chunkAck:
        final sequence = payload['sequence'] as int? ?? -1;
        _completeReply(
          _replyKey('chunk', transferId, event.address, sequence),
          payload,
        );
        break;
      case ProtocolMessageType.complete:
        await _handleComplete(transferId, event);
        break;
      case ProtocolMessageType.completeAck:
        _completeReply(
          _replyKey('complete', transferId, event.address),
          payload,
        );
        break;
      case ProtocolMessageType.meshReport:
        await _handleMeshReport(transferId, payload, event);
        break;
      case ProtocolMessageType.cancel:
        await _cancelTransferByTransferId(transferId);
        break;
      case ProtocolMessageType.error:
        await _failTransferByTransferId(
          transferId,
          payload['reason'] as String? ?? 'Unknown remote error.',
        );
        break;
    }
  }

  Future<void> _handleOffer(
    String transferId,
    Map<String, dynamic> payload,
    TransportMessageEvent event,
  ) async {
    await _refreshSecuritySettings();
    final existingRecord = _meshTransfers[transferId];
    if (existingRecord?.isComplete == true) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.offerAck,
          payload: {
            'transferId': transferId,
            'accepted': true,
            'alreadyReceived': true,
            'resumeFromChunk': existingRecord!.totalChunks,
          },
        ),
      );
      return;
    }

    final existingSession = _incomingSessions[transferId];
    if (existingSession != null) {
      if (existingSession.remoteAddress == event.address) {
        await _safeSend(
          address: event.address,
          message: ProtocolMessage(
            type: ProtocolMessageType.offerAck,
            payload: {
              'transferId': transferId,
              'accepted': true,
              'resumeFromChunk': existingSession.receivedChunks,
            },
          ),
        );
      } else {
        await _safeSend(
          address: event.address,
          message: ProtocolMessage(
            type: ProtocolMessageType.offerAck,
            payload: {
              'transferId': transferId,
              'accepted': false,
              'duplicate': true,
              'reason': 'Transfer already in progress from another peer.',
            },
          ),
        );
      }
      return;
    }

    final securityError = await _validateOfferSecurity(payload);
    if (securityError != null) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.offerAck,
          payload: {
            'transferId': transferId,
            'accepted': false,
            'reason': securityError,
          },
        ),
      );
      return;
    }

    final tempFile = await _fileStorageService.createIncomingTempFile(
      transferId: transferId,
    );
    final session = _IncomingTransferSession(
      transferId: transferId,
      fileName: payload['fileName'] as String? ?? 'incoming.bin',
      expectedChunks: payload['totalChunks'] as int? ?? 0,
      expectedChecksum: payload['checksum'] as String? ?? '',
      remoteAddress: event.address,
      tempPath: tempFile.path,
      mimeType: payload['mimeType'] as String?,
      hopCount: payload['hopCount'] as int? ?? 0,
      originNode: payload['originNode'] as String?,
      senderNode: payload['previousHop'] as String?,
      requiresSecureTransfer: payload['securityMode'] == 'passkey',
    );
    _incomingSessions[transferId] = session;
    _meshTransfers[transferId] = _MeshTransferRecord(
      transferId: transferId,
      fileName: session.fileName,
      filePath: tempFile.path,
      mimeType: session.mimeType,
      totalBytes: payload['fileSize'] as int? ?? 0,
      checksum: session.expectedChecksum,
      totalChunks: session.expectedChunks,
      originNode: session.originNode ?? event.address,
      hopCount: session.hopCount,
      receivedFrom: event.address,
      isLocalOrigin: false,
    );

    _upsertIncomingJob(
      transferId: transferId,
      fileName: session.fileName,
      filePath: tempFile.path,
      remoteAddress: event.address,
      totalBytes: payload['fileSize'] as int? ?? 0,
      mimeType: session.mimeType,
      totalChunks: session.expectedChunks,
      hopCount: session.hopCount,
      originNode: session.originNode,
      sourceAddress: event.address,
      sourceName: session.senderNode,
    );

    await _safeSend(
      address: event.address,
      message: ProtocolMessage(
        type: ProtocolMessageType.offerAck,
        payload: {
          'transferId': transferId,
          'accepted': true,
          'resumeFromChunk': 0,
        },
      ),
    );
    await _refreshForegroundState();
  }

  Future<void> _handleChunk(
    String transferId,
    Map<String, dynamic> payload,
    TransportMessageEvent event,
  ) async {
    final session = _incomingSessions[transferId];
    if (session == null) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.chunkAck,
          payload: {
            'transferId': transferId,
            'sequence': payload['sequence'],
            'accepted': false,
            'reason': 'Unknown transfer.',
          },
        ),
      );
      return;
    }

    final sequence = payload['sequence'] as int? ?? -1;
    if (sequence < session.receivedChunks) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.chunkAck,
          payload: {
            'transferId': transferId,
            'sequence': sequence,
            'accepted': true,
          },
        ),
      );
      return;
    }

    if (sequence > session.receivedChunks) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.chunkAck,
          payload: {
            'transferId': transferId,
            'sequence': sequence,
            'accepted': false,
            'reason': 'Out-of-order chunk.',
          },
        ),
      );
      return;
    }

    try {
      final encrypted = payload['encrypted'] as bool? ?? false;
      if (session.requiresSecureTransfer && !encrypted) {
        throw Exception(
          'Encrypted chunk required for passkey-protected transfer.',
        );
      }
      final encryptedBytes = Uint8List.fromList(
        base64Decode(payload['payload'] as String),
      );
      final chunkBytes = await _transferCryptoService.decrypt(
        data: encryptedBytes,
        encrypted: encrypted,
        nonce: payload['nonce'] as String?,
        mac: payload['mac'] as String?,
      );
      final declaredLength = payload['length'] as int?;
      if (declaredLength != null && declaredLength != chunkBytes.length) {
        throw Exception(
          'Chunk length mismatch: expected $declaredLength, got ${chunkBytes.length}.',
        );
      }

      await _fileStorageService.appendBytes(
        filePath: session.tempPath,
        bytes: chunkBytes,
      );

      session.receivedChunks += 1;
      session.bytesTransferred += chunkBytes.length;
      _replaceJob(
        transferId,
        (job) => job.copyWith(
          bytesTransferred: session.bytesTransferred,
          currentChunk: session.receivedChunks,
          status: TransferStatus.receiving,
          updatedAt: DateTime.now(),
          statusDetail:
              session.requiresSecureTransfer
                  ? 'Passkey verified. Receiving from ${job.sourceName ?? job.remoteAddress}.'
                  : 'Receiving from ${job.sourceName ?? job.remoteAddress}.',
        ),
      );
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.chunkAck,
          payload: {
            'transferId': transferId,
            'sequence': sequence,
            'accepted': true,
          },
        ),
      );
      await _refreshForegroundState();
    } catch (error) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.chunkAck,
          payload: {
            'transferId': transferId,
            'sequence': sequence,
            'accepted': false,
            'reason': error.toString(),
          },
        ),
      );
    }
  }

  Future<void> _handleComplete(
    String transferId,
    TransportMessageEvent event,
  ) async {
    final finalizedReply = _finalizedIncomingReplies[transferId];
    if (finalizedReply != null) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.completeAck,
          payload: finalizedReply,
        ),
      );
      return;
    }

    final session = _incomingSessions.remove(transferId);
    if (session == null) {
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.completeAck,
          payload: {
            'transferId': transferId,
            'accepted': false,
            'reason': 'Unknown transfer.',
          },
        ),
      );
      return;
    }

    final actualChecksum = await _checksumService.sha256File(session.tempPath);
    if (actualChecksum != session.expectedChecksum) {
      final reply = <String, dynamic>{
        'transferId': transferId,
        'accepted': false,
        'reason': 'Checksum mismatch.',
      };
      _finalizedIncomingReplies[transferId] = reply;
      _replaceJob(
        transferId,
        (job) => job.copyWith(
          status: TransferStatus.failed,
          checksum: actualChecksum,
          errorMessage: 'Checksum mismatch detected after receive.',
          completedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await _persistHistoryFor(transferId);
      await _safeSend(
        address: event.address,
        message: ProtocolMessage(
          type: ProtocolMessageType.completeAck,
          payload: reply,
        ),
      );
      return;
    }

    final finalPath = await _fileStorageService.finalizeIncomingFile(
      tempPath: session.tempPath,
      fileName: session.fileName,
      remoteAddress: session.remoteAddress,
    );
    final publishedPath = await _publicFilePublishService.publishReceivedFile(
      sourcePath: finalPath,
      fileName: session.fileName,
      mimeType: _jobById(transferId)?.mimeType,
    );

    final record = _meshTransfers[transferId];
    if (record != null) {
      record
        ..filePath = finalPath
        ..checksum = actualChecksum
        ..totalBytes = max(record.totalBytes, session.bytesTransferred)
        ..totalChunks = session.expectedChunks
        ..hopCount = session.hopCount
        ..receivedFrom = session.remoteAddress
        ..isComplete = true;
    }

    _replaceJob(
      transferId,
      (job) => job.copyWith(
        filePath: finalPath,
        checksum: actualChecksum,
        bytesTransferred: session.bytesTransferred,
        status: TransferStatus.completed,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        statusDetail:
            publishedPath != null
                ? (session.requiresSecureTransfer
                    ? 'Passkey verified, saved locally, and published to device storage.'
                    : 'Saved locally and published to device storage.')
                : (session.requiresSecureTransfer
                    ? 'Passkey verified and saved locally.'
                    : 'Saved locally.'),
      ),
    );
    await _persistHistoryFor(transferId);
    final reply = <String, dynamic>{
      'transferId': transferId,
      'accepted': true,
      'path': finalPath,
    };
    _finalizedIncomingReplies[transferId] = reply;
    await _safeSend(
      address: event.address,
      message: ProtocolMessage(
        type: ProtocolMessageType.completeAck,
        payload: reply,
      ),
    );

    await _queueRelayDeliveries(
      transferId,
      excludeAddresses: <String>{session.remoteAddress},
    );
    await _refreshForegroundState();
  }

  Future<void> _handleMeshReport(
    String transferId,
    Map<String, dynamic> payload,
    TransportMessageEvent event,
  ) async {
    _upsertMeshReportJob(transferId: transferId, payload: payload);
    await _forwardMeshReportUpstream(
      transferId: transferId,
      payload: payload,
      receivedFrom: event.address,
    );
  }

  Future<_MeshTransferRecord> _prepareTransferRecord(String transferId) {
    final pending = _recordPreparationFutures[transferId];
    if (pending != null) {
      return pending;
    }

    final future = _prepareTransferRecordInternal(transferId);
    _recordPreparationFutures[transferId] = future;
    future.whenComplete(() {
      if (_recordPreparationFutures[transferId] == future) {
        _recordPreparationFutures.remove(transferId);
      }
    });
    return future;
  }

  Future<_MeshTransferRecord> _prepareTransferRecordInternal(
    String transferId,
  ) async {
    final record = _meshTransfers[transferId];
    if (record == null) {
      throw StateError('Transfer $transferId is not registered.');
    }

    if (record.totalBytes <= 0) {
      record.totalBytes = await File(record.filePath).length();
    }
    if (record.checksum == null || record.checksum!.isEmpty) {
      record.checksum = await _checksumService.sha256File(record.filePath);
    }
    if (record.totalChunks <= 0) {
      record.totalChunks = _fileChunker.totalChunksFor(
        totalBytes: record.totalBytes,
        chunkSize: AppConstants.transferChunkSize,
      );
    }
    return record;
  }

  Future<void> _queueRelayDeliveries(
    String transferId, {
    Set<String> excludeAddresses = const <String>{},
  }) async {
    final record = _meshTransfers[transferId];
    if (record == null || !record.isComplete) {
      return;
    }

    for (final address in _transportService.connectedAddresses) {
      if (excludeAddresses.contains(address) ||
          record.deliveredPeers.contains(address) ||
          record.receivedFrom == address ||
          _hasPendingDelivery(transferId, address)) {
        continue;
      }

      _enqueueDeliveryJob(
        record: record,
        peerAddress: address,
        peerName: address,
        hopCount: record.hopCount + 1,
        isRelay: true,
        sourceName: _localNodeName,
        statusDetail: 'Queued for relay propagation.',
      );
    }

    _emitJobs();
    unawaited(_processQueue());
  }

  Future<bool> _ensureConnected(String address) async {
    if (await _transportService.isConnected(address)) {
      return true;
    }

    for (var attempt = 0; attempt < _tuning.reconnectAttempts; attempt++) {
      final connected = await _transportService.connect(address);
      if (connected || await _transportService.isConnected(address)) {
        return true;
      }
      await Future<void>.delayed(
        Duration(seconds: _tuning.retryBackoffSeconds),
      );
    }

    return false;
  }

  Future<Map<String, dynamic>> _sendAndAwait({
    required String key,
    required Duration timeout,
    required String address,
    required ProtocolMessage message,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    _replyWaiters[key] = completer;
    final sent = await _safeSend(address: address, message: message);
    if (!sent) {
      _replyWaiters.remove(key);
      throw Exception('Unable to send protocol message.');
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _replyWaiters.remove(key);
        throw TimeoutException('Timed out while waiting for $key.');
      },
    );
  }

  Future<Map<String, dynamic>> _sendAndAwaitWithRetry({
    required String key,
    required Duration timeout,
    required ProtocolMessage message,
    required int attempts,
    required Future<void> Function(int attempt, Object error) onRetry,
  }) async {
    Object? lastError;
    final targetAddress = _addressFromReplyKey(key);
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await _sendAndAwait(
          key: key,
          timeout: timeout,
          address: targetAddress,
          message: message,
        );
      } catch (error) {
        lastError = error;
        if (attempt == attempts) {
          break;
        }
        await onRetry(attempt + 1, error);
      }
    }

    throw lastError ?? Exception('Unknown transfer retry failure.');
  }

  Future<bool> _safeSend({
    required String address,
    required ProtocolMessage message,
  }) async {
    final sent = await _transportService.sendMessage(
      address: address,
      message: message.encode(),
    );
    if (!sent) {
      throw Exception('Bluetooth write failed.');
    }
    return sent;
  }

  void _completeReply(String key, Map<String, dynamic> payload) {
    final completer = _replyWaiters.remove(key);
    if (completer != null && !completer.isCompleted) {
      completer.complete(payload);
    }
  }

  String _replyKey(
    String prefix,
    String transferId,
    String address, [
    int? sequence,
  ]) {
    return sequence == null
        ? '$prefix|$transferId|$address'
        : '$prefix|$transferId|$address|$sequence';
  }

  String _addressFromReplyKey(String key) {
    final parts = key.split('|');
    if (parts.length < 3) {
      throw StateError('Invalid reply key: $key');
    }
    return parts[2];
  }

  void _replaceJob(
    String jobId,
    TransferJob Function(TransferJob job) transform, {
    bool reportUpstream = false,
  }) {
    final index = _jobs.indexWhere((job) => job.id == jobId);
    if (index == -1) {
      return;
    }
    final updated = transform(_jobs[index]);
    _jobs[index] = updated;
    _emitJobs();
    if (reportUpstream) {
      unawaited(_reportMeshProgressIfNeeded(updated));
    }
  }

  Future<void> _persistHistoryFor(String jobId) async {
    final job = _jobById(jobId);
    if (job == null || job.isRemoteTelemetry) {
      return;
    }

    final entry = TransferHistoryEntry(
      id: _uuid.v4(),
      transferId: job.transferId,
      fileName: job.fileName,
      filePath: job.filePath,
      remoteAddress: job.remoteAddress,
      remoteName: job.remoteName,
      direction: job.direction,
      totalBytes: job.totalBytes,
      bytesTransferred: job.bytesTransferred,
      status: job.status,
      startedAt: job.startedAt ?? DateTime.now(),
      completedAt: job.completedAt,
      checksum: job.checksum,
      errorMessage: job.errorMessage,
      sourceAddress: job.sourceAddress,
      sourceName: job.sourceName,
      originNode: job.originNode,
      hopCount: job.hopCount,
      forwardedToCount: job.forwardedToCount,
      isRelay: job.isRelay,
    );

    _history.insert(0, entry);
    _historyController.add(List<TransferHistoryEntry>.unmodifiable(_history));
    try {
      await _historyStore.save(_history);
    } catch (error) {
      _log('Failed to persist history for ${job.transferId}: $error');
    }
  }

  void _emitJobs() {
    _jobs.sort((left, right) {
      final leftTime = left.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });
    _jobsController.add(List<TransferJob>.unmodifiable(_jobs));
  }

  void _handleConnectionEvent(TransportConnectionEvent event) {
    switch (event.state) {
      case TransportConnectionState.connected:
        if (event.address != null) {
          _reactivateRetryableJobs(event.address!);
          for (final record in _meshTransfers.values) {
            if (!record.isComplete ||
                record.deliveredPeers.contains(event.address) ||
                record.receivedFrom == event.address ||
                _hasPendingDelivery(record.transferId, event.address!)) {
              continue;
            }
            _enqueueDeliveryJob(
              record: record,
              peerAddress: event.address!,
              peerName: event.address!,
              hopCount: record.hopCount + 1,
              isRelay: true,
              sourceName: _localNodeName,
              statusDetail: 'Queued after peer joined the mesh.',
            );
          }
          _emitJobs();
          unawaited(_processQueue());
        }
        break;
      case TransportConnectionState.disconnected:
      case TransportConnectionState.connecting:
      case TransportConnectionState.serverStarted:
      case TransportConnectionState.serverStopped:
      case TransportConnectionState.error:
        break;
    }
  }

  void _log(String message) {
    developer.log(message, name: 'BlueShareTransfer');
  }

  Future<void> _refreshForegroundState() async {
    final activeTransfers =
        _jobs.where((job) {
          return job.status != TransferStatus.completed &&
              job.status != TransferStatus.failed &&
              job.status != TransferStatus.cancelled;
        }).toList();

    if (activeTransfers.isEmpty) {
      await _backgroundTransferService.stop();
      return;
    }

    final lead = activeTransfers.first;
    final percent = (lead.progress * 100).clamp(0, 100).toStringAsFixed(0);
    await _backgroundTransferService.showTransferNotification(
      title: 'BlueShare transfer in progress',
      text: '${lead.fileName} - $percent%',
    );
  }

  TransferJob? _jobById(String jobId) {
    final index = _jobs.indexWhere((job) => job.id == jobId);
    if (index == -1) {
      return null;
    }
    return _jobs[index];
  }

  void _enqueueDeliveryJob({
    required _MeshTransferRecord record,
    required String peerAddress,
    required String peerName,
    required int hopCount,
    required bool isRelay,
    String? sourceAddress,
    String? sourceName,
    String? statusDetail,
  }) {
    if (record.deliveredPeers.contains(peerAddress) ||
        _hasPendingDelivery(record.transferId, peerAddress)) {
      return;
    }

    final job = TransferJob(
      id: _uuid.v4(),
      transferId: record.transferId,
      fileName: record.fileName,
      filePath: record.filePath,
      remoteAddress: peerAddress,
      remoteName: peerName,
      mimeType: record.mimeType,
      direction: TransferDirection.outgoing,
      totalBytes: record.totalBytes,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      hopCount: hopCount,
      isRelay: isRelay,
      originNode: record.originNode,
      sourceAddress: sourceAddress,
      sourceName: sourceName,
      forwardedToCount: record.deliveredPeers.length,
      statusDetail: statusDetail,
    );
    _jobs.add(job);
    if (isRelay) {
      unawaited(_reportMeshProgressIfNeeded(job));
    }
  }

  bool _hasPendingDelivery(String transferId, String address) {
    return _jobs.any(
      (job) =>
          job.direction == TransferDirection.outgoing &&
          !job.isRemoteTelemetry &&
          job.transferId == transferId &&
          job.remoteAddress == address &&
          job.status != TransferStatus.completed &&
          job.status != TransferStatus.cancelled &&
          job.status != TransferStatus.failed,
    );
  }

  void _upsertIncomingJob({
    required String transferId,
    required String fileName,
    required String filePath,
    required String remoteAddress,
    required int totalBytes,
    required String? mimeType,
    required int totalChunks,
    required int hopCount,
    required String? originNode,
    required String? sourceAddress,
    required String? sourceName,
  }) {
    final existingIndex = _jobs.indexWhere((job) => job.id == transferId);
    final job = TransferJob(
      id: transferId,
      transferId: transferId,
      fileName: fileName,
      filePath: filePath,
      remoteAddress: remoteAddress,
      remoteName: remoteAddress,
      direction: TransferDirection.incoming,
      totalBytes: totalBytes,
      mimeType: mimeType,
      status: TransferStatus.receiving,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalChunks: totalChunks,
      hopCount: hopCount,
      originNode: originNode,
      sourceAddress: sourceAddress,
      sourceName: sourceName,
      statusDetail: 'Receiving from ${sourceName ?? remoteAddress}.',
    );

    if (existingIndex == -1) {
      _jobs.add(job);
    } else {
      _jobs[existingIndex] = job;
    }
    _emitJobs();
  }

  Future<void> _markDeliveryComplete(
    String jobId, {
    required int bytesTransferred,
    required String detail,
  }) async {
    final job = _jobById(jobId);
    if (job == null) {
      return;
    }

    _replaceJob(
      jobId,
      (current) => current.copyWith(
        status: TransferStatus.completed,
        bytesTransferred: bytesTransferred,
        completedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        forwardedToCount:
            _meshTransfers[current.transferId]?.deliveredPeers.length ?? 0,
        statusDetail: detail,
      ),
      reportUpstream: true,
    );
    await _persistHistoryFor(jobId);
    _updateForwardCounts(job.transferId);
  }

  void _updateForwardCounts(String transferId) {
    final deliveredCount =
        _meshTransfers[transferId]?.deliveredPeers.length ?? 0;
    var changed = false;
    for (var index = 0; index < _jobs.length; index++) {
      final job = _jobs[index];
      if (job.transferId != transferId ||
          job.forwardedToCount == deliveredCount) {
        continue;
      }
      _jobs[index] = job.copyWith(forwardedToCount: deliveredCount);
      changed = true;
    }
    if (changed) {
      _emitJobs();
    }
  }

  Future<void> _deferTransfer(String jobId, String message) async {
    _replaceJob(
      jobId,
      (job) => job.copyWith(
        status: TransferStatus.waitingForPeer,
        updatedAt: DateTime.now(),
        statusDetail: message,
      ),
      reportUpstream: true,
    );
    await _refreshForegroundState();
  }

  Future<void> _failTransfer(String jobId, String message) async {
    _replaceJob(
      jobId,
      (job) => job.copyWith(
        status: TransferStatus.failed,
        errorMessage: message,
        updatedAt: DateTime.now(),
        completedAt: DateTime.now(),
      ),
      reportUpstream: true,
    );
    await _persistHistoryFor(jobId);
    await _refreshForegroundState();
  }

  Future<void> _cancelTransferByTransferId(String transferId) async {
    final incoming = _incomingSessions.remove(transferId);
    if (incoming != null) {
      final tempFile = File(incoming.tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
    final job = _jobById(transferId);
    if (job != null) {
      await cancel(job.id);
    }
  }

  Future<void> _failTransferByTransferId(
    String transferId,
    String message,
  ) async {
    final matchingJobs = _jobs
        .where((job) => job.transferId == transferId)
        .map((job) => job.id);
    for (final jobId in matchingJobs.toList()) {
      await _failTransfer(jobId, message);
    }
  }

  bool _shouldDeferFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('timed out') ||
        message.contains('connection') ||
        message.contains('disconnected') ||
        message.contains('socket') ||
        message.contains('broken pipe') ||
        message.contains('bluetooth write failed') ||
        message.contains('unable to send protocol message') ||
        message.contains('send failed') ||
        message.contains('send_failed') ||
        message.contains('no active bluetooth socket') ||
        message.contains('unknown transfer');
  }

  void _reactivateRetryableJobs(String address) {
    var changed = false;
    for (var index = 0; index < _jobs.length; index++) {
      final job = _jobs[index];
      final retryableFailure =
          job.status == TransferStatus.failed &&
          _shouldDeferFailure(job.errorMessage ?? job.statusDetail ?? '');
      if (job.remoteAddress != address ||
          (job.status != TransferStatus.waitingForPeer && !retryableFailure)) {
        continue;
      }
      _jobs[index] = job.copyWith(
        status: TransferStatus.queued,
        updatedAt: DateTime.now(),
        clearErrorMessage: true,
        clearStatusDetail: true,
      );
      changed = true;
      unawaited(_reportMeshProgressIfNeeded(_jobs[index]));
    }
    if (changed) {
      _emitJobs();
      unawaited(_processQueue());
    }
  }

  Future<void> _refreshTuning() async {
    _tuning = await _settingsRepository.loadMeshTransferTuning();
  }

  Future<void> _refreshSecuritySettings() async {
    _securitySettings = await _settingsRepository.loadMeshSecuritySettings();
    _transferCryptoService.updateSharedSecret(_securitySettings.passkey);
  }

  Future<String?> _signOfferPayload(Map<String, dynamic> payload) {
    return _transferCryptoService.signPayload(
      _offerPayloadForSignature(payload),
    );
  }

  Future<String?> _validateOfferSecurity(Map<String, dynamic> payload) async {
    final securityMode = payload['securityMode'] as String? ?? 'open';
    final encrypted = payload['encrypted'] as bool? ?? false;
    if (_securitySettings.isEnabled) {
      if (securityMode != 'passkey') {
        return 'This device only accepts passkey-protected BlueShare transfers.';
      }
      if (!encrypted) {
        return 'Passkey-protected transfers must use encrypted payloads.';
      }
      final verified = await _transferCryptoService.verifyPayload(
        payload: _offerPayloadForSignature(payload),
        signature: payload['authorization'] as String?,
      );
      if (!verified) {
        return 'Mesh passkey verification failed for this transfer.';
      }
      return null;
    }

    if (securityMode == 'passkey') {
      return 'Configure the same mesh passkey on this device to accept secure transfers.';
    }

    return null;
  }

  Map<String, dynamic> _offerPayloadForSignature(Map<String, dynamic> payload) {
    return <String, dynamic>{
      'transferId': payload['transferId'],
      'version': payload['version'],
      'fileName': payload['fileName'],
      'fileSize': payload['fileSize'],
      'mimeType': payload['mimeType'],
      'checksum': payload['checksum'],
      'totalChunks': payload['totalChunks'],
      'encrypted': payload['encrypted'],
      'originNode': payload['originNode'],
      'previousHop': payload['previousHop'],
      'hopCount': payload['hopCount'],
      'securityMode': payload['securityMode'],
    };
  }

  Future<void> _reportMeshProgressIfNeeded(TransferJob job) async {
    if (!_shouldReportUpstream(job)) {
      return;
    }

    final record = _meshTransfers[job.transferId];
    final upstreamAddress = record?.receivedFrom;
    if (upstreamAddress == null || upstreamAddress.isEmpty) {
      return;
    }

    try {
      await _safeSend(
        address: upstreamAddress,
        message: ProtocolMessage(
          type: ProtocolMessageType.meshReport,
          payload: {
            'transferId': job.transferId,
            'fileName': job.fileName,
            'nodeAddress': job.remoteAddress,
            'nodeName': job.remoteName,
            'status': job.status.name,
            'hopCount': job.hopCount,
            'bytesTransferred': job.bytesTransferred,
            'totalBytes': job.totalBytes,
            'isRelay': job.isRelay,
            'sourceAddress': job.sourceAddress,
            'sourceName': job.sourceName,
            'originNode': job.originNode,
            'forwardedToCount': job.forwardedToCount,
            'statusDetail': job.statusDetail,
            'errorMessage': job.errorMessage,
            'updatedAt': (job.updatedAt ?? DateTime.now()).toIso8601String(),
          },
        ),
      );
    } catch (_) {
      // Topology telemetry is best-effort and should not block the file path.
    }
  }

  bool _shouldReportUpstream(TransferJob job) {
    if (!job.isRelay ||
        job.isRemoteTelemetry ||
        job.direction != TransferDirection.outgoing) {
      return false;
    }
    final record = _meshTransfers[job.transferId];
    return record != null &&
        !record.isLocalOrigin &&
        record.receivedFrom != null &&
        record.receivedFrom!.isNotEmpty;
  }

  void _upsertMeshReportJob({
    required String transferId,
    required Map<String, dynamic> payload,
  }) {
    final nodeAddress = payload['nodeAddress'] as String?;
    if (nodeAddress == null || nodeAddress.trim().isEmpty) {
      return;
    }

    final hopCount = payload['hopCount'] as int? ?? 0;
    final matchingIndex = _jobs.indexWhere(
      (job) =>
          job.transferId == transferId &&
          job.remoteAddress == nodeAddress &&
          job.hopCount == hopCount &&
          job.direction == TransferDirection.outgoing,
    );
    final status = _transferStatusFromName(payload['status'] as String?);
    final updatedAt =
        DateTime.tryParse(payload['updatedAt'] as String? ?? '') ??
        DateTime.now();

    if (matchingIndex == -1) {
      _jobs.add(
        TransferJob(
          id: _telemetryJobId(transferId, nodeAddress, hopCount),
          transferId: transferId,
          fileName: payload['fileName'] as String? ?? 'Mesh delivery',
          filePath: '',
          remoteAddress: nodeAddress,
          remoteName: payload['nodeName'] as String?,
          direction: TransferDirection.outgoing,
          totalBytes: payload['totalBytes'] as int? ?? 0,
          bytesTransferred: payload['bytesTransferred'] as int? ?? 0,
          status: status,
          startedAt: updatedAt,
          updatedAt: updatedAt,
          sourceAddress: payload['sourceAddress'] as String?,
          sourceName: payload['sourceName'] as String?,
          originNode: payload['originNode'] as String?,
          hopCount: hopCount,
          forwardedToCount: payload['forwardedToCount'] as int? ?? 0,
          isRelay: payload['isRelay'] as bool? ?? true,
          isRemoteTelemetry: true,
          statusDetail: payload['statusDetail'] as String?,
          errorMessage: payload['errorMessage'] as String?,
        ),
      );
      _emitJobs();
      return;
    }

    final current = _jobs[matchingIndex];
    _jobs[matchingIndex] = current.copyWith(
      fileName: payload['fileName'] as String? ?? current.fileName,
      remoteName: payload['nodeName'] as String? ?? current.remoteName,
      totalBytes: payload['totalBytes'] as int? ?? current.totalBytes,
      bytesTransferred:
          payload['bytesTransferred'] as int? ?? current.bytesTransferred,
      status: status,
      updatedAt: updatedAt,
      sourceAddress:
          payload['sourceAddress'] as String? ?? current.sourceAddress,
      sourceName: payload['sourceName'] as String? ?? current.sourceName,
      originNode: payload['originNode'] as String? ?? current.originNode,
      forwardedToCount:
          payload['forwardedToCount'] as int? ?? current.forwardedToCount,
      isRelay: payload['isRelay'] as bool? ?? current.isRelay,
      isRemoteTelemetry: true,
      statusDetail: payload['statusDetail'] as String? ?? current.statusDetail,
      errorMessage: payload['errorMessage'] as String?,
      clearErrorMessage: payload['errorMessage'] == null,
    );
    _emitJobs();
  }

  Future<void> _forwardMeshReportUpstream({
    required String transferId,
    required Map<String, dynamic> payload,
    required String receivedFrom,
  }) async {
    final record = _meshTransfers[transferId];
    final upstreamAddress = record?.receivedFrom;
    if (record == null ||
        record.isLocalOrigin ||
        upstreamAddress == null ||
        upstreamAddress.isEmpty ||
        upstreamAddress == receivedFrom) {
      return;
    }

    try {
      await _safeSend(
        address: upstreamAddress,
        message: ProtocolMessage(
          type: ProtocolMessageType.meshReport,
          payload: payload,
        ),
      );
    } catch (_) {
      // Forwarded telemetry should stay non-blocking.
    }
  }

  TransferStatus _transferStatusFromName(String? value) {
    return TransferStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TransferStatus.queued,
    );
  }

  String _telemetryJobId(String transferId, String address, int hopCount) {
    return 'telemetry|$transferId|$address|$hopCount';
  }
}

class _OutgoingDeliverySession {
  _OutgoingDeliverySession({
    required this.jobId,
    required this.transferId,
    required this.remoteAddress,
    required this.checksum,
    required this.totalChunks,
  });

  final String jobId;
  final String transferId;
  final String remoteAddress;
  final String checksum;
  final int totalChunks;
  int acknowledgedChunks = 0;
  int retryCount = 0;
  bool cancelled = false;
  Completer<void>? _pauseCompleter;

  bool get paused => _pauseCompleter != null;

  void pause() {
    _pauseCompleter ??= Completer<void>();
  }

  void resume() {
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  Future<void> waitIfPaused() async {
    final completer = _pauseCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  void cancel() {
    cancelled = true;
    resume();
  }
}

class _IncomingTransferSession {
  _IncomingTransferSession({
    required this.transferId,
    required this.fileName,
    required this.expectedChunks,
    required this.expectedChecksum,
    required this.remoteAddress,
    required this.tempPath,
    required this.mimeType,
    required this.hopCount,
    required this.originNode,
    required this.senderNode,
    required this.requiresSecureTransfer,
  });

  final String transferId;
  final String fileName;
  final int expectedChunks;
  final String expectedChecksum;
  final String remoteAddress;
  final String tempPath;
  final String? mimeType;
  final int hopCount;
  final String? originNode;
  final String? senderNode;
  final bool requiresSecureTransfer;
  int receivedChunks = 0;
  int bytesTransferred = 0;
}

class _MeshTransferRecord {
  _MeshTransferRecord({
    required this.transferId,
    required this.fileName,
    required this.filePath,
    required this.mimeType,
    required this.totalBytes,
    this.checksum,
    this.totalChunks = 0,
    required this.originNode,
    required this.hopCount,
    this.receivedFrom,
    this.isLocalOrigin = false,
  });

  final String transferId;
  final String fileName;
  String filePath;
  final String? mimeType;
  int totalBytes;
  String? checksum;
  int totalChunks;
  final String originNode;
  int hopCount;
  String? receivedFrom;
  final bool isLocalOrigin;
  bool isComplete = false;
  final Set<String> deliveredPeers = <String>{};
}
