#!/usr/bin/env python3
"""
LeadSniper Comprehensive Test Suite
Validates:
1. Zero API dependency RSS stream parsing
2. Project manager preset loading and switching
3. Intent analyzer scoring and negative keyword filtering
4. Persona engine link formatting (100% clean unbracketed URLs)
"""
import unittest
from pathlib import Path

from core.project_manager import ProjectManager
from core.rss_harvester import RssHarvester
from core.intent_analyzer import IntentAnalyzer
from core.persona_engine import PersonaEngine

class TestLeadSniper(unittest.TestCase):
    def setUp(self):
        self.base_dir = Path(__file__).resolve().parent
        self.pm = ProjectManager(self.base_dir)
        self.harvester = RssHarvester()
        self.analyzer = IntentAnalyzer()
        self.persona_engine = PersonaEngine()

    def test_presets_loaded(self):
        projects = self.pm.list_projects()
        self.assertGreaterEqual(len(projects), 3)
        ids = [p["id"] for p in projects]
        self.assertIn("sunoget", ids)
        self.assertIn("saas_growth", ids)
        self.assertIn("video_ai_tool", ids)

    def test_project_switching(self):
        self.assertTrue(self.pm.set_active_project("saas_growth"))
        proj = self.pm.get_active_project()
        self.assertEqual(proj["id"], "saas_growth")
        self.assertEqual(proj["product_url"], "https://yourapp.com")

    def test_intent_scoring_hot(self):
        self.pm.set_active_project("saas_growth")
        proj = self.pm.get_active_project()
        test_post = {
            "title": "Looking for any tool to automate my workflow dashboard?",
            "body": "Need help finding an alternative software to save time.",
            "author": "growth_hacker",
            "subreddit": "SaaS"
        }
        analysis = self.analyzer.analyze_post(test_post, proj)
        self.assertTrue(analysis["is_qualified"])
        self.assertGreaterEqual(analysis["intent_score"], 60)
        self.assertEqual(analysis["intent_level"], "HOT 🔥")

    def test_negative_keyword_disqualification(self):
        self.pm.set_active_project("saas_growth")
        proj = self.pm.get_active_project()
        test_post = {
            "title": "This tool is a scam avoid it",
            "body": "I got spammed and want a refund.",
            "author": "angry_user",
            "subreddit": "SaaS"
        }
        analysis = self.analyzer.analyze_post(test_post, proj)
        self.assertFalse(analysis["is_qualified"])
        self.assertEqual(analysis["intent_score"], 0)

    def test_clean_unbracketed_urls_in_reply(self):
        self.pm.set_active_project("saas_growth")
        proj = self.pm.get_active_project()
        test_post = {
            "title": "How to automate client reports?",
            "body": "Looking for an easy tool.",
            "author": "sarah_dev",
            "subreddit": "SideProject"
        }
        analysis = self.analyzer.analyze_post(test_post, proj)
        reply = self.persona_engine.generate_reply(test_post, analysis, proj)
        
        # Strict URL format verification
        self.assertIn("https://yourapp.com", reply)
        self.assertNotIn("[https://yourapp.com]", reply)
        self.assertNotIn("(https://yourapp.com)", reply)
        self.assertNotIn("**https://yourapp.com**", reply)

    def test_atom_xml_feed_parser(self):
        sample_xml = b"""<?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>t3_test123</id>
            <title>Best way to batch export tracks in Ableton?</title>
            <author><name>/u/producer_mike</name></author>
            <updated>2026-08-23T21:40:00+00:00</updated>
            <content type="html">&lt;p&gt;Need a tool to download stems quickly.&lt;/p&gt;</content>
            <link href="https://www.reddit.com/r/SunoAI/comments/test123" />
          </entry>
        </feed>"""
        posts = self.harvester.parse_atom_feed(sample_xml, "SunoAI")
        self.assertEqual(len(posts), 1)
        self.assertEqual(posts[0]["id"], "test123")
        self.assertEqual(posts[0]["author"], "producer_mike")
        self.assertIn("Ableton", posts[0]["title"])

if __name__ == "__main__":
    unittest.main()
