#!/usr/bin/env python3
"""
LeadSniper Intent & Relevance Analyzer
Scores intent, filters negative keywords, detects matched features, and generates action context.
"""
import re
from typing import Dict, Any, Tuple, List

class IntentAnalyzer:
    def __init__(self):
        self.question_patterns = [
            r"\bhow (?:do|can|to)\b",
            r"\bis there (?:a|any)\b",
            r"\bany (?:tool|app|software|plugin|script|alternative)\b",
            r"\blooking for\b",
            r"\bneed help\b",
            r"\brecommend\b",
            r"\bwhat do you use\b",
            r"\bworkflow\b",
            r"\bproblem with\b",
            r"\bhow to\b"
        ]

    def analyze_post(self, post: Dict[str, Any], project: Dict[str, Any]) -> Dict[str, Any]:
        title = post.get("title", "")
        body = post.get("body", "")
        full_text = f"{title} {body}".lower()

        # 1. Negative Filter
        negative_keywords = [k.lower() for k in project.get("negative_keywords", [])]
        for neg in negative_keywords:
            if re.search(r"\b" + re.escape(neg) + r"\b", full_text):
                return {
                    "is_qualified": False,
                    "intent_score": 0,
                    "intent_level": "DISQUALIFIED",
                    "matched_keywords": [],
                    "matched_feature": None,
                    "action_phrase": ""
                }

        # 2. Keyword Matches
        keywords = [k.lower() for k in project.get("keywords", [])]
        matched_keywords = []
        for kw in keywords:
            if re.search(r"\b" + re.escape(kw) + r"\b", full_text):
                matched_keywords.append(kw)

        # 3. Question / Pain Point Detection
        is_question = any(re.search(p, full_text) for p in self.question_patterns)
        
        # 4. Feature Matching
        features = project.get("features", [])
        matched_feature = None
        for feat in features:
            triggers = feat.get("trigger_words", [])
            if any(re.search(r"\b" + re.escape(tr.lower()) + r"\b", full_text) for tr in triggers):
                matched_feature = feat.get("name")
                break

        if not matched_feature and features:
            matched_feature = features[0].get("name")

        # 5. Score Calculation
        score = len(matched_keywords) * 15
        if is_question:
            score += 35
        if len(title) > 10 and any(kw in title.lower() for kw in keywords):
            score += 25

        score = min(100, score)

        # 6. Intent Level
        if score >= 60:
            intent_level = "HOT 🔥"
        elif score >= 30:
            intent_level = "WARM ⚡"
        else:
            intent_level = "COOL ❄️"

        action_phrase = self._generate_action_phrase(matched_feature, matched_keywords, project)

        return {
            "is_qualified": len(matched_keywords) > 0 or is_question,
            "intent_score": score,
            "intent_level": intent_level,
            "matched_keywords": matched_keywords,
            "matched_feature": matched_feature or "Workflow Solution",
            "action_phrase": action_phrase
        }

    def _generate_action_phrase(self, feature: str, keywords: List[str], project: Dict[str, Any]) -> str:
        if not feature:
            return "streamline your creative workflow"
        
        feat_lower = feature.lower()
        if "batch" in feat_lower or "download" in feat_lower:
            return "batch-export and back up all master audio"
        elif "visualizer" in feat_lower or "video" in feat_lower:
            return "render audio-reactive 9:16 video visualizers"
        elif "daw" in feat_lower or "applet" in feat_lower:
            return "run in a dedicated desktop studio workspace"
        elif "namer" in feat_lower or "metadata" in feat_lower:
            return "auto-format track titles and ID3 streaming tags"
        elif "workflow" in feat_lower or "automate" in feat_lower:
            return "automate your repetitive pipeline"
        else:
            return f"use the {feature} feature"
