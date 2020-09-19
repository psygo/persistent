// Copyright (c) 2014, VacuumLabs.
// Copyright (c) 2012, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Authors are listed in the AUTHORS file

part of persistent;

// this turns out to be the fastest combination

const branchingBits = 4;
const maxDepth = 6;

//const branchingBits = 3;
//const maxDepth = 9;

//const branchingBits = 5;
//const maxDepth = 5;

const branching = 1 << branchingBits;
const branchingMask = (1 << branchingBits) - 1;
const allHashMask = (1 << (maxDepth + 1) * branchingBits) - 1;

const leafSize = branching * 3;
const leafSizeMin = branching * 2;

const binSearchThr = 4;
const recsize = 3; //0 - hash, 1 - key, 2 - val

final _random = new Random();

_ThrowKeyError(key) => throw new Exception('Key Error: ${key} is not defined');

_ThrowUpdateKeyError(key, exception) => throw new Exception(
    'Key $key was not found, calling update with no arguments threw: $exception');

_getUpdateValue(key, updateF) {
  try {
    return updateF();
  } catch (e) {
    _ThrowUpdateKeyError(key, e);
  }
}

/// see technical.md for explanation of what this does
_mangleHash(hash) {
  var _tmp = hash ^ (hash << 8);
  return ((_tmp ^ (_tmp << 16)) & allHashMask);
}

/// no array compression here (aka bitpos style). Why? See technical.md

_getBranch(hash, depth) {
  return (hash >> (depth * branchingBits)) & branchingMask;
}

class _TMapImpl<K, V> extends IterableBase<Pair<K, V>> implements TMap<K, V> {
  // Although PMap can be represented a simple _Node, Transient map needs
  // separate structure with a mutable reference to _Node.
  _Node _root;

  _Owner _owner;
  get owner => _owner != null
      ? _owner
      : throw new Exception('Cannot modify TMap after calling asPersistent.');

  factory _TMapImpl() => new _TMapImpl.fromPersistent(new PMap());

  /**
   * Creates an immutable copy of [map] using the default implementation of
   * [TMap].
   */
  _TMapImpl.fromPersistent(_Node<K, V> map) {
    _owner = new _Owner();
    _root = map;
  }

  TMap _adjustRootAndReturn(newRoot) {
    _root = newRoot;
    return this;
  }

  TMap<K, V> doAssoc(K key, V value) {
    return _adjustRootAndReturn(_root._assoc(owner, key, value));
  }

  operator []=(key, value) {
    this.doAssoc(key, value);
  }

  TMap<K, V> doDelete(K key, {bool missingOk: false}) {
    return _adjustRootAndReturn(_root._delete(
        owner, key, _mangleHash(key.hashCode), maxDepth, missingOk));
  }

  TMap<K, V> doUpdate(K key, dynamic updateF) {
    return _adjustRootAndReturn(_root._update(owner, key, updateF));
  }

  PMap asPersistent() {
    _owner = null;
    return this._root;
  }

  toString() => 'TMap($_root)';

  V get(K key, [V notFound = _none]) => _root.get(key, notFound);

  V operator [](K key) => _root.get(key);

  void forEachKeyValue(f) => _root.forEachKeyValue(f);

  Map<K, V> toMap() => _root.toMap();

  Iterable<K> get keys => _root.keys;

  Iterable<V> get values => _root.values;

  Iterator<Pair<K, V>> get iterator => _root.iterator;

  int get length => _root.length;

  bool containsKey(key) => _root.containsKey(key);

  bool hasKey(key) => _root.hasKey(key);
}

/**
 * Superclass for _EmptyMap, _Leaf and _SubMap.
 */
