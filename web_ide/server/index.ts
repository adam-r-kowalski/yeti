import { WebSocketServer } from 'ws';
import fs from 'fs'

const wss = new WebSocketServer({ port: 8080 });

wss.on('connection', (ws) => {
        fs.readFile('index.wasm', null, (err, data) => {
                if (!err) {
                        ws.send(data)
                }
        })
        ws.on('message', (data) => {
                console.log('received: %s', data);
        });
});
