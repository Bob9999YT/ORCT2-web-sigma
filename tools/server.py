import http.server
import socketserver

PORT = 8080

class HttpRequestHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        '': 'application/octet-stream',
        '.manifest': 'text/cache-manifest',
        '.html': 'text/html',
        '.png': 'image/png',
        '.jpg': 'image/jpg',
        '.svg':	'image/svg+xml',
        '.css':	'text/css',
        '.js':'application/x-javascript',
        '.wasm': 'application/wasm',
        '.json': 'application/json',
        '.xml': 'application/xml',
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        return super().end_headers()

httpd = socketserver.TCPServer(("0.0.0.0", PORT), HttpRequestHandler)

try:
    print(f"serving at http://0.0.0.0:{PORT}")
    httpd.serve_forever()
except KeyboardInterrupt:
    pass
