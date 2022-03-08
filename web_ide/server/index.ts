import { WebSocketServer, WebSocket } from 'ws'
import fs from 'fs'
import { exec } from 'child_process'

const wss = new WebSocketServer({ port: 8080 })

const compile_and_send_wasm = (ws: WebSocket) => {
  exec('yeti index.yeti', (err, stdout, stderr) => {
    if (err) {
      console.log('error compiling index.yeti')
      console.log(stderr)
      return
    }
    fs.readFile('index.wasm', null, (err, data) => {
      if (err) {
        console.log('error reading index.wasm')
        return
      }
      ws.send(data)
      console.log('sent index.wasm to client')
    })
  })
}

wss.on('connection', (ws) => {
  compile_and_send_wasm(ws)
  fs.watch('index.yeti', (event, filename) => {
    if (!filename && event !== 'change') {
      return
    }
    compile_and_send_wasm(ws)
  })
  ws.on('message', (data) => {
    console.log('received: %s', data)
  });
});