abstract class _Node<K, V> extends IterableBase<Pair<K, V>>
    implements PMap<K, V> {
  _Owner _owner;
  int _length;
  int _hash;
  get length => _length;

  _Node(this._owner, this._length);

  factory _Node.fromMap(map) {
    _Node root = new _Leaf.empty(null);
    map.forEach((K key, V value) {
      root = root._assoc(null, key, value);
    });
    return root;
  }

  factory _Node.fromPairs(pairs) {
    var _root = new _Leaf.empty(null);
    pairs.forEach((pair) {
      _root = _root._assoc(null, pair.fst, pair.snd);
    });
    return _root;
  }

  _forEachKVSegment(f);

  V _get(K key, int hash, int depth);
  _Node<K, V> _insertOneWith(_Owner owner, key, val, hash, int depth, [update]);

  int get hashCode;

  _Node<K, V> _update(_Owner owner, K key, dynamic updateF) {
    return _insertOneWith(
        owner, key, null, _mangleHash(key.hashCode), maxDepth, updateF);
  }

  PMap<K, V> update(K key, dynamic updateF) => _insertOneWith(
      null, key, null, _mangleHash(key.hashCode), maxDepth, updateF);

  _Node<K, V> _assoc(_Owner owner, K key, V value) =>
      _insertOneWith(owner, key, value, _mangleHash(key.hashCode), maxDepth);

  PMap<K, V> assoc(K key, V value) => _assoc(null, key, value);

  _Node<K, V> _delete(_Owner owner, K key, int hash, int depth, bool missingOk);

  PMap<K, V> delete(K key, {bool missingOk: false}) =>
      _delete(null, key, _mangleHash(key.hashCode), maxDepth, missingOk);

  bool operator ==(other) {
    if (other is! _Node) return false;
    if (identical(this, other)) return true;
    _Node me = this;
    if (me.length != other.length) {
      return false;
    }
    if (me is _Leaf && other is _Leaf) {
      List mekv = (me as _Leaf)._kv;
      List okv = other._kv;
      var lastMatch = 0;
      for (int i = 0; i < mekv.length; i += recsize) {
        if (mekv[i] == okv[i]) {
          // same hash
          if (mekv[i + 1] == okv[i + 1]) {
            // same hash, same key
            if (mekv[i + 2] == okv[i + 2]) {
              // match
              lastMatch = i;
              continue;
            } else {
              // same key, but not value
              return false;
            }
          } else {
            // same hash, different key
            var hash = mekv[i];
            // find boundaries of same-hash regions
            var bm, bo;
            for (var j = i; j < mekv.length; j += recsize) {
              var fm = mekv[j] == hash;
              var fo = okv[j] == hash;
              if (fm) bm = j;
              if (fo) bo = j;
              if (!fm && !fo) break;
            }
            if (bm != bo) return false;
            // scan the same-hash regions
            for (var j = i; j <= bm; j += recsize) {
              bool res = false;
              for (var k = i; k <= bo; k += recsize) {
                res = res ||
                    ((mekv[j + 1] == okv[k + 1]) &&
                        (mekv[j + 2] == okv[k + 2]));
              }
              if (!res) return false;
            }
            // continue after the boundary
            i = bm;
          }
        } else {
          // different hash
          return false;
        }
      }
      return true;
    }
    if (me is _SubMap && other is _SubMap) {
      for (int i = 0; i < branching; i++) {
        if ((me as _SubMap)._array[i] != other._array[i]) {
          return false;
        }
      }
      return true;
    }
    if (me is _SubMap && other is _Leaf) {
      var _tmp = other;
      other = me;
      me = _tmp;
    }
    if (me is _Leaf && other is _SubMap) {
      return me == new _Leaf.fromSubmap(other._owner, other);
    }
    throw new Exception('Should not get here');
    return null;
  }

  // method must be called only on top-level _Node
  V get(K key, [V notFound = _none]) {
    var val = _get(key, _mangleHash(key.hashCode), maxDepth);
    if (_isNone(val)) {
      if (_isNone(notFound)) {
        _ThrowKeyError(key);
        return null;
      } else {
        return notFound;
      }
    } else {
      return val;
    }
  }

  Map<K, V> toMap() {
    Map<K, V> result = new Map<K, V>();
    this.forEachKeyValue((K k, V v) {
      result[k] = v;
    });
    return result;
  }

  String toString() {
    StringBuffer buffer = new StringBuffer('{');
    bool comma = false;
    this.forEachKeyValue((K k, V v) {
      if (comma) buffer.write(', ');
      buffer.write('$k: $v');
      comma = true;
    });
    buffer.write('}');
    return buffer.toString();
  }

  Iterable<K> get keys => this.map((Pair<K, V> pair) => pair.fst);

  Iterable<V> get values => this.map((Pair<K, V> pair) => pair.snd);

  void forEachKeyValue(f(K key, V value));

  bool containsKey(key) {
    final _none = new Object();
    final value = this.get(key, _none);
    return value != _none;
  }

  bool hasKey(key) => containsKey(key);

  TMap<K, V> asTransient() {
    return new _TMapImpl.fromPersistent(this);
  }

  PMap<K, V> withTransient(dynamic f(TMap map)) {
    TMap transient = this.asTransient();
    f(transient);
    return transient.asPersistent();
  }

  V operator [](K key) => get(key);

  PMap strictMap(Pair<K, V> f(Pair<K, V> pair)) =>
      new PMap.fromPairs(this.map(f));

  PMap<K, V> strictWhere(bool f(Pair<K, V> pair)) =>
      new PMap<K, V>.fromPairs(this.where(f));

  static V _returnRight<V>(V left, V right) => right;

  PMap<K, V> union(PMap<K, V> other,
      [V combine(V left, V right)]) {
    if (combine == null) combine = _returnRight;
    if (other is _Node) {
      return _union(other as _Node, combine, maxDepth);
    } else {
      var result = this.asTransient();
      other.forEachKeyValue((K key, V value) {
        if (result.hasKey(key)) {
          result.doAssoc(key, combine(this[key], value));
        } else {
          result.doAssoc(key, value);
        }
      });
      return result.asPersistent();
    }
  }

  PMap<K, V> intersection(PMap<K, V> other,
      [V combine(V left, V right) = _returnRight]) {
    if (other is _Node) {
      return _intersection(other as _Node, combine, maxDepth);
    } else {
      var result = new PMap().asTransient();
      other.forEachKeyValue((K key, V value) {
        if (this.hasKey(key)) {
          result.doAssoc(key, combine(this[key], value));
        }
      });
      return result.asPersistent();
    }
  }

  PMap<K, V> _union(_Node<K, V> other, V combine(V left, V right), int depth);

  PMap<K, V> _intersection(
      _Node<K, V> other, V combine(V left, V right), int depth);
}

