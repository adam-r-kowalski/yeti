from time import time
from typing import Any, Callable, TypeVar, cast
from functools import partial

from wasmtime import Store, Module, Instance
import matplotlib.pyplot as plt
import numpy as np



T = TypeVar('T', bound=Callable)


class Wasm:
    store: Store
    module: Module
    instance: Instance
    
    def __init__(self, filename: str) -> None:
        with open(filename, 'r') as file:
            content = file.read()
            self.store = Store()
            self.module = Module(self.store.engine, content)
            self.instance = Instance(self.store, self.module, [])

    def exports(self, name: str, F: type[T]) -> T:
        f = cast(Any, self.instance.exports(self.store)[name])
        return cast(F, partial(f, self.store))


wasm = Wasm('fib.wat')


fib_yeti = wasm.exports('fib', Callable[[int], int])


def fib_python(n: int) -> int:
    if n < 2:
        return 1
    return fib_python(n - 1) + fib_python(n - 2)


def benchmark(trials: int, f: Callable[[], Any], label: str):
    times = []
    for _ in range(trials):
        begin = time()
        f()
        end = time()
        times.append(end - begin)
    plt.plot(times, label=f'{label} {np.mean(times):0.4f}s')


trials = 10
plt.figure(figsize=(12, 10))
benchmark(trials, lambda: fib_yeti(30), 'yeti')
benchmark(trials, lambda: fib_python(30), 'yeti')
plt.legend()
plt.ylabel('seconds')
plt.show()
