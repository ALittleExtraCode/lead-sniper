#!/usr/bin/env python3
"""
LeadSniper Desktop Control Center & Radar
Universal real-time lead acquisition, intent scoring, and 1-click assisted conversion app.
"""
import tkinter as tk
from tkinter import ttk, messagebox
import webbrowser
import subprocess
import threading
import time
from pathlib import Path
from typing import Dict, Any, List

from core.project_manager import ProjectManager
from core.rss_harvester import RssHarvester
from core.intent_analyzer import IntentAnalyzer
from core.persona_engine import PersonaEngine

class LeadSniperApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("🎯 LeadSniper — Autonomous Real-Time Growth & Lead Acquisition")
        self.geometry("1280x820")
        self.minsize(1080, 680)
        self.configure(bg="#0B0F19")

        # Core Engines
        self.project_mgr = ProjectManager()
        self.harvester = RssHarvester()
        self.analyzer = IntentAnalyzer()
        self.persona_engine = PersonaEngine()

        self.current_project = self.project_mgr.get_active_project()
        self.selected_persona_id = None
        self.leads_data: List[Dict[str, Any]] = []
        self.selected_lead = None
        self.is_scanning = False

        self._setup_styles()
        self._build_ui()
        
        # Initial scan
        self.after(500, self.trigger_live_scan)

    def _setup_styles(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        
        # Dark Theme Configuration
        style.configure(".", background="#0B0F19", foreground="#F8FAFC", font=("SF Pro Display", 11))
        style.configure("Treeview", 
                        background="#111827", 
                        foreground="#F1F5F9", 
                        fieldbackground="#111827",
                        rowheight=34,
                        font=("SF Pro Text", 10.5))
        style.configure("Treeview.Heading", 
                        background="#1E293B", 
                        foreground="#94A3B8", 
                        font=("SF Pro Display", 10, "bold"),
                        padding=6)
        style.map("Treeview", 
                  background=[("selected", "#2563EB")], 
                  foreground=[("selected", "#FFFFFF")])

    def _build_ui(self):
        # 1. TOP HEADER & PROJECT SWITCHER
        header_frame = tk.Frame(self, bg="#0F172A", height=70, padx=20, pady=12)
        header_frame.pack(fill=tk.X, side=tk.TOP)

        # Brand Logo & Title
        title_box = tk.Frame(header_frame, bg="#0F172A")
        title_box.pack(side=tk.LEFT, fill=tk.Y)
        
        lbl_brand = tk.Label(title_box, text="🎯 LeadSniper", font=("SF Pro Display", 18, "bold"), fg="#38BDF8", bg="#0F172A")
        lbl_brand.pack(side=tk.LEFT)
        lbl_sub = tk.Label(title_box, text=" | Universal Growth Engine", font=("SF Pro Text", 12), fg="#64748B", bg="#0F172A")
        lbl_sub.pack(side=tk.LEFT, padx=(4, 0))

        # Project Switcher Dropdown
        proj_box = tk.Frame(header_frame, bg="#0F172A")
        proj_box.pack(side=tk.LEFT, padx=30)
        
        tk.Label(proj_box, text="Active Project:", font=("SF Pro Text", 10, "bold"), fg="#94A3B8", bg="#0F172A").pack(side=tk.LEFT, padx=(0, 8))
        
        self.project_var = tk.StringVar(value=self.current_project.get("name", "Default"))
        self.project_names = [p["name"] for p in self.project_mgr.list_projects()]
        
        self.project_dropdown = ttk.Combobox(proj_box, textvariable=self.project_var, values=self.project_names, state="readonly", width=26)
        self.project_dropdown.pack(side=tk.LEFT)
        self.project_dropdown.bind("<<ComboboxSelected>>", self._on_project_switched)

        # Scan Controls
        ctrl_box = tk.Frame(header_frame, bg="#0F172A")
        ctrl_box.pack(side=tk.RIGHT)

        self.lbl_status = tk.Label(ctrl_box, text="● Radar Ready", font=("SF Pro Text", 10, "bold"), fg="#10B981", bg="#0F172A")
        self.lbl_status.pack(side=tk.LEFT, padx=(0, 15))

        btn_scan = tk.Button(ctrl_box, text="⚡ Scan Feeds", font=("SF Pro Text", 10, "bold"), bg="#2563EB", fg="#FFFFFF", activebackground="#1D4ED8", activeforeground="#FFFFFF", padx=14, pady=5, relief=tk.FLAT, cursor="hand2", command=self.trigger_live_scan)
        btn_scan.pack(side=tk.LEFT)

        # 2. MAIN SPLIT CONTAINER (Left: Leads Table, Right: Reply Studio)
        main_split = tk.PanedWindow(self, orient=tk.HORIZONTAL, bg="#0B0F19", sashrelief=tk.FLAT, sashwidth=4)
        main_split.pack(fill=tk.BOTH, expand=True, padx=16, pady=14)

        # === LEFT PANEL: RADAR LEADS STREAM ===
        left_panel = tk.Frame(main_split, bg="#111827", padx=12, pady=12)
        main_split.add(left_panel, minsize=520, width=640)

        # Filter bar
        filter_bar = tk.Frame(left_panel, bg="#111827")
        filter_bar.pack(fill=tk.X, pady=(0, 10))

        tk.Label(filter_bar, text="Filter Intent:", font=("SF Pro Text", 9, "bold"), fg="#94A3B8", bg="#111827").pack(side=tk.LEFT, padx=(0, 6))
        self.filter_var = tk.StringVar(value="ALL")
        for f_label, f_val in [("All", "ALL"), ("🔥 HOT", "HOT"), ("⚡ WARM+", "WARM")]:
            rb = tk.Radiobutton(filter_bar, text=f_label, variable=self.filter_var, value=f_val, bg="#111827", fg="#E2E8F0", selectcolor="#1E293B", activebackground="#111827", activeforeground="#38BDF8", command=self._render_leads_table)
            rb.pack(side=tk.LEFT, padx=4)

        self.lbl_lead_count = tk.Label(filter_bar, text="0 leads", font=("SF Pro Text", 9), fg="#64748B", bg="#111827")
        self.lbl_lead_count.pack(side=tk.RIGHT)

        # Leads Treeview Table
        tree_frame = tk.Frame(left_panel, bg="#111827")
        tree_frame.pack(fill=tk.BOTH, expand=True)

        columns = ("sub", "intent", "title", "author", "matched")
        self.tree = ttk.Treeview(tree_frame, columns=columns, show="headings", selectmode="browse")
        self.tree.heading("sub", text="Subreddit")
        self.tree.heading("intent", text="Intent Score")
        self.tree.heading("title", text="Post Title")
        self.tree.heading("author", text="Author")
        self.tree.heading("matched", text="Matched Feature")

        self.tree.column("sub", width=105, anchor="center")
        self.tree.column("intent", width=100, anchor="center")
        self.tree.column("title", width=270, anchor="w")
        self.tree.column("author", width=100, anchor="w")
        self.tree.column("matched", width=130, anchor="w")

        scrollbar = ttk.Scrollbar(tree_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.tree.bind("<<TreeviewSelect>>", self._on_lead_selected)

        # === RIGHT PANEL: CONTEXTUAL REPLY STUDIO ===
        right_panel = tk.Frame(main_split, bg="#0F172A", padx=16, pady=14)
        main_split.add(right_panel, minsize=480)

        # Panel Header
        tk.Label(right_panel, text="💬 Contextual Reply Studio", font=("SF Pro Display", 13, "bold"), fg="#F8FAFC", bg="#0F172A").pack(anchor="w")

        # Original Post Card
        self.post_card = tk.LabelFrame(right_panel, text=" Original Reddit Post ", font=("SF Pro Text", 9, "bold"), bg="#1E293B", fg="#94A3B8", padx=10, pady=8)
        self.post_card.pack(fill=tk.X, pady=(10, 12))

        self.lbl_selected_title = tk.Label(self.post_card, text="Select a lead from the left radar...", font=("SF Pro Text", 10.5, "bold"), fg="#E2E8F0", bg="#1E293B", wraplength=420, justify=tk.LEFT)
        self.lbl_selected_title.pack(anchor="w")

        self.lbl_selected_meta = tk.Label(self.post_card, text="r/-- • u/-- • Intent: --", font=("SF Pro Text", 9), fg="#38BDF8", bg="#1E293B")
        self.lbl_selected_meta.pack(anchor="w", pady=(3, 0))

        # Persona Switcher
        persona_bar = tk.Frame(right_panel, bg="#0F172A")
        persona_bar.pack(fill=tk.X, pady=(4, 8))

        tk.Label(persona_bar, text="Select Persona:", font=("SF Pro Text", 9, "bold"), fg="#94A3B8", bg="#0F172A").pack(side=tk.LEFT, padx=(0, 8))
        self.persona_btn_frame = tk.Frame(persona_bar, bg="#0F172A")
        self.persona_btn_frame.pack(side=tk.LEFT, fill=tk.X)

        # Generated Reply Box
        tk.Label(right_panel, text="Generated Non-Spam Reply (100% Clean Unbracketed URL):", font=("SF Pro Text", 9, "bold"), fg="#94A3B8", bg="#0F172A").pack(anchor="w")
        
        self.txt_reply = tk.Text(right_panel, height=8, bg="#1E293B", fg="#F8FAFC", insertbackground="#38BDF8", font=("SF Pro Text", 11), wrap=tk.WORD, padx=10, pady=8, relief=tk.FLAT)
        self.txt_reply.pack(fill=tk.BOTH, expand=True, pady=(6, 12))

        # Big 1-Click Action Button
        self.btn_action = tk.Button(right_panel, 
                                    text="🚀 Copy Reply & Open Reddit Post", 
                                    font=("SF Pro Display", 12, "bold"), 
                                    bg="#10B981", 
                                    fg="#FFFFFF", 
                                    activebackground="#059669", 
                                    activeforeground="#FFFFFF", 
                                    pady=10, 
                                    relief=tk.FLAT, 
                                    cursor="hand2", 
                                    command=self._execute_copy_and_open)
        self.btn_action.pack(fill=tk.X)

        self._render_persona_buttons()

    def _on_project_switched(self, event=None):
        name = self.project_var.get()
        for p in self.project_mgr.list_projects():
            if p["name"] == name:
                self.project_mgr.set_active_project(p["id"])
                self.current_project = self.project_mgr.get_active_project()
                self.selected_persona_id = None
                self._render_persona_buttons()
                self.trigger_live_scan()
                break

    def _render_persona_buttons(self):
        for child in self.persona_btn_frame.winfo_children():
            child.destroy()
        
        personas = self.persona_engine.list_personas(self.current_project)
        if not personas:
            return

        if not self.selected_persona_id:
            self.selected_persona_id = personas[0]["id"]

        for p in personas:
            p_id = p["id"]
            is_active = (p_id == self.selected_persona_id)
            btn = tk.Button(self.persona_btn_frame, 
                            text=p["name"], 
                            font=("SF Pro Text", 8.5, "bold" if is_active else "normal"),
                            bg="#2563EB" if is_active else "#1E293B",
                            fg="#FFFFFF" if is_active else "#94A3B8",
                            activebackground="#1D4ED8",
                            activeforeground="#FFFFFF",
                            padx=8, pady=3,
                            relief=tk.FLAT,
                            cursor="hand2",
                            command=lambda pid=p_id: self._select_persona(pid))
            btn.pack(side=tk.LEFT, padx=3)

    def _select_persona(self, pid: str):
        self.selected_persona_id = pid
        self._render_persona_buttons()
        self._update_reply_text()

    def trigger_live_scan(self):
        if self.is_scanning:
            return
        self.is_scanning = True
        self.lbl_status.config(text="● Harvesting Feeds...", fg="#F59E0B")
        
        threading.Thread(target=self._async_scan_worker, daemon=True).start()

    def _async_scan_worker(self):
        raw_posts = self.harvester.harvest_project_leads(self.current_project)
        processed = []
        for post in raw_posts:
            analysis = self.analyzer.analyze_post(post, self.current_project)
            if analysis["is_qualified"]:
                processed.append({
                    "post": post,
                    "analysis": analysis
                })
        
        # Sort by intent score
        processed.sort(key=lambda x: x["analysis"]["intent_score"], reverse=True)
        self.leads_data = processed
        self.after(0, self._on_scan_completed)

    def _on_scan_completed(self):
        self.is_scanning = False
        self.lbl_status.config(text=f"● Live ({len(self.leads_data)} leads)", fg="#10B981")
        self._render_leads_table()

    def _render_leads_table(self):
        self.tree.delete(*self.tree.get_children())
        filter_mode = self.filter_var.get()

        visible_count = 0
        for item in self.leads_data:
            post = item["post"]
            analysis = item["analysis"]
            score = analysis["intent_score"]

            if filter_mode == "HOT" and score < 60:
                continue
            if filter_mode == "WARM" and score < 30:
                continue

            visible_count += 1
            intent_badge = f"{analysis['intent_level']} ({score}%)"
            item_id = self.tree.insert("", tk.END, values=(
                f"r/{post['subreddit']}",
                intent_badge,
                post["title"],
                f"u/{post['author']}",
                analysis["matched_feature"]
            ))

        self.lbl_lead_count.config(text=f"{visible_count} visible leads")
        
        # Auto-select first if none selected
        children = self.tree.get_children()
        if children and not self.selected_lead:
            self.tree.selection_set(children[0])
            self._on_lead_selected(None)

    def _on_lead_selected(self, event):
        sel = self.tree.selection()
        if not sel:
            return
        
        idx = self.tree.index(sel[0])
        # Find matching lead
        filter_mode = self.filter_var.get()
        filtered = [l for l in self.leads_data if (filter_mode == "ALL" or (filter_mode == "HOT" and l["analysis"]["intent_score"] >= 60) or (filter_mode == "WARM" and l["analysis"]["intent_score"] >= 30))]
        
        if idx < len(filtered):
            self.selected_lead = filtered[idx]
            post = self.selected_lead["post"]
            analysis = self.selected_lead["analysis"]

            self.lbl_selected_title.config(text=post["title"])
            self.lbl_selected_meta.config(text=f"r/{post['subreddit']} • u/{post['author']} • Intent: {analysis['intent_level']} ({analysis['intent_score']}%) • Feature: {analysis['matched_feature']}")
            self._update_reply_text()

    def _update_reply_text(self):
        if not self.selected_lead:
            return
        post = self.selected_lead["post"]
        analysis = self.selected_lead["analysis"]
        reply = self.persona_engine.generate_reply(post, analysis, self.current_project, self.selected_persona_id)
        
        self.txt_reply.delete("1.0", tk.END)
        self.txt_reply.insert("1.0", reply)

    def _execute_copy_and_open(self):
        reply_content = self.txt_reply.get("1.0", tk.END).strip()
        if not reply_content or not self.selected_lead:
            messagebox.showwarning("No Lead Selected", "Please select a lead from the radar first!")
            return

        post = self.selected_lead["post"]
        url = post.get("permalink", "")

        # 1. Copy to macOS clipboard
        try:
            process = subprocess.Popen('pbcopy', env={'LANG': 'en_US.UTF-8'}, stdin=subprocess.PIPE)
            process.communicate(reply_content.encode('utf-8'))
        except Exception:
            self.clipboard_clear()
            self.clipboard_append(reply_content)

        # 2. Open Reddit in default browser
        if url:
            webbrowser.open(url)

        # Visual feedback badge
        self.btn_action.config(text="✅ Copied to Clipboard & Opened Reddit!", bg="#059669")
        self.after(2500, lambda: self.btn_action.config(text="🚀 Copy Reply & Open Reddit Post", bg="#10B981"))

if __name__ == "__main__":
    app = LeadSniperApp()
    app.mainloop()