class _Leaf<K, V> extends _Node<K, V> {
  List _kv;
  get private_kv => _kv;

  get iterator {
    List<Pair<K, V>> pairs = [];
    for (int i = 0; i < _kv.length; i += recsize) {
      pairs.add(new Pair(_kv[i + 1], _kv[i + 2]));
    }
    return pairs.iterator;
  }

  /// check whether order-by-hashcode invariant (see technical.md) holds
  void sanityCheck() {
    var lasthash = - double.infinity;
    for (int i = 0; i < _kv.length; i += recsize) {
      if (lasthash > _kv[i]) {
        throw new Exception('invariant violated');
      }
      lasthash = _kv[i];
    }
  }

  int get hashCode {
    if (_hash != null) return _hash;
    _hash = 0;
    for (int i = 0; i < _kv.length; i += recsize) {
      _hash ^= hash2(_kv[i], _kv[i + 2].hashCode);
    }
    return _hash;
  }

  _Leaf.abc(_Owner owner, _kv) : super(owner, _kv.length ~/ recsize) {
    this._kv = _kv;
  }

  _Leaf.empty(_Owner owner) : super(owner, 0) {
    this._kv = [];
  }

  factory _Leaf.fromSubmap(_Owner owner, _SubMap sm) {
    List _kv = [];
    sm._forEachKVSegment((kv) {
      _kv.addAll(kv);
    });
    var nres = new _Leaf.abc(owner, _kv);
    return nres;
  }

  factory _Leaf.ensureOwner(_Leaf old, _Owner owner, kv, int length) {
    if (_ownerEquals(owner, old._owner)) {
      old._kv = kv;
      old._length = length;
      return old;
    }
    return new _Leaf.abc(owner, kv);
  }

  /// see technical.md for explanation of what this does

  _Node<K, V> _polish(_Owner owner, int depth, List _kv) {
    assert(_kv.length % recsize == 0);
    // depth == -1 means we are at the bottom level; we consumed all
    // information from 'hash' and we have to extend the _Leaf no matter how
    // long it gets
    if (_kv.length < recsize * leafSize || depth == -1) {
      return new _Leaf.abc(owner, _kv);
    } else {
      List<List> kvs = new List.generate(branching, (_) => []);
      for (int i = 0; i < _kv.length; i += recsize) {
        int branch = _getBranch(_kv[i], depth);
        kvs[branch].add(_kv[i]);
        kvs[branch].add(_kv[i + 1]);
        kvs[branch].add(_kv[i + 2]);
      }
      List<_Node<K, V>> array =
          new List.generate(branching, (i) => new _Leaf.abc(owner, kvs[i]));
      return new _SubMap.abc(owner, array, _kv.length ~/ recsize);
    }
  }

