// Copyright 2012 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Paul Brauner (polux@google.com)

library test_util;

import 'package:args/args.dart';
import 'package:dart_check/dart_check.dart';
import 'package:dart_enumerators/combinators.dart' as c;
import 'package:dart_enumerators/enumerators.dart' as en;
import 'package:persistent/persistent.dart';
import 'package:unittest/unittest.dart';

part 'map_model.dart';
part 'set_model.dart';

/**
 * A datatype with an imperfect hash function
 */
class Key {
  int i;
  bool b;
  Key(this.i, this.b);
  bool operator ==(Key other) {
    if (other is! Key) return false;
    return i == other.i && b == other.b;
  }
  int get hashCode => i.hashCode;
  toString() => "Key($i,$b)";
}

/**
 * Enumerations of [Key], [Map<Key, int>] and [Set<Key>].
 */
class Enumerations {
  en.Enumeration<Key> keys;
  en.Enumeration<int> values;
  en.Enumeration<Map<Key, int>> maps;
  en.Enumeration<Set<Key>> sets;

  Enumerations() {
    keys = en.singleton((i) => (b) => new Key(i, b))
             .apply(c.ints)
             .apply(c.bools);
    values = c.ints + new en.Enumeration.singleton(null);
    maps = c.mapsOf(keys, values);
    sets = c.setsOf(keys);
  }
}

PersistentMap implemMapFrom(Map m) => new PersistentMap.fromMap(m);
ModelMap modelMapFrom(Map m) => new ModelMap(m);

PersistentSet implemSetFrom(Set s) => new PersistentSet.fromSet(s);
ModelSet modelSetFrom(Set s) => new ModelSet(s);

class _Stop implements Exception {}

bool mapEquals(Map m1, Map m2) {
  if (m1.length != m2.length) return false;
  try {
    m1.forEach((k, v) {
      if (!m2.containsKey(k)) throw new _Stop();
      if (v != m2[k]) throw new _Stop();
    });
  } on _Stop catch(e) {
    return false;
  }
  return true;
}

bool setEquals(Set s1, Set s2) {
  if (s1.length != s2.length) return false;
  try {
    s1.forEach((e) {
      if (!s2.contains(e)) throw new _Stop();
    });
  } on _Stop catch(e) {
    return false;
  }
  return true;
}

bool sameMap(PersistentMap pm, ModelMap mm) => mapEquals(pm.toMap(), mm.map);
bool sameSet(PersistentSet ps, ModelSet ms) => setEquals(ps.toSet(), ms.zet);

void testMain(Map<String, Property> properties) {
  final parser = new ArgParser();
  parser.addFlag('help', negatable: false);
  parser.addFlag('quiet', negatable: false);
  parser.addOption('quickCheckMaxSize', defaultsTo: '300');
  parser.addOption('smallCheckDepth', defaultsTo: '15');
  parser.addOption('property',
                   help: 'property to test or "all"',
                   allowed: new List.from(properties.keys)..add('all'),
                   allowMultiple: true,
                   defaultsTo: 'all');
  final flags = parser.parse(new Options().arguments);

  if (flags['help']) {
    print(parser.getUsage());
    return;
  }

  final qc = new QuickCheck(
      maxSize: int.parse(flags['quickCheckMaxSize']),
      quiet: flags['quiet']);
  final sc = new SmallCheck(
      depth: int.parse(flags['smallCheckDepth']),
      quiet: flags['quiet']);

  Collection<String> toTest = flags['property'];
  if (toTest.contains('all')) {
    toTest = properties.keys;
  }

  group('quickcheck', () {
    for (final property in toTest) {
      test(property, () => qc.check(properties[property]));
    }
  });
  group('smallcheck', () {
    for (final property in toTest) {
      test(property, () => sc.check(properties[property]));
    }
  });
}
