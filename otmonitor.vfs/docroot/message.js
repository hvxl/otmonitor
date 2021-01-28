var wsurl = "ws" + document.URL.match("s?://[-a-zA-Z0-9.:_/]+/") + "message.ws"

if ("WebSocket" in window) {
   var ws = new WebSocket(wsurl);
} else if ("MozWebSocket" in window) {
   ws = new MozWebSocket(wsurl)
}

if (ws) {
  ws.onopen = function () {
    log = document.getElementById("log");
  }

  ws.onmessage = function (evt) {
    var scroll = tailing();
    log.innerHTML += evt.data + "\n";
    if (scroll) {
      var ypos = document.body.scrollHeight - document.body.clientHeight
      window.scrollTo(0, ypos)
    }
  }

  ws.onclose = function (evt) {
    log = null;
  }
}

// Check if the scrollbar is at the bottom
function tailing () {
  if (typeof window.pageYOffset != 'undefined') {
    // Most browsers
    var offset = window.pageYOffset
  } else {
    // IE
    var offset = document.body.scrollTop
  }
  return (offset == document.body.scrollHeight - document.body.clientHeight)
}
