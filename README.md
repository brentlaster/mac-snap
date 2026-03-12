# mac-snap
Screen capture app to help with lab screenshots

# Snap Screenshot Tool

A macOS keyboard-shortcut-driven tool that captures screenshots, auto-names them with sequential numbering, and copies a ready-to-paste markdown image reference to your clipboard.

Designed for technical writers and developers who frequently capture screenshots for documentation and need consistent naming and quick markdown embedding.

## What It Does

When you press your configured hotkey (e.g., Cmd+Shift+1):

1. The macOS crosshair selector appears — drag to capture a region
2. A dialog appears with two combo-box fields:
   - **Prefix** — type a new prefix or pick from a dropdown of your recently used prefixes (e.g., `ai`, `ai-sec`, `fig`)
   - **Description** — type a caption or pick from your last 3 descriptions
3. The screenshot is auto-numbered and saved (e.g., `ai-sec4.png` if `ai-sec1.png` through `ai-sec3.png` already exist)
4. A markdown reference is copied to your clipboard, ready to paste:
   ```
   ![loading sources](./images/ai-sec4.png?raw=true "loading sources")
   ```
5. A macOS notification confirms the save

The dialog also shows the full save path and has a **Change...** button to pick a different project folder on the fly.

## Files

| File | Purpose |
|---|---|
| `snap-hotkey.sh` | Main bash script — handles screenshot capture, auto-numbering, history, AI, clipboard |
| `snap_dialog.py` | Python tkinter GUI — the combined prefix + description dialog |

Both files must be in the same directory.

## Requirements

- **macOS** (uses `screencapture`, `osascript`, `pbcopy`)
- **Python 3** with **tkinter** (ships with most Python installations on macOS)
- **Bash** (macOS built-in `/bin/bash` works fine)

To verify tkinter is available:
```bash
python3 -c "import tkinter; print('OK')"
```
If that fails, install it with:
```bash
brew install python-tk
```

### Optional: AI-Suggested Descriptions

If you want the tool to automatically suggest a description based on what the screenshot shows, you'll also need:

- **Ollama** — local LLM runtime
- A **vision model** (e.g., `llama3.2-vision:11b`)

Install with:
```bash
brew install ollama
ollama serve &
ollama pull llama3.2-vision:11b
```

## Installation

1. Create a scripts directory (or use any location you prefer):
   ```bash
   mkdir -p ~/scripts
   ```

2. Copy both files there:
   ```bash
   cp snap-hotkey.sh ~/scripts/snap-hotkey.sh
   cp snap_dialog.py ~/scripts/snap_dialog.py
   chmod +x ~/scripts/snap-hotkey.sh
   ```

3. Create an **Automator Quick Action** to bind it to a hotkey:
   - Open **Automator** → File → New → **Quick Action**
   - Set "Workflow receives **no input** in **any application**"
   - Drag in a **Run Shell Script** action
   - Set the shell dropdown to `/bin/bash`
   - Paste this line:
     ```bash
     ~/scripts/snap-hotkey.sh
     ```
     Or, to enable AI descriptions:
     ```bash
     ~/scripts/snap-hotkey.sh --ai
     ```
   - Save as **"Snap Screenshot"**

4. Assign a keyboard shortcut:
   - Go to **System Settings → Keyboard → Keyboard Shortcuts → Services** (or **General → Quick Actions** on newer macOS)
   - Find **"Snap Screenshot"** in the list
   - Click "none" next to it and press your desired shortcut (e.g., **Cmd+Shift+1**)

5. Grant permissions when prompted:
   - **Screen & Content Recording**: Grant to **Automator** (and **System Events** if prompted)
   - Add manually if needed: System Settings → Privacy & Security → Screen & Content Recording → click `+` → navigate to `/System/Library/CoreServices/Automator.app`

## Usage

### Basic (no AI)

```bash
# Via hotkey (after setup above)
# Just press Cmd+Shift+1 (or whatever you configured)

# Or from the command line
~/scripts/snap-hotkey.sh
```

### With AI descriptions

```bash
~/scripts/snap-hotkey.sh --ai
```

When `--ai` is enabled, the tool sends the screenshot to a local Ollama vision model in the background. The AI-suggested description pre-fills the description field in the dialog. You can accept it, edit it, or replace it entirely.

