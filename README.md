# Efficient Persistent Data Structures

[![Build Status](https://drone.io/github.com/vacuumlabs/persistent/status.png)](https://drone.io/github.com/vacuumlabs/persistent/latest)

The project is forked from
[polux/persistent](https://github.com/polux/persistent).

## What are persistent data structures
*Persistent* data structure is an immutable structure; the main difference with standard data structures is how you 'write' to them: instead of mutating
the old structure, you create the new, independent, (slightly) modified copy of it. Typical examples of commonly used Persistent structures are String (in Java, Javascript, Python, Ruby) or Python's Tuple or Java's BigDecimal. [(Not only)](http://www.infoq.com/presentations/Value-Identity-State-Rich-Hickey) we believe such concept could be beneficial also for other data structures such as Maps, Lists/Vectors, Sets.

     var couple = new PersistentMap.fromMap({'father': 'Homer', 'mother': 'Marge'});
     // do not (and can not) modify couple anymore
     var withChild = couple.assoc('boy', 'Bart');
     print(couple); // {mother: Marge, father: Homer}
     print(withChild); // {boy: Bart, mother: Marge, father: Homer}

## Got it. And it is cool because...?

### It disallows unwanted side effects
You know the story. Late in the evening, exhausted and frustrated you find out that some guy that implemented

     int ComputeResponseLength(Map responseMap) 

got a 'great' idea, that instead of just computing response length he also mutates responseMap in some tricky way (say, he does some kind of sanitization of responseMap). Even if this was mentioned in the documentation and even if the methods name was different: this is a spaghetti code.

### Equality and hashCode done right
Finally, they work as you'd expect. How cool is this:

    // deeply persist the structure of Maps and Lists
    var a = persist({[1,2]: 'tower', [1,3]: 'water'});
    var b = persist({[1,2]: 'tower', [1,3]: 'water'});
    assert(a==b); 
    // kids, don't try this with standard List, it ain't going to work
    print(a[persist([1, 2])]); // prints 'tower'

### Instant 'deep copy'
Just copy/pass the reference. It's like doing deep copy in O(1).

### Caching made easier
Caching can speed things up significantly. But how do you cache results of a function

    List findSuspiciousEntries(List<Map> entries)

One possible workaround would be to JSONize entries to string and use such string as a hashing key. However, it's much more elegant, safe (what about ordering of keys within maps?), performant and memory-wise with Persistent structures. Also, until you restrict to well-behaving functions, there's no need to invalidate cache; you can cache anything, for as long as you want.
    
### Simplicity matters
Fast copying or equality done right are nice features, but this is not the only selling point here. Having different ways how to copy (shallow, deep) objects or how to compare them (== vs. equals in Java) introduces new complexity. Even if you get used to it, it still takes some part of your mental capabilities and can lead to errors.

### Structure sharing 
    var map1 = persist({'a': 'something', 'b': bigMap});
    var map2 = a.assoc('a', 'something completely different');
Suppose you are interested, whether map1['b'] == map2['b']. Thanks to structure sharing, this is O(1) operation, which means it is amazingly fast - no need to traverse through the bigMap. Although it may sound unimportant at the first glance, it is what really enables fast caching of complex functions. Also, this is the reason, why [Om](https://github.com/swannodette/om/) framework is MUCH faster than Facebooks [React](http://facebook.github.io/react/).

## And what is the prize for this all
Short version: size and speed. Although structure sharing makes the whole thing much more effective than naive copy-it-all approach, Persistents still are slower and bigger than their mutable counterparts. Following numbers illustrate, how much less efficient (in terms of speed or memory consumption) are Persistent data structures when benchmarking either on DartVM or Dart2JS on Node:

* DartVM memory: 2.5
* Dart2JS memory: 6
* DartVM read speed: 2
* DartVM write speed: 2.5
* Dart2JS read speed: 2
* Dart2JS write speed: 4

The good part of the story is, that these numbers are not getting worse, as the Map grows - you get such performance even for Maps with tens of megabytes of data stored within them.

Some [advanced topics](https://github.com/vacuumlabs/persistent/wiki/Advanced-topics).

