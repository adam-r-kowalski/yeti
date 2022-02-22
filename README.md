# Yeti

Programming language for writing fast, portable and secure code

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
start() {
  prev = 0
  curr = 1
  for i in 0:10 {
    next = prev + curr
    prev = curr
    curr = next
  }
  curr
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
