var output = document.getElementById("debug");
var connect = document.getElementById("connect");

function debug(str) {
    if (output) output.innerHTML += str + "<BR>";
}

var wsurl = "ws" + document.URL.match("s?://[-a-z0-9.:]+/") + "basic.ws";

if ("WebSocket" in window) {
   var websocket = new WebSocket(wsurl);
} else if ("MozWebSocket" in window) {
   var websocket = new MozWebSocket(wsurl);
}

websocket.onopen = function () {
  connect.src = "images/online.png";
};

websocket.onclose = function (evt) {
  connect.src = "images/offline.png";
};

websocket.onmessage = function(evt) {onMessage(evt)}

function onMessage(evt) {
    var message = JSON.parse(evt.data)
    for (var name in message) {
        var elem = document.getElementById(name)
        switch (elem.nodeName) {
          case "IMG":
            if (message[name] != 0) {
              elem.src = "images/" + name + "-on.png"
            } else {
              elem.src = "images/" + name + "-off.png"
            }
            break
          default:
            elem.innerHTML = message[name]
        }
    }
}

function invoke(cmd) {
    try {
        // Send the command through the websocket
        websocket.send(cmd);
        // If successful, don't submit the form
        return false;
    } catch(err) {
        // As a backup action proceed with submitting the form
        return true;
    }
}
