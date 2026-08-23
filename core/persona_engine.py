#!/usr/bin/env python3
"""
LeadSniper Persona & Response Engine
Generates authentic, human, non-spam replies with 100% clean, unbracketed, raw direct links.
"""
from typing import Dict, Any, List

class PersonaEngine:
    def __init__(self):
        pass

    def generate_reply(self, post: Dict[str, Any], analysis: Dict[str, Any], project: Dict[str, Any], persona_id: str = None) -> str:
        personas = project.get("personas", [])
        if not personas:
            personas = [{
                "id": "default",
                "name": "Helpful Peer",
                "template": "Awesome post u/{author}! Check out {url} for \"{title}\"."
            }]

        selected_persona = None
        if persona_id:
            for p in personas:
                if p.get("id") == persona_id:
                    selected_persona = p
                    break

        if not selected_persona:
            selected_persona = personas[0]

        author = post.get("author", "creator")
        raw_title = post.get("title", "this post")
        # Clean title for natural insertion (remove leading [Genre] tags and trailing (Extra info))
        import re
        clean_title = re.sub(r'^\[[^\]]*\]\s*', '', raw_title).strip()
        clean_title = re.sub(r'\s*\([^)]*\)\s*$', '', clean_title).strip()
        if not clean_title:
            clean_title = raw_title.strip()
        if len(clean_title) > 60:
            clean_title = clean_title[:57] + "..."

        url = project.get("product_url", "https://yourapp.com")
        action_phrase = analysis.get("action_phrase") or "streamline this workflow"
        feature = analysis.get("matched_feature") or "our free tools"

        template = selected_persona.get("template", "Hey u/{author}! Check out {url} for \"{title}\".")

        reply = template.format(
            author=author,
            title=clean_title,
            url=url,
            action_phrase=action_phrase,
            feature=feature
        )

        # STRICT QUALITY ENFORCEMENT: Strip any accidental brackets/parentheses around URL
        reply = reply.replace(f"({url})", f" {url} ")
        reply = reply.replace(f"[{url}]", f" {url} ")
        reply = reply.replace(f"**{url}**", f"{url}")
        
        # Clean up any double spacing
        import re
        reply = re.sub(r'  +', ' ', reply).strip()

        return reply

    def list_personas(self, project: Dict[str, Any]) -> List[Dict[str, str]]:
        return [{"id": p.get("id", "default"), "name": p.get("name", "Default Persona")} for p in project.get("personas", [])]
