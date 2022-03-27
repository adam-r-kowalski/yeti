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

    const shaders: WebGLShader[] = []
    const programs: WebGLProgram[] = []
    const buffers: WebGLBuffer[] = []
    const vertex_arrays: WebGLVertexArrayObject[] = []
    const uniform_locations: WebGLUniformLocation[] = []

    var memory: WebAssembly.Memory = undefined

    const imports = {
      "host": {
        "create_shader": (shader_type: number): number => {
          const shader_index = shaders.length
          const shader = gl.createShader(shader_type)
          shaders.push(shader)
          return shader_index
        },
        "shader_source": (shader: number, source_ptr: number, source_len: number): void => {
          const buffer = new Uint8Array(memory.buffer, source_ptr, source_len)
          gl.shaderSource(shaders[shader], new TextDecoder('utf-8').decode(buffer))
        },
        "compile_shader": (shader: number): void => {
          gl.compileShader(shaders[shader])
        },
        "get_shader_parameter": (shader: number, pname: number): number => {
          return gl.getShaderParameter(shaders[shader], pname)
        },
        "log_shader_info": (shader: number): void => {
          console.log(gl.getShaderInfoLog(shaders[shader]))
        },
        "delete_shader": (shader: number): void => {
          gl.deleteShader(shaders[shader])
        },
        "create_program": (): number => {
          const program_index = programs.length
          const program = gl.createProgram()
          programs.push(program)
          return program_index
        },
        "attach_shader": (program: number, shader: number): void => {
          gl.attachShader(programs[program], shaders[shader])
        },
        "link_program": (program: number): void => {
          gl.linkProgram(programs[program])
        },
        "get_program_parameter": (program: number, pname: number): number => {
          return gl.getProgramParameter(programs[program], pname)
        },
        "log_program_info": (program: number): void => {
          console.log(gl.getProgramInfoLog(programs[program]))
        },
        "delete_program": (program: number): void => {
          gl.deleteProgram(programs[program])
        },
        "get_attrib_location": (program: number, attrib_ptr: number, attrib_len: number): number => {
          const buffer = new Uint8Array(memory.buffer, attrib_ptr, attrib_len)
          return gl.getAttribLocation(programs[program], new TextDecoder('utf-8').decode(buffer))
        },
        "get_uniform_location": (program: number, uniform_ptr: number, uniform_len: number): number => {
          const buffer = new Uint8Array(memory.buffer, uniform_ptr, uniform_len)
          const uniform = gl.getUniformLocation(programs[program], new TextDecoder('utf-8').decode(buffer))
          const uniform_index = uniform_locations.length
          uniform_locations.push(uniform)
          return uniform_index
        },
        "uniform2f": (uniform: number, width: number, height: number): void => {
          gl.uniform2f(uniform_locations[uniform], width, height)
        },
        "create_buffer": (): number => {
          const buffer_index = buffers.length
          const buffer = gl.createBuffer()
          buffers.push(buffer)
          return buffer_index
        },
        "bind_buffer": (target: number, buffer: number): void => {
          gl.bindBuffer(target, buffers[buffer])
        },
        "buffer_data": (target: number, usage: number, positions_ptr: number, positions_len: number): void => {
          const positions = new Float32Array(memory.buffer, positions_ptr, positions_len)
          gl.bufferData(target, positions, usage)
        },
        "create_vertex_array": (): number => {
          const vertex_array_index = vertex_arrays.length
          const vertex_array = gl.createVertexArray()
          vertex_arrays.push(vertex_array)
          return vertex_array_index
        },
        "bind_vertex_array": (vertex_array: number): void => {
          gl.bindVertexArray(vertex_arrays[vertex_array])
        },
        "enable_vertex_attrib_array": (index: number): void => {
          gl.enableVertexAttribArray(index)
        },
        "vertex_attrib_pointer": (index: number, size: number, dtype: number, normalized: boolean, stride: number, offset: number): void => {
          gl.vertexAttribPointer(index, size, dtype, normalized, stride, offset)
        },
        "resize_canvas_to_display_size": (): void => {
          if (canvas.width !== canvas.clientWidth || canvas.height !== canvas.clientHeight) {
            canvas.width = canvas.clientWidth
            canvas.height = canvas.clientHeight
          }
        },
        "viewport": (x: number, y: number, width: number, height: number): void => {
          gl.viewport(x, y, width, height)
        },
        "canvas_width": (): number => gl.canvas.width,
        "canvas_height": (): number => gl.canvas.height,
        "clear_color": (red: number, green: number, blue: number, alpha: number): void => {
          gl.clearColor(red, green, blue, alpha)
        },
        "clear": (mask: number): void => {
          gl.clear(mask)
        },
        "use_program": (program: number): void => {
          gl.useProgram(programs[program])
        },
        "draw_arrays": (mode: number, first: number, count: number): void => {
          gl.drawArrays(mode, first, count)
        },
        "log": console.log,
      }
    }

    WebAssembly.instantiate(event.data, imports).then((module) => {
      memory = module.instance.exports.memory as WebAssembly.Memory;

      (module.instance.exports.on_load as Function)()
    })
  }
}

on_page_load()
