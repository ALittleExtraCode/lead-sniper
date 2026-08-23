#!/usr/bin/env python3
"""
LeadSniper Local Web Server & API Backend
Provides REST & SSE real-time stream endpoints for the LeadSniper Web Interface.
Runs standalone with zero external dependencies (standard Python http.server).
"""
import http.server
import socketserver
import json
import urllib.parse
import sys
from pathlib import Path

from core.project_manager import ProjectManager
from core.rss_harvester import RssHarvester
from core.intent_analyzer import IntentAnalyzer
from core.persona_engine import PersonaEngine

BASE_DIR = Path(__file__).resolve().parent
PORT = 8080

pm = ProjectManager(BASE_DIR)
harvester = RssHarvester()
analyzer = IntentAnalyzer()
persona_engine = PersonaEngine()

class LeadSniperHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BASE_DIR), **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        
        # API: List all projects
        if parsed.path == "/api/projects":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            data = {
                "active_id": pm.active_project_id,
                "projects": pm.list_projects(),
                "active_project": pm.get_active_project()
            }
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return

        # API: Scan feeds for current project
        if parsed.path == "/api/scan":
            query = urllib.parse.parse_qs(parsed.query)
            proj_id = query.get("project", [pm.active_project_id])[0]
            if proj_id in pm.projects:
                pm.set_active_project(proj_id)
            
            project = pm.get_active_project()
            raw_posts = harvester.harvest_project_leads(project)
            
            leads = []
            for post in raw_posts:
                analysis = analyzer.analyze_post(post, project)
                if analysis["is_qualified"]:
                    replies = {}
                    for persona in project.get("personas", []):
                        pid = persona.get("id", "default")
                        replies[pid] = persona_engine.generate_reply(post, analysis, project, pid)
                    
                    leads.append({
                        "post": post,
                        "analysis": analysis,
                        "replies": replies
                    })

            leads.sort(key=lambda x: x["analysis"]["intent_score"], reverse=True)

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "count": len(leads),
                "project": project,
                "leads": leads
            }).encode("utf-8"))
            return

        # Fallback to static files (index.html, etc.)
        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        
        # API: Switch active project
        if parsed.path == "/api/switch-project":
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(body)
                proj_id = data.get("project_id")
                if pm.set_active_project(proj_id):
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "success", "active": pm.get_active_project()}).encode("utf-8"))
                    return
            except Exception as e:
                pass
            
            self.send_response(400)
            self.end_headers()
            return

        return super().do_POST()

def run_server(port=PORT):
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", port), LeadSniperHandler) as httpd:
        print(f"\n🚀 LeadSniper Web Server running at: http://localhost:{port}")
        print(f"📡 Serving live radar & API endpoints")
        print(f"⌨️  Press Ctrl+C to stop server.\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n🛑 Server stopped.")

if __name__ == "__main__":
    p = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    run_server(p)
