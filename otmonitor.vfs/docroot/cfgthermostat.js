var days = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
];
var months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];

function clock() {
    var now = new Date();
    // Friday 20 November 2015, 00:19
    var s = days[now.getDay()] + ' ' + now.getDate();
    s += ' ' + months[now.getMonth()] + ' ' + now.getFullYear();
    s += ', ' + twodig(now.getHours()) + ':' + twodig(now.getMinutes());
    document.getElementById('clock').innerHTML = s;
    // Update at the start of the next minute
    setTimeout(clock, 60000 - now.getTime() % 60000);
}

function twodig(i) {
    if (i < 10) {i = "0" + i};
    return i;
}

function setclock() {
    var now = new Date();
    var cmd = 'SC=' + now.getHours() + ':' + now.getMinutes() + '/';
    if (now.getDay() == 0) {
        cmd += '7';
    } else {
        cmd += now.getDay();
    }
    command(cmd);
    if (document.getElementById("clock,date").checked) {
	command("SR=21:" + (now.getMonth() + 1) + "," + now.getDate());
    }
    if (document.getElementById("clock,year").checked) {
	var y = now.getFullYear();
	command("SR=22:" + (y >> 8) + "," + (y % 256));
    }
}
