var output = document.getElementById("debug")

function debug(str) {
    if (output) output.innerHTML += str + "<BR>"
}

function formatquery(url, json) {
    var query = [];
    for (var name in json) {
	if (Array.isArray(json[name])) {
	    for (var i = 0; i < json[name].length; i++) {
		query.push(name + "=" + json[name][i]);
	    }
	} else {
	    query.push(name + "=" + json[name]);
	}
    }
    return url + '?' + query.join('&');
}

var wsurl = "ws" + document.URL.match("s?://[-a-z0-9.:]+/") + "status.ws"
if (typeof query !== 'undefined') {
    wsurl = formatquery(wsurl, query);
}

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
	debug("Connected");
	if (typeof learn !== 'undefined') {
	    var cmd = ["learn"];
	    eval.apply(this, cmd.concat(learn));
	}
	change("websock", 1);
    }

    ws.onclose = function (evt) {
	debug("Disconnected")
	change("websock", 0);
    }

    ws.onmessage = function (evt) {
	var message = JSON.parse(evt.data)
	for (var section in message) {
	    switch (section) {
	      case "status":
	      case "config":
		for (var id in message[section]) {
		    change(id, message[section][id]);
		}
		break;
	      case "error":
	      case "gpio":
	      case "led":
		for (var id in message[section]) {
		    change(section + id, message[section][id]);
		}
		break;
	    }
	}
    }
}

function change(id, value) {
    var e = document.getElementById(id);
    if (e) {
	switch (e.nodeName) {
	  case "TD":
	    e.innerHTML = value;
	    break;
	  case "IMG":
	    if (value == 1) {
		var src = e.getAttribute("image1");
		if (src) {
		    e.src = src;
		} else {
		    e.className = "checkset";
		}
	    } else {
		var src = e.getAttribute("image0");
		if (src) {
		    e.src = src;
                } else {
		    e.className = "checkclr";
		}
	    }
	    break;
	  case "INPUT":
	    if (e.type == "checkbox") {
		e.checked = (value === 'true' || value === '1');
	    }
	    if (e.type == "text" || e.type == "number") {
		e.value = value;
		//e.onchange();
	    }
	    if (e.type == "range") {
		e.value = value;
		e.onchange();
	    }
	    break;
	  case "SELECT":
	    if (e.className == "dict") {
		e.options.length = 0;
		var list = value.split(" ");
		for (var i = 0; i < list.length;) {
		    var text = list[i++].replace(/\{(.*)\}/, "$1");
		    var value = list[i++];
		    e.add(new Option(text, value));
		}
	    } else {
		for (var i = 0; i < e.options.length; i++) {
		    if (e.options[i].value == value) {
			e.selectedIndex = i;
			break;
		    }
		}
		break;
	    }
	    e.onchange();
	    break;
	  default:
	    e.innerHTML = value;
	    break;
	}
    } else {
	e = document.getElementById(id + ':' + value);
	if (e && e.nodeName == "INPUT") {
	    e.checked = true;
	    if (e.name) {
		fieldsetradio(e.name);
	    }
	}
    }
}

function command() {
    if (ws.readyState === 1) {
	var args = Array.prototype.slice.call(arguments);
	args.unshift("command");
	ws.send(args.join(" "));
    }
    return false;
}

function config() {
    if (ws.readyState === 1) {
	var args = Array.prototype.slice.call(arguments);
	args.unshift("config");
	ws.send(args.join(" "));
    }
    return false;
}

function commandstr(id) {
    var e = document.getElementById(id);
    command(e.value);
    return false;
}

function toggle(w, cmd) {
    command(cmd + "=" + (w.checked ? "1" : "0"));
}

function flag(w, section, name) {
    config(section, name, w.checked);
}

function input(w, section, name) {
    config(section, name, w.value);
}

function seconds(w, section, name) {
    config(section, name, w.value * 1000);
} 

