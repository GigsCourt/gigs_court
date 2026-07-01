class CacheEntry<T> {
  final T data;
  final DateTime expiry;
  CacheEntry(this.data, this.expiry);
  bool get isExpired => DateTime.now().isAfter(expiry);
}

class CacheService {
  static final Map<String, CacheEntry> _store = {};

  static void set(String key, dynamic data, {Duration ttl = const Duration(minutes: 30)}) {
    _store[key] = CacheEntry(data, DateTime.now().add(ttl));
  }

  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry != null && !entry.isExpired) {
      return entry.data as T;
    }
    _store.remove(key);
    return null;
  }

  static void remove(String key) => _store.remove(key);
  static void clear() => _store.clear();

  static bool has(String key) {
    final entry = _store[key];
    return entry != null && !entry.isExpired;
  }
}