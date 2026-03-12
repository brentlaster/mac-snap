#!/usr/bin/env python3
"""
snap_dialog.py — Combined prefix + description dialog for snap-hotkey.sh

Usage:
    python3 snap_dialog.py \
        --prefixes "ai-sec,ai,fig" \
        --descriptions "calculator app,login page,git log output" \
        --default-prefix "ai-sec" \
        --ai-description "suggested caption" \
        --save-path "/path/to/project/images/ai-sec4.png" \
        --image-dir "/path/to/project/images"

Output (stdout, pipe-delimited):
    PREFIX|DESCRIPTION|IMAGE_DIR
    e.g.: ai-sec|calculator multiplication result|/Users/me/project/images

Exit codes:
    0 = user clicked Save (output on stdout)
    1 = user cancelled
"""

import argparse
import os
import sys
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefixes", default="", help="Comma-separated recent prefixes")
    parser.add_argument("--descriptions", default="", help="Comma-separated recent descriptions")
    parser.add_argument("--default-prefix", default="ai", help="Default prefix value")
    parser.add_argument("--ai-description", default="", help="AI-suggested description")
    parser.add_argument("--save-path", default="", help="Current full save path for display")
    parser.add_argument("--image-dir", default="", help="Current images directory")
    args = parser.parse_args()

    prefix_list = [p for p in args.prefixes.split(",") if p] if args.prefixes else []
    desc_list = [d for d in args.descriptions.split(",") if d] if args.descriptions else []
    default_prefix = args.default_prefix or (prefix_list[0] if prefix_list else "ai")
    ai_desc = args.ai_description
    save_path = args.save_path
    image_dir = args.image_dir

    try:
        import tkinter as tk
        from tkinter import ttk, filedialog
    except ImportError:
        # Fallback: if tkinter unavailable, use osascript
        print("tkinter not available", file=sys.stderr)
        sys.exit(1)

    result = {"prefix": None, "description": None, "image_dir": image_dir, "cancelled": True}

    root = tk.Tk()
    root.title("Snap Screenshot")
    root.attributes("-topmost", True)

    # macOS-friendly sizing
    root.geometry("520x290")
    root.resizable(False, False)

    # Center on screen
    root.update_idletasks()
    w = root.winfo_width()
    h = root.winfo_height()
    x = (root.winfo_screenwidth() // 2) - (w // 2)
    y = (root.winfo_screenheight() // 3) - (h // 2)
    root.geometry(f"+{x}+{y}")

    # ── Save path display ──
    path_frame = tk.Frame(root)
    path_frame.pack(fill="x", padx=15, pady=(15, 5))

    path_var = tk.StringVar(value=save_path)
    tk.Label(path_frame, text="Save to:", font=("system", 11, "bold")).pack(side="left")
    path_label = tk.Label(path_frame, textvariable=path_var, font=("system", 11), fg="#555555", anchor="w")
    path_label.pack(side="left", fill="x", expand=True, padx=(5, 0))

    def pick_folder():
        folder = filedialog.askdirectory(
            title="Choose project folder (images/ will be created inside it)",
            initialdir=os.path.dirname(result["image_dir"]) if result["image_dir"] else os.path.expanduser("~")
        )
        if folder:
            result["image_dir"] = os.path.join(folder, "images")
            # Update display path (we don't know the final filename yet, just show dir)
            prefix_val = prefix_combo.get().strip()
            path_var.set(f"{result['image_dir']}/{prefix_val}_.png")

    folder_btn = ttk.Button(path_frame, text="Change...", command=pick_folder, width=8)
    folder_btn.pack(side="right", padx=(5, 0))

    # ── Prefix field ──
    prefix_frame = tk.Frame(root)
    prefix_frame.pack(fill="x", padx=15, pady=(10, 5))

    tk.Label(prefix_frame, text="Prefix:", font=("system", 12)).pack(side="left")

    prefix_combo = ttk.Combobox(prefix_frame, values=prefix_list, font=("system", 13), width=25)
    prefix_combo.set(default_prefix)
    prefix_combo.pack(side="left", padx=(10, 0), fill="x", expand=True)

    # ── Description field ──
    desc_frame = tk.Frame(root)
    desc_frame.pack(fill="x", padx=15, pady=(10, 5))

    desc_label_text = "Description:"
    if ai_desc:
        desc_label_text = "Description (AI suggested):"

    tk.Label(desc_frame, text=desc_label_text, font=("system", 12)).pack(side="left")

    desc_combo = ttk.Combobox(desc_frame, values=desc_list, font=("system", 13), width=25)
    desc_combo.set(ai_desc)
    desc_combo.pack(side="left", padx=(10, 0), fill="x", expand=True)

    # ── Buttons ──
    btn_frame = tk.Frame(root)
    btn_frame.pack(fill="x", padx=15, pady=(20, 15))

    def on_cancel():
        result["cancelled"] = True
        root.destroy()

    def on_save(event=None):
        result["prefix"] = prefix_combo.get().strip()
        result["description"] = desc_combo.get().strip()
        result["cancelled"] = False
        root.destroy()

    cancel_btn = ttk.Button(btn_frame, text="Cancel", command=on_cancel, width=10)
    cancel_btn.pack(side="left")

    # Spacer
    tk.Frame(btn_frame).pack(side="left", fill="x", expand=True)

    save_btn = ttk.Button(btn_frame, text="Save", command=on_save, width=10)
    save_btn.pack(side="right")

    # Keyboard shortcuts
    root.bind("<Return>", on_save)
    root.bind("<Escape>", lambda e: on_cancel())

    # Focus the description field if AI filled it (user likely wants to review)
    # Otherwise focus the prefix field
    if ai_desc:
        desc_combo.focus_set()
        desc_combo.select_range(0, "end")
    else:
        prefix_combo.focus_set()
        prefix_combo.select_range(0, "end")

    # Bring window to front on macOS
    root.lift()
    root.after(1, lambda: root.focus_force())

    root.mainloop()

    if result["cancelled"] or not result["prefix"]:
        sys.exit(1)

    desc = result["description"] or f"{result['prefix']} screenshot"
    print(f"{result['prefix']}|{desc}|{result['image_dir']}")
    sys.exit(0)

if __name__ == "__main__":
    main()
