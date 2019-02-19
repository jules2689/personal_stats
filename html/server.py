#/usr/bin/env python

import os
import sys
import http.server
import socketserver

PORT = 8090

pid = str(os.getpid())
pidfile = "/tmp/mydaemon.pid"

if os.path.isfile(pidfile):
  print("%s already exists, exiting" % pidfile)
  sys.exit()

open(pidfile, 'w').write(pid)
try:
  Handler = http.server.SimpleHTTPRequestHandler
  httpd = socketserver.TCPServer(("", PORT), Handler)
  print("Serving at port", PORT)
  httpd.serve_forever()
finally:
    os.unlink(pidfile)
