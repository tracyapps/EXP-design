// Third-party script (origin A).
//
// Its entire job is to prove the §4 iterative case: a script that is BLOCKED in
// pass 1 contributes nothing beyond its own URL to the manifest, but once
// ALLOWED it executes and requests resources from an origin (B) that pass 1
// could not possibly have known about. If the manifest does not grow after
// allowing this file, the two-pass model's central honesty claim is wrong and
// E1 gets rescoped.
(function () {
  var img = new Image();
  img.alt = "";
  img.src = "http://127.0.0.1:8733/tracker.svg";   // origin B — image
  img.width = 1; img.height = 1;
  document.body.appendChild(img);

  fetch("http://127.0.0.1:8733/config.json")        // origin B — XHR/fetch
    .then(function (r) { return r.json(); })
    .catch(function () { /* expected to fail while blocked */ });

  var note = document.createElement("p");
  note.setAttribute("data-fixture", "widget-ran");
  note.textContent = "widget.js executed";
  document.body.appendChild(note);
})();
