// -*- tcl -*-
// The width of the image. Must be wide enough at the start for the legend
var width = 220
var height = 625
var timer
var refresh
var ref
var start
start = start || Date.now()
var span
span = span || 7200

const margin = 25
const ns = "http://www.w3.org/2000/svg"
const timefmt = new Intl.DateTimeFormat("sv", {timeStyle: "short"})

addEventListener("load", svginit)

var wsurl = "ws" + document.URL.match("s?://[-a-zA-Z0-9.:_/]+/") + "status.ws"
var ws = new WebSocket(wsurl)
ws.onopen = function () {
    animate()
}
ws.onclose = function (evt) {
    clearTimeout(timer)
}
ws.onmessage = function (evt) {
    var message = JSON.parse(evt.data)
    if (message.status) {
	for (const trace in message.status) {
	    value(trace, message.status[trace])
	}
    }
}

function svginit() {
    // Get a reference to the SVG image
    svg = document.rootElement
    width = svg.getAttribute("width")
    height = svg.getAttribute("height")
    // Adjust the time strings, in case the server has a different time zone
    let now = Date.now()
    for (let ms = Math.ceil(start / 300000) * 300000; ms < now; ms += 300000) {
	let text = svg.getElementById("label" + (Math.round(ms / 300000) % (span / 300)))
	if (text) {
	    text.textContent = timefmt.format(ms)
	}
    }
}

function animate() {
    cancelAnimationFrame(refresh)
    refresh = requestAnimationFrame(scroll)
    // Prevent multiple timers running
    clearTimeout(timer)
    // Update the graph every 5 seconds (corresponding to 1 pixel)
    let ms = 5000 - (Date.now() + skew) % 5000
    timer = setTimeout(animate, ms)
}

function scroll(ms) {
    // Round the position to the nearest second
    let pos = Math.round((ref + ms) / 1000) * 1000
    // Expect a multiple of 5 seconds
    let now = new Date(start + pos)
    // Limit the graph to 2 hours
    if (pos > span * 1000) {
	let dt = pos - span * 1000
	start += dt
	ref -= dt
	let dx = dt / 5000
	const vgrid = svg.querySelectorAll(".vgrid")
	for (const line of vgrid) {
	    line.points[0].x -= dx
	    line.points[1].x -= dx
	}
	const labels = svg.querySelectorAll(".time")
	for (const text of labels) {
	    text.setAttribute("x", text.getAttribute("x") - dx)
	}
	const traces = svg.querySelectorAll(".trace")
	for (const line of traces) {
	    for (var p of line.points) p.x -= dx
	    // Remove expired points
	    // Find first unexpired point
	    let len = line.points.length
	    let n = 0
	    while (n < len && line.points[n].x < margin) n++
	    if (len > 1 && n > 0) {
		// Move the previous point to the start of the graph
		line.points[--n].x = margin
		if (line.tagName == "polygon") {
		    if (line.points[n].y != line.points[0].y) {
			// Make the previous point the origin of the graph
			line.points[--n].x = margin
			line.points[n].y = line.points[0].y
		    }
		}
		// Delete obsolete points
		while (n > 0) line.points.removeItem(--n)
	    }
	}
    }
    if (width < span / 5 + margin) {
	// Calculate the new width
	width = Math.min(span / 5, Math.round(pos / 5000)) + margin
	// Resize the image
	svg.setAttribute("width", Math.max(220, width))
	// Extend the horizontal grid lines
	const hgrid = svg.querySelectorAll(".hgrid")
	for (const line of hgrid) {
	    // Grid lines are only expected to have 2 points
	    line.points[1].x = width
	}
    }
    // Update the vertical grid
    let marktime = new Date(Math.floor(now.getTime() / 300000) * 300000)
    // Multiple markers may have been missed while the browser tab was inactive
    while (marktime >= start) {
	let mark = Math.round(marktime.getTime() / 300000) % (span / 300)
	let name = "marker" + mark
	let line = svg.getElementById(name)
	let x = (marktime.getTime() - start) / 5000 + margin
	if (!line) {
	    line = document.createElementNS(ns, "polyline")
	    line.id = name
	    line.setAttribute("class", "vgrid")
	    line.style.stroke = "#eee"
	    line.style.fill = "none"
	    line.points.appendItem(svg.createSVGPoint())
	    line.points.appendItem(svg.createSVGPoint())
	    line.points[0].x = x
	    line.points[0].y = 0
	    line.points[1].x = x
	    line.points[1].y = height
	    /* SVGPoints are deprecated?
	    line.points.appendItem(new DOMPoint(x, 0))
	    line.points.appendItem(new DOMPoint(x, height))
	    */
	    // Insert the new marker before the horizontal grid lines
	    let refnode = svg.querySelector(".hgrid")
	    svg.insertBefore(line, refnode)
	    text = document.createElementNS(ns, "text")
	    text.id = "label" + mark
	    text.setAttribute("class", "time")
	    text.setAttributeNS(null, "x", x)
	    text.setAttributeNS(null, "y", height - 2)
	    text.setAttributeNS(null, "text-anchor", "middle")
	    text.style.fill = "black"
	    text.style.fontFamily = "DejaVu Sans"
	    text.style.fontSize = "10px"
	    text.appendChild(document.createTextNode(timefmt.format(marktime)))
	    svg.insertBefore(text, refnode)
	} else if (Math.abs(line.points[0].x - x) > 0.001) {
	    // Move the line
	    line.points[0].x = x
	    line.points[1].x = x
	    let text = svg.getElementById("label" + mark)
	    if (text) {
		text.setAttribute("x", x)
		text.textContent = timefmt.format(marktime)
	    }
	} else {
	    break
	}
	marktime.setTime(marktime.getTime() - 300000)
    }
    // Extend the traces
    const traces = svg.querySelectorAll(".trace")
    for (const line of traces) {
	const len = line.points.length
	if (len > 0) {
	    // Move the last point to the end of the graph
	    line.points[len - 1].x = width
	    if (len > 2 && line.tagName == "polygon") {
		if (line.points[len - 2].y != line.points[0].y) {
		    // Bit is "on"
		    line.points[len - 2].x = width
		}
	    }
	}
    }
}

function value(trace, value) {
    let line = svg.getElementById(trace)
    if (line) {
	Number(value)
	let x = (Date.now() + skew - start) / 5000 + margin
	let zero = +line.getAttribute("data-zero")
	let zoom = +line.getAttribute("data-zoom")
	let y = zero - value * zoom
	let len = line.points.length
	let point
	if (len == 0) {
	    // First value for this trace
	    if (line.tagName == "polygon") {
		point = line.points.appendItem(svg.createSVGPoint())
		point.x = x
		point.y = zero
	    }
	} else {
	    // Extend the last point to the current time
	    line.points[len - 1].x = x
	}
	if (line.tagName != "polygon") {
	    // Add a point at the new level and current time
	    point = line.points.appendItem(svg.createSVGPoint())
	    point.x = x
	    point.y = y
	} else {
	    if (len > 1 && line.points[len - 2].y != zero) {
		// Also extend the point before last to the current time
		line.points[len - 2].x = x
	    }
	    if (value != 0) {
		// Add a point at the new level and current time
		point = line.points.appendItem(svg.createSVGPoint())
		point.x = x
		point.y = y
		// Add a point at the new level to be moved later
		point = line.points.appendItem(svg.createSVGPoint())
		point.x = x
		point.y = y
		y = zero
	    }
	}
	// Add a final point that can be moved later
	point = line.points.appendItem(svg.createSVGPoint())
	point.x = x
	point.y = y
    }
}