## Configuration

Edit the variables at the top of `snap-hotkey.sh`:

| Variable | Default | Description |
|---|---|---|
| `DEFAULT_PROJECT_DIR` | `$HOME/Desktop` | Fallback directory when no Finder window is open |
| `MAX_HISTORY` | `10` | Number of recent prefixes to keep in the dropdown |
| `MAX_DESC_HISTORY` | `3` | Number of recent descriptions to keep in the dropdown |
| `OLLAMA_MODEL` | `llama3.2-vision:11b` | Vision model for AI descriptions (only used with `--ai`) |
| `OLLAMA_URL` | `http://localhost:11434` | Ollama API endpoint |
| `AI_TIMEOUT` | `30` | Seconds to wait for AI response before skipping |

### PATH for Automator

The script includes a PATH export line that adds common Python/tool locations so Automator can find `python3`, `curl`, etc. If your Python is installed in a non-standard location, add its directory to this line near the top of `snap-hotkey.sh`:

```bash
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/miniconda3/bin:$HOME/.conda/bin:$PATH"
```

## How the Save Location Is Determined

The tool uses this priority for deciding where to save:

1. If you click **Change...** in the dialog and pick a folder, that folder is used
2. Otherwise, if a **Finder window** is open, its directory is used
3. Otherwise, `DEFAULT_PROJECT_DIR` (defaults to `~/Desktop`) is used

In all cases, an `images/` subdirectory is created inside the chosen folder, and the screenshot is saved there.

## How Auto-Numbering Works

The tool looks at existing files in the target `images/` directory matching the pattern `{prefix}[0-9]*.png`, finds the highest number, and increments by one. For example:

- If `images/` contains `ai-sec1.png`, `ai-sec2.png`, `ai-sec3.png` → next file is `ai-sec4.png`
- If `images/` contains `ai1.png`, `ai5.png` → next file is `ai6.png` (uses highest, not count)
- Different prefixes don't collide: `ai` files are numbered independently from `ai-sec` files

## History Files

The tool stores recent prefixes and descriptions in plain text files:

| File | Contents |
|---|---|
| `~/.snap_prefix_history` | Recent prefixes, one per line (most recent first) |
| `~/.snap_desc_history` | Recent descriptions, one per line (most recent first) |

These are simple text files you can edit or delete at any time.

## Debug Log

Each run writes a debug log to `/tmp/snap_debug.log`. If something isn't working as expected, check this file:

```bash
cat /tmp/snap_debug.log
```

When using `--ai`, the last Ollama response is also saved to `/tmp/snap_last_response.json`.

## Troubleshooting

**Dialog doesn't appear after screenshot (Automator)**: Automator runs scripts with a minimal PATH that doesn't include Homebrew or conda. The script adds common paths automatically (`/opt/homebrew/bin`, `$HOME/miniconda3/bin`, etc.), but if your `python3` is installed somewhere else, add its directory to the `export PATH=` line near the top of `snap-hotkey.sh`. You can find your Python's location with `which python3` in Terminal.

**"Screen Recording" permission popups**: Grant permission to **Automator** (not just Terminal) in System Settings → Privacy & Security → Screen & Content Recording. If Automator isn't listed, click `+` and navigate to `/System/Library/CoreServices/Automator.app`. You may also need to add **System Events** at `/System/Library/CoreServices/System Events.app`. After adding, toggle the permission off and back on, then log out and back in.

**tkinter not found**: The fix depends on how Python is installed:
- **Homebrew Python**: `brew install python-tk`
- **Conda/Miniconda**: `conda install tk`
- **System Python**: tkinter should be included, but if not, install the Xcode Command Line Tools with `xcode-select --install`

**AI descriptions not appearing**: Check that Ollama is running (`ollama serve`), the model is pulled (`ollama pull llama3.2-vision:11b`), you're using the `--ai` flag, and review `/tmp/snap_debug.log` for errors. The last raw AI response is saved to `/tmp/snap_last_response.json` for inspection.

**Dialog doesn't appear on top**: This can happen occasionally with macOS window management. The dialog sets itself to "always on top" but if it's still hidden, click on the Python icon that appears in the Dock.
