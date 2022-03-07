const on_page_load = () => {
  const ws = new WebSocket("ws://localhost:8080")

  ws.binaryType = "arraybuffer"

  ws.onmessage = (event) => {
    console.clear()

    const canvas = document.querySelector("#c") as HTMLCanvasElement

    const gl = canvas.getContext("webgl2")

    if (!gl) {
      console.error("no webgl2 context available")
      return
    }

    const shaders = []

    var memory = undefined

    const imports = {
      "gl": {
        "create_shader": (shader_type: number): bigint => {
          const shader_index = shaders.length
          const shader = gl.createShader(Number(shader_type))
          shaders.push(shader)
          return BigInt(shader_index)
        },
        "shader_source": (shader: number, source_ptr: number, source_len: number): void => {
          const buffer = new Uint8Array(memory.buffer, source_ptr, source_len)
          gl.shaderSource(shaders[shader], buffer as unknown as string)
          console.log(source_ptr)
          console.log(source_len)
          console.log(new TextDecoder('utf-8').decode(buffer))
        },
        "compile_shader": (shader: number): void => {
          gl.compileShader(shaders[shader])
        },
        "get_shader_parameter": (shader: number, pname: BigInt): BigInt => {
          return BigInt(gl.getShaderParameter(shaders[shader], Number(pname)))
        },
      },
      "console": {
        "log": console.log,
      }
    }

    WebAssembly.instantiate(event.data, imports).then((module) => {
      memory = module.instance.exports.memory;

      (module.instance.exports.on_load as Function)()
    })
  }
}

on_page_load()