  _insert(List into, key, val, hash, [update]) {
    assert(into.length % recsize == 0);
    if (into.length == 0) {
      into.addAll([hash, key, val]);
      return;
    }
    int from = 0;
    int to = (into.length ~/ recsize) - 1;
    while (to - from > binSearchThr) {
      int mid = (from + to) ~/ 2;
      var midh = into[mid * recsize];
      if (midh > hash) {
        to = mid;
      } else if (midh < hash) {
        from = mid;
      } else {
        break;
      }
    }

    for (int i = from * recsize; i <= to * recsize; i += recsize) {
      assert(i % recsize == 0);
      if (hash <= into[i]) {
        if (hash < into[i]) {
          into.insertAll(i, [hash, key, val]);
          return;
        }
        if (key == into[i + 1]) {
          if (update == null) {
            into[i + 2] = val;
          } else {
            into[i + 2] = update(into[i + 2]);
          }
          return;
        }
      }
    }

    if (update == null) {
      into.addAll([hash, key, val]);
    } else {
      into.addAll([hash, key, _getUpdateValue(key, update)]);
    }
    assert(into.length % recsize == 0);
  }

  _Node<K, V> _insertOneWith(_Owner owner, key, val, hash, int depth,
      [update]) {
    List nkv = _makeCopyIfNeeded(owner, this._owner, _kv);
    _insert(nkv, key, val, hash, update);
    return _polish(owner, depth, nkv);
  }

  _Node<K, V> _delete(
      _Owner owner, K key, int hash, int depth, bool missingOk) {
    bool found = false;
    List nkv = _makeCopyIfNeeded(owner, this._owner, _kv);
    for (int i = 0; i < nkv.length; i += recsize) {
      if (nkv[i] == hash && nkv[i + 1] == key) {
        nkv.removeRange(i, i + recsize);
        found = true;
        break;
      }
    }
    assert(nkv.length % recsize == 0);

    if (!found) {
      if (missingOk) {
        return this;
      } else {
        _ThrowKeyError(key);
        // won't get here, just to make Dart Editor happy
        return null;
      }
    } else {
      return new _Leaf<K, V>.ensureOwner(
          this, owner, nkv, nkv.length ~/ recsize);
    }
  }

  V _get(K key, int hash, int depth) {
    int f = 0;
    int from = 0;
    int to = _kv.length ~/ recsize;
    while (to - from > binSearchThr) {
      int mid = (from + to) ~/ 2;
      var midh = _kv[mid * recsize];
      if (midh > hash) {
        to = mid;
      } else if (midh < hash) {
        from = mid;
      } else {
        break;
      }
    }
    for (int i = from * recsize; i < to * recsize; i += recsize) {
      if (_kv[i] == hash && _kv[i + 1] == key) {
        return _kv[i + 2];
      }
    }
    return _none;
  }

  void forEachKeyValue(f(K, V)) {
    for (int i = 0; i < _kv.length; i += recsize) {
      f(_kv[i + 1], _kv[i + 2]);
    }
  }

  toDebugString() => "_Leaf($_kv)";

  _forEachKVSegment(f) {
    f(_kv);
  }

  PMap<K, V> _union(_Node<K, V> other, V combine(V left, V right), int depth) {
    // TODO: More efficient union of two leafs.
    _Owner owner = new _Owner();
    for (int i = 0; i < _kv.length; i += 3) {
      var res = other._get(_kv[i + 1], _kv[i], depth);
      if (_isNone(res)) {
        other =
            other._insertOneWith(owner, _kv[i + 1], _kv[i + 2], _kv[i], depth);
      } else {
        other = other._insertOneWith(
            owner, _kv[i + 1], combine(_kv[i + 2], res), _kv[i], depth);
      }
    }
    other._owner = null;
    return other;
  }

  PMap<K, V> _intersection(
      _Node<K, V> other, V combine(V left, V right), int depth) {
    List _nkv = [];
    for (int i = 0; i < _kv.length; i += 3) {
      var res = other._get(_kv[i + 1], _kv[i], depth);
      if (!_isNone(res)) {
        _nkv.addAll([_kv[i], _kv[i + 1], combine(_kv[i + 2], res)]);
      }
    }
    return new _Leaf.abc(null, _nkv);
  }
}

class _SubMapIterator<K, V> implements Iterator<Pair<K, V>> {
  List<_Node<K, V>> _array;
  int _index = 0;
  // invariant: _currentIterator != null => _currentIterator.current != null
  Iterator<Pair<K, V>> _currentIterator = null;

  _SubMapIterator(this._array);

  Pair<K, V> get current =>
      (_currentIterator != null) ? _currentIterator.current : null;

