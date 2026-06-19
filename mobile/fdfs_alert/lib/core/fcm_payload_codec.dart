import 'dart:convert';

/// JSON payload for local notification taps (movie_id + watcher_id; no booking_url).
abstract final class FcmPayloadCodec {
  static String encode(Map<String, String> data) => jsonEncode(data);

  static Map<String, String> decode(String? payload) {
    if (payload == null || payload.isEmpty) return {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
      }
    } catch (_) {
      /* legacy: treat non-JSON as movie_id slug */
      if (!payload.startsWith('http')) {
        return {'movie_id': payload};
      }
    }
    return {};
  }
}
