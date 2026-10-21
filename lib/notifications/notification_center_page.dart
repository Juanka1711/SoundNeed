import 'dart:async';

import 'package:flutter/material.dart';

import '../music_player.dart';
import '../services/artwork_palette.dart';
import '../services/notification_service.dart';

enum _ReadFilter { all, unread, read }

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    super.key,
    required this.service,
    required this.player,
    required this.palette,
    required this.onOpenDestination,
  });

  final NotificationService service;
  final MusicPlayerController player;
  final ArtworkPalette palette;
  final ValueChanged<SoundNeedNotification> onOpenDestination;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  NotificationCategory? _category;
  _ReadFilter _readFilter = _ReadFilter.all;
  late ArtworkPalette _palette;
  int? _paletteSongId;
  int _paletteRequest = 0;

  @override
  void initState() {
    super.initState();
    _palette = widget.palette;
    _paletteSongId = widget.player.currentSong?.id;
    widget.service.addListener(_refresh);
    widget.player.addListener(_onPlayerChanged);
    widget.service.initialize();
    unawaited(_loadPalette(widget.player.currentSong));
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    widget.player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onPlayerChanged() {
    final song = widget.player.currentSong;
    if (song?.id == _paletteSongId) return;
    _paletteSongId = song?.id;
    unawaited(_loadPalette(song));
  }

  Future<void> _loadPalette(Song? song) async {
    final request = ++_paletteRequest;
    if (song == null) {
      if (mounted) setState(() => _palette = ArtworkPalette.neutral);
      return;
    }
    try {
      final artwork = await widget.player.loadArtwork(song);
      final palette = artwork == null
          ? ArtworkPalette.neutral
          : await ArtworkPaletteExtractor.fromBytes(artwork);
      if (!mounted || request != _paletteRequest) return;
      setState(() => _palette = palette);
    } catch (_) {
      if (!mounted || request != _paletteRequest) return;
      setState(() => _palette = ArtworkPalette.neutral);
    }
  }

  Color _categoryAccent(NotificationCategory category) {
    // Use one hue throughout the page; the category is identified by its label.
    return _palette.primary;
  }

  List<SoundNeedNotification> _filteredRecords() => widget.service.records
      .where((record) {
        if (_category != null && record.category != _category) return false;
        return switch (_readFilter) {
          _ReadFilter.all => true,
          _ReadFilter.unread => !record.isRead,
          _ReadFilter.read => record.isRead,
        };
      })
      .toList(growable: false);

  Future<void> _openRecord(SoundNeedNotification record) async {
    await widget.service.markRead(record.id);
    final destination = record.destination;
    if (!mounted ||
        destination == null ||
        !NotificationService.isValidDestination(destination)) {
      return;
    }
    widget.onOpenDestination(record);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final records = _filteredRecords();
    final background = _palette.isArtworkDerived
        ? Color.lerp(_palette.dark, const Color(0xff0b0b12), .58)!
        : const Color(0xff0b0b12);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _palette.primary.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: _palette.primary.withValues(alpha: .28),
                ),
              ),
              child: Text(
                '${service.unreadCount} sin leer',
                style: TextStyle(
                  fontSize: 12,
                  color: _palette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (service.unreadCount > 0)
            IconButton(
              tooltip: 'Marcar todas como leídas',
              onPressed: service.markAllRead,
              icon: Icon(Icons.done_all_rounded, color: _palette.primary),
            ),
          if (service.records.isNotEmpty)
            IconButton(
              tooltip: 'Eliminar historial',
              onPressed: service.deleteAll,
              icon: Icon(Icons.delete_sweep_outlined, color: _palette.primary),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: service.isLoading && service.records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : service.error != null && service.records.isEmpty
          ? _errorState(service.error!)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _activityHeader(service),
                _filters(),
                Expanded(
                  child: records.isEmpty
                      ? _emptyState
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                          itemCount: records.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 9),
                          itemBuilder: (context, index) =>
                              _notificationTile(records[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _activityHeader(NotificationService service) => Container(
    margin: const EdgeInsets.fromLTRB(16, 7, 16, 8),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _palette.primary.withValues(alpha: .20),
          _palette.primary.withValues(alpha: .07),
          const Color(0xff171722),
        ],
      ),
      border: Border.all(color: _palette.primary.withValues(alpha: .24)),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _palette.primary.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            Icons.notifications_active_rounded,
            color: _palette.primary,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu actividad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                service.records.isEmpty
                    ? 'Tus avisos importantes aparecerán aquí'
                    : '${service.records.length} avisos · ${service.unreadCount} sin leer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 5, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterGroupLabel('TIPO DE AVISO'),
        const SizedBox(height: 7),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: NotificationCategory.values.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _filterChip(
                  'Todas',
                  _category == null,
                  _palette.primary,
                  () {
                    setState(() => _category = null);
                  },
                );
              }
              final category = NotificationCategory.values[index - 1];
              return _filterChip(
                category.label,
                _category == category,
                _categoryAccent(category),
                () => setState(() => _category = category),
              );
            },
          ),
        ),
        const SizedBox(height: 11),
        _filterGroupLabel('ESTADO DE LECTURA'),
        const SizedBox(height: 7),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) => switch (index) {
              0 => _filterChip(
                'Todas',
                _readFilter == _ReadFilter.all,
                _palette.primary,
                () => setState(() => _readFilter = _ReadFilter.all),
              ),
              1 => _filterChip(
                'Sin leer',
                _readFilter == _ReadFilter.unread,
                _palette.primary,
                () => setState(() => _readFilter = _ReadFilter.unread),
              ),
              _ => _filterChip(
                'Leídas',
                _readFilter == _ReadFilter.read,
                _palette.primary,
                () => setState(() => _readFilter = _ReadFilter.read),
              ),
            },
          ),
        ),
      ],
    ),
  );

  Widget _filterGroupLabel(String text) => Text(
    text,
    style: TextStyle(
      color: _palette.primary.withValues(alpha: .9),
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    ),
  );

  Widget _filterChip(
    String label,
    bool selected,
    Color accent,
    VoidCallback onPressed,
  ) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onPressed(),
    showCheckmark: false,
    backgroundColor: const Color(0xff1d1d2b),
    selectedColor: accent.withValues(alpha: .28),
    labelStyle: TextStyle(
      color: selected ? Colors.white : Colors.white70,
      fontSize: 12,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    ),
    side: BorderSide(
      color: selected ? accent.withValues(alpha: .75) : Colors.white10,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 3),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _notificationTile(SoundNeedNotification record) {
    final accent = _categoryAccent(record.category);
    final cardColor = Color.lerp(
      const Color(0xff171722),
      accent,
      record.isRead ? .035 : .105,
    )!;
    final canOpen =
        record.destination != null &&
        NotificationService.isValidDestination(record.destination!);
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xffef4444).withValues(alpha: .18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
        ),
      ),
      onDismissed: (_) => widget.service.delete(record.id),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openRecord(record),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: accent.withValues(alpha: record.isRead ? .08 : .24),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .17),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(record.category.icon, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: record.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                              ),
                            ),
                            if (!record.isRead)
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _palette.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        if (record.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            record.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xffa1a1aa),
                              height: 1.3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Text(
                              record.category.label,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _relativeTime(record.updatedAt),
                              style: const TextStyle(
                                color: Color(0xff777783),
                                fontSize: 11,
                              ),
                            ),
                            if (record.status == NotificationStatus.failed) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'Falló',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (record.isOngoing) ...[
                              const SizedBox(width: 8),
                              const Text(
                                'En curso',
                                style: TextStyle(
                                  color: Color(0xfffbbf24),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (record.isOngoing && record.progress != null) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: record.progress! / 100,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(8),
                            backgroundColor: Colors.white10,
                            color: _palette.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones',
                    color: Color.lerp(const Color(0xff1d1d2b), accent, .24),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: _palette.primary,
                    ),
                    onSelected: (value) {
                      if (value == 'read') {
                        widget.service.markRead(
                          record.id,
                          isRead: !record.isRead,
                        );
                      } else if (value == 'delete') {
                        widget.service.delete(record.id);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'read',
                        child: Text(
                          record.isRead ? 'Marcar sin leer' : 'Marcar leída',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar'),
                      ),
                    ],
                  ),
                  if (canOpen)
                    const Padding(
                      padding: EdgeInsets.only(top: 10, right: 3),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget get _emptyState => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 48,
            color: _palette.primary.withValues(alpha: .78),
          ),
          const SizedBox(height: 12),
          Text(
            _readFilter == _ReadFilter.unread
                ? 'No tienes avisos sin leer'
                : 'Todavía no hay notificaciones',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 5),
          const Text(
            'Aquí aparecerán las descargas, importaciones y avisos importantes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff8b8b96)),
          ),
        ],
      ),
    ),
  );

  Widget _errorState(String error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sync_problem_rounded,
            size: 42,
            color: Colors.orangeAccent,
          ),
          const SizedBox(height: 12),
          const Text('No se pudo cargar el historial'),
          const SizedBox(height: 6),
          Text(
            error,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff8b8b96)),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: widget.service.retryInitialization,
            style: FilledButton.styleFrom(
              backgroundColor: _palette.primary.withValues(alpha: .2),
              foregroundColor: _palette.primary,
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 60) return 'Ahora';
    if (difference.inMinutes < 60) return 'Hace ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Hace ${difference.inHours} h';
    if (difference.inDays < 7) return 'Hace ${difference.inDays} d';
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}
