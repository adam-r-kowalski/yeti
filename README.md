# Yeti

A programming language aiming to be fun and productive while mapping cleanly to the underlying hardware.

## Installation

First ensure that the prerequisites are installed

- [wasmtime](https://github.com/bytecodealliance/wasmtime#installation) A standalone runtime for [WebAssembly](https://webassembly.org/)
- [wabt](https://github.com/WebAssembly/wabt) The WebAssembly Binary Toolkit
- [zig](https://github.com/ziglang/zig#installation) A general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.

For detailed instructions on how to install these for your platform check our [wiki](https://github.com/adam-r-kowalski/yeti/wiki/Installing-Prerequisites)

To build the compiler clone the repository and run the build command

```
git clone https://github.com/adam-r-kowalski/yeti.git
cd yeti
zig build
```

Add Yeti `zig-out/bin/yeti` to your `PATH`

You're ready to use Yeti

## Your First Yeti Program

Create a file `start.yeti` with the following contents

```
start() {
  42
}
```

Compile and execute the program

```
yeti start.yeti
```

Has the following output

```
42
```

Our first program defines a function `start` which returns `42`.

# Variables

```
start() {
  x = 10
  y = 15
  x + y
}
```

```
25
```

This program defines two variables `x` and `y`, then adds them together.

# Explicit Type Annotations

```
start(): i32 {
  x: i32 = 10
  y: i32 = 10
  x + y
}
```

```
20
```

You can explicitly define the return type of functions as well as the type of a local variable.
This is encouraged when it helps the readability of a program. In this case we are stating that
`x` and `y` are both variables of type `i32` which is a 32 bit integer.

# Conditionals

```
min(x: i64, y: i64) {
  if x < y { x } else { y }
}

start() {
  min(20, 30)
}
```

```
20
```

Here we define a function `min` which takes two parameters `x` and `y` which have type `i64`.
If `x` is less than `y` we return `x` otherwise we return `y`.

# While Loops

```
fib(n: i64) {
  prev = 0
  curr = 1
  while n > 0 {
    next = prev + curr
    prev = curr
    curr = next
    n = n - 1
  }
  curr
}

start() {
  fib(10)
}
```

```
89
```

Here the nth fibonacci number is calculated using while loops

# For Loops

```
fib(n: i64) {
  prev = 0
  curr = 1
  for i in 0:n {
    next = prev + curr
    prev = curr
    curr = next
  }
  curr
}

start() {
  fib(10)
}
```

```
89
```

# For Loops With Implicit Start

```
fib(n: i64) {
  prev = 0
  curr = 1
  for i in :n {
    next = prev + curr
    prev = curr
    curr = next
  }
  curr
}

start() {
  fib(10)
}
```

```
89
```

The same algorithm can be implemented using for loops

# Uniform Function Call Syntax

```
square(n: i64) {
  n * n
}

min(x: i64, y: i64) {
  if x < y { x } else { y }
}

line(m: i64, x: i64, b: i64) {
  m * x + b
}

start() {
  line(5, min(square(10), 200), 3) == 10.square.min(200).line(5, _, 3)
}
```

```
1
```

Object oriented languages have a nice syntax for chaining methods together in a left to right fashion.
We can accomplish the same functionality while allowing external extension through uniform function call syntax.

# Named arguments

```
min(x: f64, y: f64) {
  if x < y { x } else { y }
}

max(x: f64, y: f64) {
  if x > y { x } else { y }
}

clamp(value: f64, low: f64, high: f64) {
  value.min(high).max(low)
}

start() {
  clamp(3, low=-2, high=2)
}
```

```
2
```

When functions have multiple parameters it can be helpful when calling them to utilize named arguments
as demonstrated with the call to `clamp`.

# Structs

```
struct Rectangle {
  width: f64
  height: f64
}

area(r: Rectangle) {
  r.width * r.height
}

struct Square {
  length: f64
}

area(s: Square) {
  s.length * s.length
}

start() {
  s = Square(10)
  r = Rectangle(width=10, height=20)
  r.area
}
```

```
200
```

Structs allow us to group together common data into a single type.
Function overloading can be leveraged to define multiple functions with the same name,
but that operate on different types of data.

# Imports

### clamp.yeti
```
min(x: f64, y: f64) {
  if x < y { x } else { y }
}

max(x: f64, y: f64) {
  if x > y { x } else { y }
}

clamp(value: f64, low: f64, high: f64) {
  value.min(high).max(low)
}
```

### start.yeti
```
import "clamp.yeti"

start() {
  clamp(7, low=2, high=5)
}
```

### output
```
5
```

You can split yeti programs into multiple files which can then be imported to facilate code reuse.
Unlike some languages Yeti does not require that you qualify the calls after importing a module.
Instead we rely on overloading to resolve ambiguities.


# Foreign Imports And Exports

```
@import
log(value: i64): void

@export
on_load() {
  log(10)
  log(15)
  log(20)
}
```

One of the core competencies of Yeti is the ability to interoperate with other languages.
By marking a function with the `@import` attribute you can specify that it comes from another
language. Marking a function with `@export` means it can be called from another language.
Check out the [javascript](https://github.com/adam-r-kowalski/yeti/tree/main/examples/javascript_interop)
and [python](https://github.com/adam-r-kowalski/yeti/tree/main/examples/python_interop) examples for
more details!

# Pointers

```
start() {
  x = cast(*i32, 0)
  y = x + 1
  z = y + 1
  *x = 10
  *y = 20
  *z = *x + *y
  *z
}
```

Pointers and the ability to talk about memory are fundamental in programming.
The syntax for casting from integers to pointers, doing arithmetic on pointers,
reading and writing through pointers are all very light weight.

# SIMD

```
struct Vec4 {
  a: i32
  b: i32
  c: i32
  d: i32
}

start() {
  x0 = cast(*i32, 0)
  x1 = x0 + 1
  x2 = x1 + 1
  x3 = x2 + 1
  
  y0 = x3 + 1
  y1 = y0 + 1
  y2 = y1 + 1
  y3 = y2 + 1
  
  z0 = y3 + 1
  z1 = z0 + 1
  z2 = z1 + 1
  z3 = z2 + 1

  x = cast(*i32x4, 0)
  y = x + 1
  z = y + 1

  *x0 = 10
  *x1 = 20
  *x2 = 30
  *x3 = 40
  
  *y0 = 50
  *y1 = 60
  *y2 = 70
  *y3 = 80

  *z = *x + *y

  Vec4(*z0, *z1, *z2, *z3)
}
```

```
60
80
100
120
```

SIMD (Single Instruction Multiple Data) is crucial for getting the most out of modern hardware.
In this example we perform an addition of 4 `i32` values at the same time.
