const imports = {
        "console": {
                "log": console.log
        }
}

const ws = new WebSocket("ws://localhost:8080")

ws.binaryType = "arraybuffer"

ws.onmessage = (event) => {
        WebAssembly.instantiate(event.data, imports).then((module) => {
                const on_load = module.instance.exports.on_load
                if (typeof on_load === 'function') {
                        on_load()
                }
        })
}
