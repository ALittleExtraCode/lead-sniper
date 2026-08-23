#!/usr/bin/env python3
"""
LeadSniper RSS Harvester
Universal zero-API real-time Reddit Atom/RSS XML stream parser.
"""
import urllib.request
import xml.etree.ElementTree as ET
import html
import re
import datetime
from typing import List, Dict, Any

import ssl

import random

class RssHarvester:
    def __init__(self, user_agent: str = None):
        self.custom_ua = user_agent
        self.seen_ids = set()
        try:
            self.ssl_ctx = ssl.create_default_context()
        except Exception:
            self.ssl_ctx = ssl._create_unverified_context()

    def _get_headers(self) -> Dict[str, str]:
        if self.custom_ua:
            ua = self.custom_ua
        else:
            build = random.randint(100, 130)
            rev = random.randint(1000, 9999)
            ua = f"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{build}.0.{rev}.0 Safari/537.36 LeadSniper/{build}"
        
        return {
            "User-Agent": ua,
            "Accept": "application/atom+xml,application/xml,text/xml;q=0.9,*/*;q=0.8",
            "Cache-Control": "no-cache"
        }

    def fetch_subreddit_posts(self, subreddit: str, limit: int = 25) -> List[Dict[str, Any]]:
        url = f"https://www.reddit.com/r/{subreddit}/new.rss?limit={limit}"
        headers = self._get_headers()
        
        req = urllib.request.Request(url, headers=headers)
        posts = []
        try:
            with urllib.request.urlopen(req, timeout=8, context=self.ssl_ctx) as resp:
                xml_data = resp.read()
                posts = self.parse_atom_feed(xml_data, subreddit)
        except Exception as e:
            # Retry with unverified SSL if certifi chain issue
            try:
                unverified_ctx = ssl._create_unverified_context()
                with urllib.request.urlopen(req, timeout=8, context=unverified_ctx) as resp:
                    xml_data = resp.read()
                    posts = self.parse_atom_feed(xml_data, subreddit)
            except Exception as e2:
                print(f"⚠️ Could not fetch r/{subreddit}: {e2}")
        return posts

    def parse_atom_feed(self, xml_bytes: bytes, subreddit: str) -> List[Dict[str, Any]]:
        posts = []
        try:
            root = ET.fromstring(xml_bytes)
            # Atom namespaces
            ns = {'atom': 'http://www.w3.org/2005/Atom'}
            
            entries = root.findall('atom:entry', ns)
            for entry in entries:
                id_elem = entry.find('atom:id', ns)
                title_elem = entry.find('atom:title', ns)
                author_elem = entry.find('atom:author/atom:name', ns)
                updated_elem = entry.find('atom:updated', ns)
                content_elem = entry.find('atom:content', ns)
                link_elem = entry.find('atom:link', ns)

                raw_id = id_elem.text if id_elem is not None else ""
                post_id = raw_id.split('_')[-1] if '_' in raw_id else raw_id

                title = html.unescape(title_elem.text) if title_elem is not None and title_elem.text else ""
                author = author_elem.text.replace("/u/", "").replace("u/", "") if author_elem is not None and author_elem.text else "creator"
                updated_str = updated_elem.text if updated_elem is not None else ""
                
                permalink = link_elem.attrib.get('href', '') if link_elem is not None else f"https://www.reddit.com/r/{subreddit}/comments/{post_id}"

                content_html = content_elem.text if content_elem is not None and content_elem.text else ""
                # Strip HTML tags from content
                clean_text = re.sub(r'<[^>]+>', ' ', html.unescape(content_html))
                clean_text = re.sub(r'\s+', ' ', clean_text).strip()

                posts.append({
                    "id": post_id,
                    "subreddit": subreddit,
                    "title": title,
                    "author": author,
                    "body": clean_text,
                    "permalink": permalink,
                    "created_utc": updated_str,
                    "timestamp": self._parse_iso_time(updated_str)
                })
        except Exception as e:
            print(f"⚠️ XML parse error: {e}")
        return posts

    def _parse_iso_time(self, iso_str: str) -> float:
        if not iso_str:
            return datetime.datetime.now().timestamp()
        try:
            # Format: 2026-08-23T21:45:00+00:00
            clean_iso = iso_str.replace("Z", "+00:00")
            dt = datetime.datetime.fromisoformat(clean_iso)
            return dt.timestamp()
        except Exception:
            return datetime.datetime.now().timestamp()

    def harvest_project_leads(self, project: Dict[str, Any]) -> List[Dict[str, Any]]:
        subreddits = project.get("subreddits", ["SaaS"])
        if not subreddits:
            return []
            
        all_posts = []
        
        # 1. Try single combined multi-subreddit request (Ultra-fast & immune to 429)
        combined_sub = "+".join(subreddits[:8])
        posts = self.fetch_subreddit_posts(combined_sub, limit=50)
        if posts:
            all_posts.extend(posts)
        else:
            # Fallback to individual
            import time
            for sub in subreddits:
                sub_posts = self.fetch_subreddit_posts(sub, limit=20)
                all_posts.extend(sub_posts)
                time.sleep(0.5)
            
        # Deduplicate
        unique_posts = []
        seen = set()
        for p in all_posts:
            if p["id"] and p["id"] not in seen:
                seen.add(p["id"])
                unique_posts.append(p)
                
        # Sort newest first
        unique_posts.sort(key=lambda x: x.get("timestamp", 0), reverse=True)
        return unique_posts
