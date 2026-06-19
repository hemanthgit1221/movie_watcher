import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive/hive.dart';

import '../../core/storage/hive_boxes.dart';
import 'inbox_item.dart';

const _boxName = 'moovaa_inbox';
const _maxItems = 50;

class InboxStore {
  Future<Box<Map>?> _box() => openMoovaaBox<Map>(_boxName);

  Future<List<InboxItem>> list() async {
    final box = await _box();
    if (box == null) return [];
    return box.values
        .map((v) => InboxItem.fromMap(Map<dynamic, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.receivedAtIso.compareTo(a.receivedAtIso));
  }

  Future<int> unreadCount() async {
    final items = await list();
    return items.where((i) => !i.read).length;
  }

  Future<void> appendFromRemoteMessage(RemoteMessage message) async {
    final data = _stringifyData(message.data);
    final title = message.notification?.title ??
        data['movie'] ??
        'Tickets OPEN';
    final body = message.notification?.body ?? _defaultBody(data);
    await _append(title: title, body: body, data: data);
  }

  Future<void> appendFromDataMap(
    Map<String, String> data, {
    String? title,
    String? body,
  }) async {
    await _append(
      title: title ?? data['movie'] ?? 'Ticket alert',
      body: body ?? _defaultBody(data),
      data: data,
    );
  }

  static Map<String, String> _stringifyData(Map<String, dynamic> data) {
    return data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  String _defaultBody(Map<String, String> data) {
    final theatre = data['theatre'];
    final city = data['city'];
    if (theatre != null && city != null) {
      return '$theatre · $city';
    }
    return 'Booking may be open';
  }

  Future<void> _append({
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    final box = await _box();
    if (box == null) return;

    final watcherId = data['watcher_id'];
    if (watcherId != null) {
      for (final raw in box.values) {
        final m = Map<dynamic, dynamic>.from(raw);
        if (m['watcher_id'] == watcherId) return;
      }
    }

    final id = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final item = InboxItem(
      id: id,
      title: title,
      body: body,
      receivedAtIso: DateTime.now().toUtc().toIso8601String(),
      movieId: data['movie_id'],
      bookingUrl: data['booking_url'],
      theatre: data['theatre'],
      city: data['city'],
      watcherId: watcherId,
    );
    await box.put(id, item.toMap());

    final keys = box.keys.cast<String>().toList();
    if (keys.length > _maxItems) {
      final sorted = await list();
      for (var i = _maxItems; i < sorted.length; i++) {
        await box.delete(sorted[i].id);
      }
    }
  }

  Future<void> markReadByWatcherId(String watcherId) async {
    final items = await list();
    for (final item in items) {
      if (item.watcherId == watcherId && !item.read) {
        await markRead(item.id);
      }
    }
  }

  Future<void> markRead(String id) async {
    final box = await _box();
    if (box == null) return;
    final raw = box.get(id);
    if (raw == null) return;
    final item = InboxItem.fromMap(Map<dynamic, dynamic>.from(raw));
    await box.put(id, item.markRead().toMap());
  }

  Future<void> markAllRead() async {
    final box = await _box();
    if (box == null) return;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final item = InboxItem.fromMap(Map<dynamic, dynamic>.from(raw));
      if (!item.read) {
        await box.put(key, item.markRead().toMap());
      }
    }
  }
}
