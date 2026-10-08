#!/usr/bin/env python3
"""Local mock of OpenRouter /chat/completions for tests. Run: python3 mock_openrouter.py 8765
Use HOME=/tmp/... and OPENROUTER_BASE_URL=http://127.0.0.1:8765 (base only honoured in temp HOME).
Keys: test-key-not-real -> streams "Hello from the mock." ; bad -> 401 ; nocredit -> 402 ; ratelimit -> 429 ; slow -> stalls 70 s."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        if not self.path.endswith("/chat/completions"): self.send_error(404); return
        n=int(self.headers.get("Content-Length",0)); body=json.loads(self.rfile.read(n) or b"{}")
        key=(self.headers.get("Authorization") or "").replace("Bearer ","")
        codes={"bad":401,"nocredit":402,"ratelimit":429}
        if key in codes: self.send_response(codes[key]); self.end_headers(); self.wfile.write(b'{"error":"x"}'); return
        if key=="slow": time.sleep(70)
        self.send_response(200); self.send_header("Content-Type","text/event-stream"); self.end_headers()
        for w in ["Hello"," from"," the"," mock."]:
            self.wfile.write(("data: "+json.dumps({"choices":[{"delta":{"content":w}}]})+"\n\n").encode()); self.wfile.flush(); time.sleep(0.05)
        self.wfile.write(("data: "+json.dumps({"choices":[],"usage":{"cost":0.00042}})+"\n\n").encode())
        self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
HTTPServer(("127.0.0.1",int(sys.argv[1]) if len(sys.argv)>1 else 8765),H).serve_forever()
