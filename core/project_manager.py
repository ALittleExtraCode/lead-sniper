#!/usr/bin/env python3
"""
LeadSniper Project Manager
Manages product/niche presets, active configuration, and custom project workspaces.
"""
import json
from pathlib import Path
from typing import Dict, Any, List

class ProjectManager:
    def __init__(self, base_dir: Path = None):
        if base_dir is None:
            base_dir = Path(__file__).resolve().parent.parent
        self.base_dir = Path(base_dir)
        self.presets_dir = self.base_dir / "presets"
        self.config_file = self.base_dir / "config.json"
        self.presets_dir.mkdir(parents=True, exist_ok=True)
        
        self.projects: Dict[str, Dict[str, Any]] = {}
        self.load_all_presets()
        self.active_project_id = self._get_default_active_id()

    def load_all_presets(self):
        self.projects.clear()
        for p_file in self.presets_dir.glob("*.json"):
            try:
                with open(p_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    p_id = data.get("id") or p_file.stem
                    self.projects[p_id] = data
            except Exception as e:
                print(f"⚠️ Error loading preset {p_file}: {e}")

    def _get_default_active_id(self) -> str:
        if self.config_file.exists():
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    active = cfg.get("active_project_id")
                    if active and active in self.projects:
                        return active
            except Exception:
                pass
        return list(self.projects.keys())[0] if self.projects else "default"

    def get_active_project(self) -> Dict[str, Any]:
        if self.active_project_id not in self.projects:
            self.load_all_presets()
        return self.projects.get(self.active_project_id, {
            "id": "default",
            "name": "Default Project",
            "product_url": "https://example.com",
            "subreddits": ["SaaS", "SideProject"],
            "keywords": ["tool", "recommend", "automate"],
            "personas": [
                {
                    "id": "default",
                    "name": "Helpful Peer",
                    "template": "Hey u/{author}! Check out {url} for \"{title}\"."
                }
            ]
        })

    def set_active_project(self, project_id: str) -> bool:
        if project_id in self.projects:
            self.active_project_id = project_id
            self.save_config()
            return True
        return False

    def save_project(self, project_data: Dict[str, Any]) -> str:
        p_id = project_data.get("id") or "project_" + str(len(self.projects) + 1)
        project_data["id"] = p_id
        target_path = self.presets_dir / f"{p_id}.json"
        with open(target_path, "w", encoding="utf-8") as f:
            json.dump(project_data, f, indent=2)
        self.projects[p_id] = project_data
        return p_id

    def save_config(self):
        with open(self.config_file, "w", encoding="utf-8") as f:
            json.dump({"active_project_id": self.active_project_id}, f, indent=2)

    def list_projects(self) -> List[Dict[str, str]]:
        return [{"id": pid, "name": p.get("name", pid)} for pid, p in self.projects.items()]
