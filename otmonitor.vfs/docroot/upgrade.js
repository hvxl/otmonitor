var output = document.getElementById("debug")

function debug(str) {
  if (output) output.innerHTML += str + "<BR>"
}

var wsurl = "ws" + document.URL.match("s?://[-a-zA-Z0-9.:_/]+/") + "upgrade.ws"

if ("WebSocket" in window) {
   debug("Using WebSocket")
   var ws = new WebSocket(wsurl);
} else if ("MozWebSocket" in window) {
   debug("Using MozWebSocket")
   ws = new MozWebSocket(wsurl)
} else {
   // WebSocket not supported by browser
   debug("No WebSocket support")
}

if (ws) {
  ws.onopen = function () {
    debug("Connected")
  }

  ws.onmessage = function (evt) {
    var message = JSON.parse(evt.data)
    for (var id in message) {
      debug("id=" + id + ", str=" + message[id])
      switch (id) {
       case "check":
        var ans = confirm(message[id])
        if (ans)
          ws.send("check ok")
        else
          ws.send("check cancel")
        break
       default:
        var e = document.getElementById(id)
        if (e) {
          switch (e.nodeName) {
           case "TD":
            e.innerHTML = message[id]
            break
           case "DIV":
            e.style.width = message[id] + "%"
            break
           case "INPUT":
            e.disabled = (message[id] != "enabled")
            break
          }
        }
      }
    }
  }

  ws.onclose = function (evt) {
    var e = document.getElementById("progbutton")
    e.disabled = true
    debug("Disconnected")
  }

  function fwprog(e) {
    if (ws.readyState === 1) {
      ws.send("program")
    } else {
      debug("Websocket not ready")
    }
  }
}
