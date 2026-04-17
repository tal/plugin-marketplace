# Duktape ES5.1 Constraints

Karabiner-Elements uses the Duktape JavaScript engine, which supports ES5.1 only. This page documents what works and what doesn't.

## Available (ES5.1)

### Variable declarations
```javascript
var x = 1;           // OK
var x = 1, y = 2;    // OK
```

### Functions
```javascript
function myFunc(a, b) { return a + b; }          // OK
var myFunc = function(a, b) { return a + b; };    // OK
```

### Array methods
```javascript
arr.map(function(x) { return x * 2; })    // OK
arr.filter(function(x) { return x > 0; }) // OK
arr.forEach(function(x) { /* ... */ })     // OK
arr.indexOf(value)                         // OK
arr.reduce(function(acc, x) { return acc + x; }, 0) // OK
arr.some(function(x) { return x > 0; })   // OK
arr.every(function(x) { return x > 0; })  // OK
arr.concat(otherArr)                       // OK
arr.slice(start, end)                      // OK
arr.splice(index, count)                   // OK
arr.push(value)                            // OK
arr.join(separator)                        // OK
arr.sort(compareFn)                        // OK
arr.reverse()                              // OK
```

### String methods
```javascript
str.indexOf(substr)       // OK
str.replace(a, b)         // OK
str.split(separator)      // OK
str.substring(start, end) // OK
str.toLowerCase()         // OK
str.toUpperCase()         // OK
str.trim()                // OK
str.charAt(index)         // OK
str.match(regex)          // OK
```

### Object methods
```javascript
Object.keys(obj)          // OK
JSON.stringify(obj)       // OK
JSON.parse(str)           // OK
```

### Control flow
```javascript
if / else / else if       // OK
for (var i = 0; ...)      // OK
for (var key in obj)      // OK
while / do...while        // OK
switch / case             // OK
try / catch / finally     // OK
```

### Other
```javascript
typeof x                  // OK
x instanceof Array        // OK
Math.floor, Math.random, etc.  // OK
RegExp                    // OK
Date                      // OK
```

## NOT available (ES6+)

### Variable declarations
```javascript
let x = 1;     // ERROR - use var
const x = 1;   // ERROR - use var
```

### Arrow functions
```javascript
var fn = (x) => x * 2;              // ERROR
var fn = function(x) { return x * 2; };  // use this instead
```

### Template literals
```javascript
var s = `Hello ${name}`;            // ERROR
var s = "Hello " + name;            // use this instead
```

### Destructuring
```javascript
var { a, b } = obj;                 // ERROR
var a = obj.a, b = obj.b;           // use this instead

var [x, y] = arr;                   // ERROR
var x = arr[0], y = arr[1];         // use this instead
```

### Default parameters
```javascript
function fn(x = 5) {}               // ERROR
function fn(x) { x = x || 5; }     // use this pattern (careful with falsy values)
// or more precisely:
function fn(x) {
  if (typeof x === "undefined") { x = 5; }
}
```

### Spread / rest
```javascript
var combined = [...arr1, ...arr2];   // ERROR
var combined = arr1.concat(arr2);    // use this instead

function fn(...args) {}              // ERROR
// use arguments object instead
```

### for...of
```javascript
for (var x of arr) {}               // ERROR
for (var i = 0; i < arr.length; i++) { var x = arr[i]; }  // use this
// or arr.forEach(function(x) { ... })
```

### Classes
```javascript
class Foo {}                         // ERROR
// use constructor functions if needed
```

### Promises / async-await
```javascript
Promise.resolve()                    // ERROR
async function fn() {}               // ERROR
// not applicable in this context anyway (synchronous execution)
```

### New built-ins
```javascript
Array.from()          // ERROR - use Array.prototype.slice.call()
Object.entries()      // ERROR - use Object.keys() + map
Object.assign()       // ERROR - use a manual loop or a helper
Map, Set, WeakMap     // ERROR
Symbol                // ERROR
```

## Helper patterns for common ES6 replacements

### Object.assign replacement
```javascript
function merge(target, source) {
  var keys = Object.keys(source);
  for (var i = 0; i < keys.length; i++) {
    target[keys[i]] = source[keys[i]];
  }
  return target;
}
```

### Object.entries replacement
```javascript
function entries(obj) {
  return Object.keys(obj).map(function(k) { return [k, obj[k]]; });
}
```

### Array.from replacement (for array-like objects)
```javascript
var arr = Array.prototype.slice.call(arrayLike);
```
