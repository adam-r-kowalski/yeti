const ws = new WebSocket("ws://localhost:8080")

ws.onopen = (event) => {
        ws.send("ping")
}

ws.onmessage = (event) => {
        console.log(event.data)
}
