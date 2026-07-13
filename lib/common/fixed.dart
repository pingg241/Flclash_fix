import 'dart:collection';

import 'iterable.dart';

typedef ValueCallback<T> = T Function();

class FixedList<T> {
  final int maxLength;
  final ListQueue<T> _queue;
  List<T>? _snapshot;

  FixedList(this.maxLength, {List<T>? list}) : _queue = ListQueue<T>() {
    if (maxLength <= 0 || list == null || list.isEmpty) {
      return;
    }
    _queue.addAll(list.skip((list.length - maxLength).clamp(0, list.length)));
  }

  void add(T item) {
    if (maxLength <= 0) {
      return;
    }
    if (_queue.length == maxLength) {
      _queue.removeFirst();
    }
    _queue.addLast(item);
    _snapshot = null;
  }

  void clear() {
    if (_queue.isEmpty) {
      return;
    }
    _queue.clear();
    _snapshot = null;
  }

  /// Cached immutable snapshot for consumers.
  List<T> get list => _snapshot ??= List.unmodifiable(_queue);

  int get length => _queue.length;

  T operator [](int index) => _queue.elementAt(index);

  /// Shallow copy of the current items.
  FixedList<T> copyWith() {
    return FixedList(maxLength, list: list);
  }
}

class FixedMap<K, V> {
  int maxLength;
  late Map<K, V> _map;

  FixedMap(this.maxLength, {Map<K, V>? map}) {
    _map = map ?? {};
  }

  V updateCacheValue(K key, ValueCallback<V> callback) {
    final realValue = _map.updateCacheValue(key, callback);
    _adjustMap();
    return realValue;
  }

  void clear() {
    _map.clear();
  }

  void updateMaxLength(int size) {
    maxLength = size;
    _adjustMap();
  }

  void updateMap(Map<K, V> map) {
    _map = map;
    _adjustMap();
  }

  void _adjustMap() {
    if (_map.length > maxLength) {
      _map = Map.fromEntries(map.entries.toList()..truncate(maxLength));
    }
  }

  V? get(K key) => _map[key];

  bool containsKey(K key) => _map.containsKey(key);

  int get length => _map.length;

  Map<K, V> get map => Map.unmodifiable(_map);
}
