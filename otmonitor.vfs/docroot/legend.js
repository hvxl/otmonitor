function legend() {
    var svg = document.getElementById("image").contentDocument;
    if (svg) {
	var sw = document.getElementById("legend");
	var state = sw.checked ? "visible" : "hidden";
	var elems = svg.querySelectorAll(".legend");
	for (var i = 0; i < elems.length; i++) {
	    elems[i].style.visibility = state;
	}
    }
}

window.addEventListener("load", legend);