function sync(w, id) {
    var e = document.getElementById(id);
    e.value = w.value;
}

function setpoint(id, cmd) {
    var w = document.getElementById(id);
    command(cmd + "=" + w.value);
}

function setting(w, cmd) {
    command(cmd + "=" + w.value);
}

function fieldsetradio(name) {
    var elems = document.getElementsByName(name);
    for (var i = 0; i < elems.length; i++) {
	var w = elems[i].parentNode.parentNode;
	if (w.tagName == "FIELDSET") {
	    w.disabled = !elems[i].checked;
	}
    }
}

function buttonstate(w, button1, button2, button3) {
    if (button1) {
	var b = document.getElementById(button1);
	b.disabled = w.selectedIndex < 0;
    }
    if (button2) {
	var b = document.getElementById(button2);
	b.disabled = w.selectedIndex <= 0;
    }
    if (button3) {
	var b = document.getElementById(button3);
	b.disabled = w.selectedIndex < 0 || w.selectedIndex >= w.length - 1;
    }
}

function eval() {
    if (ws.readyState === 1) {
	var args = Array.prototype.slice.call(arguments);
	args.unshift("eval");
	ws.send(args.join(" "));
    }
    return false;
}

function selectmove(name1, name2, sort) {
    var w1 = document.getElementById(name1);
    var w2 = document.getElementById(name2);
    var select = w1.selectedIndex;
    var opt = new Option(w1.options[select].text, w1.options[select].value);
    w1.options[select] = null;
    if (sort === true) {
	var s = opt.text.toLowerCase()
	var target = 0;
	while (s > w2.options[target].text.toLowerCase()) target++;
    } else {
	var target = w2.selectedIndex;
	if (target < 0) target = w2.length;
    }
    w2.add(opt, target);
    w1.onchange();
    w2.onchange();
}

function selectorder(name, dir) {
    var w = document.getElementById(name);
    var select = w.selectedIndex;
    var target = select + dir;
    var opt = new Option(w.options[target].text, w.options[target].value);
    w.options[target] = null
    w.add(opt, select);
    w.onchange();
}

function selectlist(sel, section, name) {
    var w = document.getElementById(sel);
    var list = new Array;
    for (i = 0; i < w.options.length; i++) {
	list.push(w.options[i].value);
    }
    config(section, name, '{' + list.join(" ") + '}');
    popup(false);
}

function popup(sw) {
    var w = document.getElementById('popup');
    if (sw) {
	w.style.display = 'block';
    } else {
	w.style.display = 'none';
    }
}

function usersel(w) {
    document.getElementById("username").value = w.options[w.selectedIndex].text;
    document.getElementById("password").value = '';
    document.getElementById("confirm").value = '';
}

function usermod() {
    var w = document.getElementById("username");
    if (w.value == '') return
    var p1 = document.getElementById("password");
    var p2 = document.getElementById("confirm");
    if (p1.value != p2.value) {
	alert("Passwords don't match");
	return;
    }
    if (p1.value == '') {
	alert("Password may not be left empty");
	return;
    }
    var sel = document.getElementById("userlist");
    for (var i = 0; i < sel.options.length; i++) {
	if (sel.options[i].text == w.value) break;
    }
    if (i >= sel.options.length) {
	sel.add(new Option(w.value));
    }
    eval('security adduser', w.value, p1.value, 'rw');
}

function userdel() {
    var w = document.getElementById("username");
    if (w.value != '' && confirm("Delete user " + w.value + "?")) {
	var sel = document.getElementById("userlist");
	for (var i = 0; i < sel.options.length; i++) {
	    if (sel.options[i].text == w.value) {
		sel.remove(i);
		break;
	    }
	}
	eval('security deluser', w.value);
    }
}

function terminate(id) {
    var w = document.getElementById(id);
    var index = w.selectedIndex;
    if (index >= 0) {
	eval('server-' + w.options[index].value, 'terminate');
    }
}
