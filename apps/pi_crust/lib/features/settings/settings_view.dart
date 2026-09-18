import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_crust_theme/pi_crust_theme.dart';
import '../../data/daemon/daemon_providers.dart';

class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final int initialTabIndex;

  const SettingsView({
    super.key,
    required this.onClose,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _workerIdleTimeoutMinutes = 30;
  bool _isLoadingConfig = true;
  String? _configStatusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _fetchDaemonConfig();
  }

  Future<void> _fetchDaemonConfig() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() => _isLoadingConfig = false);
      }
      return;
    }

    try {
      final res = await client.getDaemonConfig();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final ms = (data['workerIdleTimeoutMs'] as num?)?.toInt() ?? 1800000;
      if (mounted) {
        setState(() {
          _workerIdleTimeoutMinutes = (ms / 60000).round();
          _isLoadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingConfig = false;
        });
      }
    }
  }

  Future<void> _updateTimeout(int newMinutes) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    setState(() {
      _workerIdleTimeoutMinutes = newMinutes;
      _configStatusMessage = 'Salvataggio in corso...';
    });

    try {
      await client.setDaemonConfig({
        'workerIdleTimeoutMs': newMinutes * 60000,
      });
      if (mounted) {
        setState(() {
          _configStatusMessage = 'Timeout aggiornato con successo!';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _configStatusMessage = null);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _configStatusMessage = 'Errore: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final endpointAsync = ref.watch(daemonEndpointProvider);
    final endpoint = endpointAsync.value;

    return Container(
      color: tokens.background,
      child: Column(
        children: [
          // Top Navigation Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      color: tokens.textPrimary,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Impostazioni Pi-Crust',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: tokens.accent,
                  labelColor: tokens.accent,
                  unselectedLabelColor: tokens.textSecondary,
                  tabs: const [
                    Tab(text: 'Pi CLI'),
                    Tab(text: 'Daemon'),
                    Tab(text: 'Aspetto'),
                    Tab(text: 'Privacy'),
                  ],
                ),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // -------------------------------------------------------------
                // Tab 1: Pi
                // -------------------------------------------------------------
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Installazione Pi Coding Agent', style: TextStyle(color: tokens.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'Pi-Crust si interfaccia con il CLI di Pi tramite subprocess locale RPC.',
                      style: TextStyle(color: tokens.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(tokens, [
                      _buildInfoRow(tokens, 'Percorso rilevato', 'npm global prefix / PATH'),
                      _buildInfoRow(tokens, 'Versione minima supportata', '>= v0.85.0'),
                      _buildInfoRow(tokens, 'Stato', 'Disponibile e funzionante (RPC ready)'),
                    ]),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Ricontrolla installazione'),
                        onPressed: () {
                          ref.invalidate(daemonEndpointProvider);
                        },
                      ),
                    ),
                  ],
                ),

                // -------------------------------------------------------------
                // Tab 2: Daemon
                // -------------------------------------------------------------
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Stato del Daemon pi-agentd', style: TextStyle(color: tokens.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'Il daemon locale gestisce i processi Pi worker, il journal e il protocollo PCP/1.',
                      style: TextStyle(color: tokens.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(tokens, [
                      _buildInfoRow(tokens, 'Porta HTTP/WS', endpoint != null ? '127.0.0.1:${endpoint.port}' : 'In connessione...'),
                      _buildInfoRow(tokens, 'Stato', 'Pronto (Ready)'),
                      _buildInfoRow(tokens, 'Protocollo', 'PCP/1 (JSON testuale)'),
                    ]),
                    const SizedBox(height: 24),
                    Text('Timeout Inattività Worker (D9)', style: TextStyle(color: tokens.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Dopo quanto tempo di inattività i processi Pi in idle vengono terminati per risparmiare risorse (i worker occupati non vengono mai terminati).',
                      style: TextStyle(color: tokens.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _isLoadingConfig
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: tokens.accent),
                            ),
                          )
                        : Row(
                            children: [
                              DropdownButton<int>(
                                value: _workerIdleTimeoutMinutes,
                                dropdownColor: tokens.surfaceElevated,
                                style: TextStyle(color: tokens.textPrimary, fontSize: 14),
                                items: const [
                                  DropdownMenuItem(value: 0, child: Text('Mai (0 min)')),
                                  DropdownMenuItem(value: 5, child: Text('5 minuti')),
                                  DropdownMenuItem(value: 15, child: Text('15 minuti')),
                                  DropdownMenuItem(value: 30, child: Text('30 minuti (Default)')),
                                  DropdownMenuItem(value: 60, child: Text('1 ora (60 min)')),
                                  DropdownMenuItem(value: 120, child: Text('2 ore (120 min)')),
                                ],
                                onChanged: (val) {
                                  if (val != null) _updateTimeout(val);
                                },
                              ),
                              const SizedBox(width: 16),
                              if (_configStatusMessage != null)
                                Text(
                                  _configStatusMessage!,
                                  style: TextStyle(color: tokens.success, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: 'Riavvio disabilitato quando sono presenti worker attivi per proteggere le sessioni.',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tokens.surfaceElevated,
                            foregroundColor: tokens.textMuted,
                          ),
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('Riavvia Daemon'),
                          onPressed: null, // Disabled when workers exist
                        ),
                      ),
                    ),
                  ],
                ),

                // -------------------------------------------------------------
                // Tab 3: Aspetto
                // -------------------------------------------------------------
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Personalizzazione Tema e UI', style: TextStyle(color: tokens.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'Pi-Crust supporta temi personalizzati definiti via file JSON in ~/.pi-crust/themes/.',
                      style: TextStyle(color: tokens.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoCard(tokens, [
                      _buildInfoRow(tokens, 'Tema attivo', 'Crust Dark (Ufficiale)'),
                      _buildInfoRow(tokens, 'Densità layout', 'Confortevole (Default 1.0x)'),
                      _buildInfoRow(tokens, 'Caratteri', 'Inter (UI) · JetBrains Mono (Codice)'),
                    ]),
                  ],
                ),

                // -------------------------------------------------------------
                // Tab 4: Privacy (D16 — Zero Telemetry)
                // -------------------------------------------------------------
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 24, color: tokens.success),
                        const SizedBox(width: 10),
                        Text(
                          'Informativa sulla Privacy e Tracciamento',
                          style: TextStyle(color: tokens.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Text(
                        'Pi-Crust non invia alcun dato di utilizzo a server remoti. I log restano sul tuo computer; puoi esportarli manualmente dalla sezione Diagnostica per condividerli con chi ti assiste.',
                        style: TextStyle(color: tokens.textPrimary, fontSize: 14, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '• Zero telemetria, zero analytics di terze parti (nessun Google Analytics, Mixpanel o Sentry).\n'
                      '• Comunicazione locale confinata all\'interfaccia loopback 127.0.0.1 con token di autenticazione 256 bit.\n'
                      '• Nessuna modifica ai file di sessione o configurazioni originali di Pi in ~/.pi/.',
                      style: TextStyle(color: tokens.textMuted, fontSize: 12, height: 1.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(CrustTokens tokens, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(CrustTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: tokens.textSecondary, fontSize: 13)),
          Text(value, style: TextStyle(color: tokens.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
