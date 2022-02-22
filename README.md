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

This has the following output

```
42
```

Our first program defined a function `start` which had `0` parameters and returned `42`.

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
