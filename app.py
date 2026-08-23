#!/usr/bin/env python3
"""
LeadSniper CLI & Orchestrator
Usage:
  python3 app.py                # Launches Desktop GUI
  python3 app.py --cli          # Runs automated terminal scanner
  python3 app.py --project saas # Scans specific project
"""
import sys
import argparse
from pathlib import Path

from core.project_manager import ProjectManager
from core.rss_harvester import RssHarvester
from core.intent_analyzer import IntentAnalyzer
from core.persona_engine import PersonaEngine

def run_cli_scanner(project_id: str = None):
    pm = ProjectManager()
    if project_id:
        pm.set_active_project(project_id)
    project = pm.get_active_project()

    print(f"\n🎯 [LeadSniper] Starting Real-Time Community Radar")
    print(f"📦 Active Project: {project.get('name')} ({project.get('product_url')})")
    print(f"📡 Subreddits: {', '.join(project.get('subreddits', []))}")
    print("=" * 65)

    harvester = RssHarvester()
    analyzer = IntentAnalyzer()
    persona_engine = PersonaEngine()

    posts = harvester.harvest_project_leads(project)
    print(f"⚡ Harvested {len(posts)} total posts across active feeds.\n")

    hot_leads = []
    for post in posts:
        analysis = analyzer.analyze_post(post, project)
        if analysis["is_qualified"]:
            reply = persona_engine.generate_reply(post, analysis, project)
            hot_leads.append((post, analysis, reply))

    # Sort by intent score
    hot_leads.sort(key=lambda x: x[1]["intent_score"], reverse=True)

    for idx, (post, analysis, reply) in enumerate(hot_leads[:10], 1):
        print(f"[{idx}] {analysis['intent_level']} (Score: {analysis['intent_score']}%) | r/{post['subreddit']}")
        print(f"    Title: {post['title']}")
        print(f"    Author: u/{post['author']}")
        print(f"    Feature: {analysis['matched_feature']}")
        print(f"    Link: {post['permalink']}")
        print(f"    💬 Reply: {reply}\n" + "-" * 65)

    print(f"\n✅ Scan complete. Found {len(hot_leads)} qualified high-intent leads.")

def main():
    parser = argparse.ArgumentParser(description="LeadSniper — Autonomous Real-Time Lead Acquisition")
    parser.add_argument("--cli", action="store_true", help="Run scanner in terminal mode")
    parser.add_argument("--project", type=str, help="Specify project ID to scan (e.g. sunoget, saas_growth, video_ai_tool)")
    args = parser.parse_args()

    if args.cli or args.project:
        run_cli_scanner(args.project)
    else:
        try:
            from gui import LeadSniperApp
            app = LeadSniperApp()
            app.mainloop()
        except Exception as e:
            print(f"⚠️ GUI could not start ({e}). Falling back to CLI mode...")
            run_cli_scanner()

if __name__ == "__main__":
    main()
