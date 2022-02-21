# Yeti

Programming language for writing fast, portable and secure code

## Installation

First ensure that the prerequisits are installed

- [wasmtime](https://github.com/bytecodealliance/wasmtime#installation) A standalone runtime for [WebAssembly](https://webassembly.org/)
- [wabt](https://github.com/WebAssembly/wabt) The WebAssembly Binary Toolkit
- [zig](https://github.com/ziglang/zig#installation) A general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software.

For detailed instructions on how to install these for your platform check our [wiki](https://google.com)

To build the compiler clone the repository and run the build command

```
git clone https://github.com/adam-r-kowalski/yeti.git
cd yeti
zig build
```

Add Yeti `zig-out/bin/yeti` to your `PATH`

You're ready to use Yeti
