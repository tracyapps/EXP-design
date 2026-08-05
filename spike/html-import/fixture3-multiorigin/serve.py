#!/usr/bin/env python3
"""Three local origins for HTML-import spike fixture 3.

    127.0.0.1:8731  docroot      — the document's own origin (pre-allowed per §4)
    127.0.0.1:8732  thirdparty   — origin A: stylesheet, webfont, image, script
    127.0.0.1:8733  thirdparty-b — origin B: reachable ONLY once origin A's
                                   widget.js is allowed and executes

Same host, different ports, so these are genuinely distinct origins — which also
checks that the manifest groups by scheme+host+PORT and not by host alone.

    python3 serve.py            # runs until ^C
    open http://127.0.0.1:8731/ # to eyeball it outside the importer

Everything is loopback and offline. The one non-loopback URL in the fixture
(fonts.googleapis.com) and the one that never resolves (bücher.example) are there
to be LISTED in the manifest, not fetched.
"""

import functools
import http.server
import os
import threading

HERE = os.path.dirname(os.path.abspath(__file__))

ORIGINS = [
    (8731, "docroot"),
    (8732, "thirdparty"),
    (8733, "thirdparty-b"),
]


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Cross-origin reads have to be permitted or the fixture fails for a
        # reason that has nothing to do with what it is testing.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        # A request log is the ground truth for "pass 1 fetched the document and
        # NOTHING else." Keep it, prefixed with the port that served it.
        print("[%s] %s" % (self.server.server_address[1], fmt % args), flush=True)


def serve(port, directory):
    handler = functools.partial(Handler, directory=os.path.join(HERE, directory))
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    print("serving %-14s on http://127.0.0.1:%d/" % (directory, port), flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    threads = [threading.Thread(target=serve, args=o, daemon=True) for o in ORIGINS]
    for t in threads:
        t.start()
    print("\nready — document is http://127.0.0.1:8731/  (^C to stop)\n", flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        print("\nstopped")
