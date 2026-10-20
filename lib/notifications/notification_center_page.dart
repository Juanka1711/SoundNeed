import 'package:flutter/material.dart';

import '../services/notification_service.dart';

enum _ReadFilter { all, unread, read }

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    super.key,
    required this.service,
    required this.onOpenDestination,
  });

  final NotificationService service;
  final ValueChanged<String> onOpenDestination;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  NotificationCategory? _category;
  _ReadFilter _readFilter = _ReadFilter.all;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
    widget.service.initialize();
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    widget.onOpenDestination(destination);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final records = _filteredRecords();
    return Scaffold(
      backgroundColor: const Color(0xff0b0b12),
      appBar: AppBar(
        backgroundColor: const Color(0xff0b0b12),
        title: const Text(
          'Notificaciones',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xff8b5cf6).withValues(alpha: .16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${service.unreadCount} sin leer',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xffc4b5fd),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (service.unreadCount > 0)
            IconButton(
              tooltip: 'Marcar todas como leídas',
              onPressed: service.markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          if (service.records.isNotEmpty)
            IconButton(
              tooltip: 'Eliminar historial',
              onPressed: service.deleteAll,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: service.isLoading && service.records.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xffb99aff)),
            )
          : service.error != null && service.records.isEmpty
          ? _errorState(service.error!)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip('Todas', _category == null, () {
                setState(() => _category = null);
              }),
              for (final category in NotificationCategory.values)
                _filterChip(category.label, _category == category, () {
                  setState(() => _category = category);
                }),
            ],
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 38,
          child: Row(
            children: [
              _filterChip('Todas', _readFilter == _ReadFilter.all, () {
                setState(() => _readFilter = _ReadFilter.all);
              }),
              _filterChip('Sin leer', _readFilter == _ReadFilter.unread, () {
                setState(() => _readFilter = _ReadFilter.unread);
              }),
              _filterChip('Leídas', _readFilter == _ReadFilter.read, () {
                setState(() => _readFilter = _ReadFilter.read);
              }),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterChip(String label, bool selected, VoidCallback onPressed) =>
      Padding(
        padding: const EdgeInsets.only(right: 7),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onPressed(),
          showCheckmark: false,
          backgroundColor: const Color(0xff1d1d2b),
          selectedColor: const Color(0xff8b5cf6).withValues(alpha: .28),
          labelStyle: TextStyle(
            color: selected ? const Color(0xffe9ddff) : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          side: BorderSide(
            color: selected ? const Color(0xff8b5cf6) : Colors.white10,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  Widget _notificationTile(SoundNeedNotification record) {
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
        color: record.isRead
            ? const Color(0xff171722)
            : const Color(0xff201d31),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _openRecord(record),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xff8b5cf6).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    record.category.icon,
                    color: const Color(0xffc4b5fd),
                  ),
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
                              decoration: const BoxDecoration(
                                color: Color(0xffb99aff),
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
                            style: const TextStyle(
                              color: Color(0xffc4b5fd),
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
                          color: const Color(0xffb99aff),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white54,
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
    );
  }

  Widget get _emptyState => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_rounded,
            size: 48,
            color: Colors.white30,
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
