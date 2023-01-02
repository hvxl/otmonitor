var wsurl = "ws" + document.URL.match("s?://[-a-zA-Z0-9.:_/]+/") + "message.ws"
var log
const logmax = 1000000

if ("WebSocket" in window) {
   var ws = new WebSocket(wsurl);
} else if ("MozWebSocket" in window) {
   ws = new MozWebSocket(wsurl)
}

addEventListener("load", function () {
  log = document.getElementById("log")
  if (ws) {
    ws.onmessage = function (evt) {
      let scroll = tailing();
      log.innerText += evt.data + "\n";
      let len = log.innerText.length
      if (len > logmax) {
        let p = log.innerText.indexOf('\n', len - logmax) + 1
        log.innerText = log.innerText.substring(p)
      }
      if (scroll) {
        var ypos = document.body.scrollHeight - document.body.clientHeight
        window.scrollTo(0, ypos)
      }
    }
  }
})

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
