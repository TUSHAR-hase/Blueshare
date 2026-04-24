import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/mesh_security_settings.dart';
import '../../domain/entities/mesh_transfer_tuning.dart';
import '../providers/app_providers.dart';

class MeshSettingsScreen extends ConsumerStatefulWidget {
  const MeshSettingsScreen({super.key});

  @override
  ConsumerState<MeshSettingsScreen> createState() => _MeshSettingsScreenState();
}

class _MeshSettingsScreenState extends ConsumerState<MeshSettingsScreen> {
  MeshTransferTuning _tuning = const MeshTransferTuning();
  MeshSecuritySettings _security = const MeshSecuritySettings();
  late final TextEditingController _passkeyController;
  bool _loading = true;
  bool _saving = false;
  bool _showPasskey = false;

  @override
  void initState() {
    super.initState();
    _passkeyController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final tuning =
        await ref.read(settingsRepositoryProvider).loadMeshTransferTuning();
    final security =
        await ref.read(settingsRepositoryProvider).loadMeshSecuritySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _tuning = tuning;
      _security = security;
      _passkeyController.text = security.normalizedPasskey;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final security = MeshSecuritySettings(passkey: _passkeyController.text);
    await ref.read(settingsRepositoryProvider).saveMeshTransferTuning(_tuning);
    await ref
        .read(settingsRepositoryProvider)
        .saveMeshSecuritySettings(security);
    if (!mounted) {
      return;
    }
    setState(() {
      _security = security;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mesh settings saved. New transfers will use them.'),
      ),
    );
  }

  @override
  void dispose() {
    _passkeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Settings')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final cards = <Widget>[
                    _SecurityCard(
                      security: _security,
                      controller: _passkeyController,
                      showPasskey: _showPasskey,
                      onChanged:
                          (value) => setState(
                            () =>
                                _security = MeshSecuritySettings(
                                  passkey: value,
                                ),
                          ),
                      onToggleVisibility:
                          () => setState(() => _showPasskey = !_showPasskey),
                    ),
                    _SliderCard(
                      title: 'Parallel Wave Size',
                      value: _tuning.parallelOutgoingPerWave,
                      min: 1,
                      max: 12,
                      description:
                          'How many level-1 or relay deliveries can start at the same time.',
                      onChanged:
                          (value) => setState(
                            () =>
                                _tuning = _tuning.copyWith(
                                  parallelOutgoingPerWave: value,
                                ),
                          ),
                    ),
                    _SliderCard(
                      title: 'Chunk Retries',
                      value: _tuning.chunkRetries,
                      min: 1,
                      max: 6,
                      description:
                          'Retries for data chunk ACK failures on unstable links.',
                      onChanged:
                          (value) => setState(
                            () =>
                                _tuning = _tuning.copyWith(chunkRetries: value),
                          ),
                    ),
                    _SliderCard(
                      title: 'Control Retries',
                      value: _tuning.controlRetries,
                      min: 1,
                      max: 6,
                      description:
                          'Retries for offer and completion handshakes.',
                      onChanged:
                          (value) => setState(
                            () =>
                                _tuning = _tuning.copyWith(
                                  controlRetries: value,
                                ),
                          ),
                    ),
                    _SliderCard(
                      title: 'Reconnect Attempts',
                      value: _tuning.reconnectAttempts,
                      min: 1,
                      max: 10,
                      description:
                          'How many times the mesh should try to reconnect a peer.',
                      onChanged:
                          (value) => setState(
                            () =>
                                _tuning = _tuning.copyWith(
                                  reconnectAttempts: value,
                                ),
                          ),
                    ),
                    _SliderCard(
                      title: 'Retry Backoff',
                      value: _tuning.retryBackoffSeconds,
                      min: 1,
                      max: 10,
                      suffix: 's',
                      description:
                          'Delay between reconnect attempts and retry waves.',
                      onChanged:
                          (value) => setState(
                            () =>
                                _tuning = _tuning.copyWith(
                                  retryBackoffSeconds: value,
                                ),
                          ),
                    ),
                  ];

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      _IntroCard(tuning: _tuning),
                      const SizedBox(height: 16),
                      if (wide)
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children:
                              cards
                                  .map(
                                    (card) => SizedBox(
                                      width: (constraints.maxWidth - 56) / 2,
                                      child: card,
                                    ),
                                  )
                                  .toList(),
                        )
                      else
                        ...cards.expand(
                          (card) => <Widget>[card, const SizedBox(height: 16)],
                        ),
                    ],
                  );
                },
              ),
      bottomNavigationBar:
          _loading
              ? null
              : SafeArea(
                minimum: const EdgeInsets.all(20),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.save_rounded),
                  label: const Text('Save Settings'),
                ),
              ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.tuning});

  final MeshTransferTuning tuning;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Mesh Transfer Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Set the transport profile for production mesh delivery. Use a shared passkey on every device, then tune concurrency and retries for your Bluetooth environment.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                Chip(label: Text('Parallel ${tuning.parallelOutgoingPerWave}')),
                Chip(label: Text('Chunk retries ${tuning.chunkRetries}')),
                Chip(label: Text('Reconnect ${tuning.reconnectAttempts}')),
                Chip(label: Text('Backoff ${tuning.retryBackoffSeconds}s')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.security,
    required this.controller,
    required this.showPasskey,
    required this.onChanged,
    required this.onToggleVisibility,
  });

  final MeshSecuritySettings security;
  final TextEditingController controller;
  final bool showPasskey;
  final ValueChanged<String> onChanged;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    final enabled = security.isEnabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Mesh Security',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(enabled ? 'Passkey active' : 'Passkey required'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the same passkey on the master and every relay device. BlueShare signs transfer offers and encrypts chunks before a receiver accepts them.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              onChanged: onChanged,
              obscureText: !showPasskey,
              decoration: InputDecoration(
                labelText: 'Mesh passkey',
                hintText: 'Enter the shared production passkey',
                helperText:
                    'Leave blank only if you intentionally want an open test mesh.',
                suffixIcon: IconButton(
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    showPasskey
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                Chip(label: Text('Current ${security.maskedPasskey}')),
                const Chip(label: Text('Offer signing')),
                const Chip(label: Text('AES-256 chunk encryption')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.description,
    required this.onChanged,
    this.suffix = '',
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final String description;
  final ValueChanged<int> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text('$value$suffix')),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value$suffix',
              onChanged: (newValue) => onChanged(newValue.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[Text('$min$suffix'), Text('$max$suffix')],
            ),
          ],
        ),
      ),
    );
  }
}