  bool moveNext() {
    while (_index < _array.length) {
      if (_currentIterator == null) {
        _currentIterator = _array[_index].iterator;
      }
      if (_currentIterator.moveNext()) {
        return true;
      } else {
        _currentIterator = null;
        _index++;
      }
    }
    return false;
  }
}

class _SubMap<K, V> extends _Node<K, V> {
  List<_Node<K, V>> _array;

  Iterator<Pair<K, V>> get iterator => new _SubMapIterator(_array);

  _SubMap.abc(_Owner owner, this._array, int length) : super(owner, length);

  factory _SubMap.ensureOwner(_SubMap old, _Owner owner, array, int length) {
    if (_ownerEquals(owner, old._owner)) {
      old._array = array;
      old._length = length;
    }
    return new _SubMap.abc(owner, array, length);
  }

  int get hashCode {
    if (_hash != null) return _hash;
    _hash = 0;
    for (var child in _array) {
      _hash ^= child.hashCode;
    }
    return _hash;
  }

  V _get(K key, int hash, int depth) {
    int branch = _getBranch(hash, depth);
    _Node<K, V> map = _array[branch];
    return map._get(key, hash, depth - 1);
  }

  _Node<K, V> _insertOneWith(_Owner owner, key, val, hash, int depth,
      [update]) {
    int branch = _getBranch(hash, depth);
    _Node<K, V> m = _array[branch];
    int oldSize = m.length;
    _Node<K, V> newM =
        m._insertOneWith(owner, key, val, hash, depth - 1, update);
    if (identical(m, newM)) {
      if (oldSize != m.length) this._length += m.length - oldSize;
      return this;
    }
    List<_Node<K, V>> newarray = _makeCopyIfNeeded(owner, this._owner, _array);
    newarray[branch] = newM;
    int delta = newM.length - oldSize;
    return new _SubMap<K, V>.ensureOwner(this, owner, newarray, length + delta);
  }

  _Node<K, V> _delete(owner, K key, int hash, int depth, bool missingOk) {
    int branch = _getBranch(hash, depth);
    _Node<K, V> child = _array[branch];
    int childLength = child.length;
    // need to remember child length as this may modify
    // the child (if working with transient)
    _Node<K, V> newChild =
        child._delete(owner, key, hash, depth - 1, missingOk);
    int newLength = this.length + (newChild.length - childLength);
    if (identical(child, newChild)) {
      this._length = newLength;
      return this;
    }
    List<_Node<K, V>> newarray = new List<_Node<K, V>>.from(_array);
    newarray[branch] = newChild;
    _Node res = new _SubMap.ensureOwner(this, owner, newarray, newLength);

    // if submap is too small, let's replace it by _Leaf
    if (res._length >= leafSizeMin) {
      return res;
    } else {
      return new _Leaf.fromSubmap(owner, res);
    }
  }

  _forEachKVSegment(f) {
    _array.forEach((child) => child._forEachKVSegment(f));
  }

  forEachKeyValue(f(K, V)) {
    _array.forEach((mi) => mi.forEachKeyValue(f));
  }

  toDebugString() => "_SubMap($_array)";

  PMap<K, V> _union(_Node<K, V> other, V combine(V left, V right), int depth) {
    if (other is _SubMap) {
      var children = new List.generate(
          branching,
          (int i) => (_array[i]
              ._union((other as _SubMap)._array[i], combine, depth - 1)));
      int size = children.fold(0, (int sum, PMap<K, V> x) => sum += x.length);
      return new _SubMap.abc(null, children, size);
    } else {
      return other._union(this, (x, y) => combine(y, x), depth);
    }
  }

  PMap<K, V> _intersection(
      _Node<K, V> other, V combine(V left, V right), int depth) {
    if (other is _SubMap) {
      var children = new List<PMap<K, V>>.generate(
          branching,
          (int i) => (_array[i]._intersection(
              (other as _SubMap)._array[i], combine, depth - 1)));
      int size = children.fold(0, (int sum, x) => sum += x.length);
      var res = new _SubMap.abc(null, children, size);
      if (size >= leafSizeMin) {
        return res;
      } else {
        return new _Leaf.fromSubmap(null, res);
      }
    } else {
      return other._intersection(this, (x, y) => combine(y, x), depth);
    }
  }
}

_ownerEquals(_Owner a, _Owner b) {
  return a != null && a == b;
}

/// usually, we need to copy some arrays when associng. However, when working
/// with transients (and the owners match), it is safe just to modify the array
_makeCopyIfNeeded(_Owner a, _Owner b, List c) {
  if (_ownerEquals(a, b))
    return c;
  else
    return c.sublist(0);
}
