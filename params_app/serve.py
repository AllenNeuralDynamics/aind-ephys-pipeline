#!/usr/bin/env python3
"""Launch the AIND Ephys Pipeline Parameter Editor webapp.

Can be run from anywhere — it automatically serves from the repository root.
Works on all platforms (Linux, macOS, Windows).

Usage:
    python params_app/serve.py [PORT]
"""

import http.server
import os
import sys
import webbrowser

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

# Resolve repo root (parent of the directory containing this script)
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(script_dir)
os.chdir(repo_root)

url = f"http://localhost:{PORT}/params_app/"

print(f"Starting parameter editor at:\n  {url}\n")
print("Press Ctrl+C to stop.\n")

webbrowser.open(url)

handler = http.server.SimpleHTTPRequestHandler
with http.server.HTTPServer(("", PORT), handler) as httpd:
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
