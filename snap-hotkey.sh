#!/usr/bin/env bash
# snap-hotkey.sh — One-key screenshot → auto-name → markdown clipboard
#
# Triggered by a keyboard shortcut (via Automator Quick Action).
# 1. Opens macOS interactive screen capture (crosshair selector)
# 2. Optionally kicks off Ollama AI description in the background (--ai flag)
# 3. Shows a single combined dialog for prefix + description
# 4. Auto-numbers the file into <project>/images/
# 5. Copies the markdown reference to clipboard
#
# Usage:
#   snap-hotkey.sh          # Normal mode (no AI)
#   snap-hotkey.sh --ai     # Enable AI-suggested descriptions
#
# Requirements (for --ai mode only):
#   - Ollama running locally with a vision model
#   - Install: brew install ollama && ollama pull llama3.2-vision:11b

set -eo pipefail

# ── Ensure PATH includes common locations (Automator has a minimal PATH) ─
export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/miniconda3/bin:$HOME/.conda/bin:$PATH"

# ── Configuration ────────────────────────────────────────────────
DEFAULT_PROJECT_DIR="$HOME/Desktop"
HISTORY_FILE="$HOME/.snap_prefix_history"
DESC_HISTORY_FILE="$HOME/.snap_desc_history"
DIR_HISTORY_FILE="$HOME/.snap_dir_history"
MAX_HISTORY=10                           # Number of recent prefixes to keep
MAX_DESC_HISTORY=3                       # Number of recent descriptions to keep
OLLAMA_MODEL="llama3.2-vision:11b"       # Vision model for description
OLLAMA_URL="http://localhost:11434"      # Ollama API endpoint
AI_TIMEOUT=30                            # Seconds to wait for AI before skipping
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ─────────────────────────────────────────────────────────────────

# Parse flags
USE_AI=false
for arg in "$@"; do
    case "$arg" in
        --ai) USE_AI=true ;;
    esac
done

# Ensure history files exist
touch "$HISTORY_FILE"
touch "$DESC_HISTORY_FILE"
touch "$DIR_HISTORY_FILE"

# Cleanup helper
cleanup() {
    rm -rf "${TMPDIR_SNAP:-}"
    [[ -n "${AI_PID:-}" ]] && kill "$AI_PID" 2>/dev/null || true
}
trap cleanup EXIT

DEBUG_LOG="/tmp/snap_debug.log"
echo "$(date): Starting snap (AI=$USE_AI)" > "$DEBUG_LOG"

# ── Step 1: Take the screenshot interactively ────────────────────
TMPDIR_SNAP=$(mktemp -d /tmp/snap_XXXXXXXX)
TMPFILE="${TMPDIR_SNAP}/capture.png"

echo "Step 1: Taking screenshot..." >> "$DEBUG_LOG"
# Brief delay to let macOS settle focus when triggered via hotkey over certain apps
sleep 0.3
# Don't check screencapture's exit code — macOS can return non-zero
# even on success (e.g., when capturing certain apps). Just check the file.
# The "|| true" prevents set -e from killing the script.
screencapture -i "$TMPFILE" 2>>"$DEBUG_LOG" || true

if [[ ! -s "$TMPFILE" ]]; then
    echo "Screenshot file missing or empty (user cancelled or permission denied)" >> "$DEBUG_LOG"
    exit 0
fi
echo "Step 1: Screenshot captured ($(wc -c < "$TMPFILE") bytes)" >> "$DEBUG_LOG"

# ── Step 2: Optionally kick off AI description in the background ─
AI_RESULT_FILE="${TMPDIR_SNAP}/ai_description.txt"
echo "" > "$AI_RESULT_FILE"
AI_PID=""

if [[ "$USE_AI" == "true" ]]; then
    (
        if ! curl -s --max-time 2 "$OLLAMA_URL/api/tags" &>/dev/null; then
            echo "Ollama is NOT running" >> "$DEBUG_LOG"
            exit 0
        fi
        echo "Ollama is running" >> "$DEBUG_LOG"

        B64_FILE="${TMPDIR_SNAP}/image.b64"
        base64 -b 0 < "$TMPFILE" > "$B64_FILE" 2>/dev/null \
            || base64 -w 0 < "$TMPFILE" > "$B64_FILE" 2>/dev/null \
            || { base64 < "$TMPFILE" | tr -d '\n' > "$B64_FILE"; }

        JSON_FILE="${TMPDIR_SNAP}/request.json"
        PROMPT_FILE="${TMPDIR_SNAP}/prompt.txt"
        cat > "$PROMPT_FILE" <<'PROMPT_END'
You are labeling a screenshot for a software documentation image library.

Look at this screenshot carefully and write a short descriptive caption (3-8 words, lowercase).

Focus on WHAT is shown, being as specific as possible:
- If it shows code: mention the language, function/class name, or what the code does
- If it shows a terminal: mention the command, output, or error shown
- If it shows logs: mention the key log message or error type
- If it shows a UI: mention which specific panel, dialog, or page it is
- If it shows a diagram: mention what system or relationship it depicts
- If it shows an error: mention the specific error name or code

Good examples:
- python fastapi route handler
- git rebase conflict in terminal
- docker compose build output
- vscode debugger breakpoint hit
- nginx 502 bad gateway error
- react component rendering list
- postgres query execution plan
- kubernetes pod crashloop logs
- JWT token decode failure
- webpack bundle size analysis

Bad examples (too vague):
- code editor screenshot
- terminal output
- error message
- application window

Reply with ONLY the caption text, lowercase, no formatting. No quotes, no asterisks, no bold, no period, no explanation.
PROMPT_END

        python3 - "${OLLAMA_MODEL}" "${B64_FILE}" "${PROMPT_FILE}" "${JSON_FILE}" <<'BUILD_JSON'
import sys, json
model = sys.argv[1]
with open(sys.argv[2], "r") as f:
    img_b64 = f.read().strip()
with open(sys.argv[3], "r") as f:
    prompt = f.read().strip()
payload = {"model": model, "prompt": prompt, "images": [img_b64], "stream": False}
with open(sys.argv[4], "w") as f:
    json.dump(payload, f)
BUILD_JSON

        RESPONSE_FILE="${TMPDIR_SNAP}/response.json"
        curl -s --max-time "$AI_TIMEOUT" \
            -H "Content-Type: application/json" \
            -d @"$JSON_FILE" \
            -o "$RESPONSE_FILE" \
            "$OLLAMA_URL/api/generate" 2>>"$DEBUG_LOG" || true

        if [[ -s "$RESPONSE_FILE" ]]; then
            cp "$RESPONSE_FILE" /tmp/snap_last_response.json 2>/dev/null || true
            python3 - "$RESPONSE_FILE" "$AI_RESULT_FILE" <<'PARSE_JSON'
import sys, json, re
try:
    with open(sys.argv[1], "r") as f:
        data = json.load(f)
    resp = data.get("response", "").strip()
    resp = resp.replace("*", "")
    resp = re.sub(r"(?i)^(image description|caption|description|alt text)\s*:?\s*", "", resp)
    resp = re.sub(r"(?i)^(here is |here's )?(a |the )?(short |brief |concise )?(descriptive )?(caption|description|alt text)s?( for)?( the| this)?( screenshot| image)?[:\s]*", "", resp)
    resp = re.sub(r"(?i)^(this is |this shows |this appears to be |it shows |it is |a screenshot of |screenshot of |screenshot showing |an? )", "", resp)
    resp = re.sub(r"(?i)^(a screenshot of |screenshot of |screenshot showing |an? )", "", resp)
    resp = resp.strip('"').strip("'").strip()
    resp = resp.split("\n")[0]
    resp = resp.split(". ")[0]
    resp = resp.rstrip(".")
    resp = " ".join(resp.split()).lower()
    words = resp.split()
    if len(words) > 10:
        resp = " ".join(words[:8])
    with open(sys.argv[2], "w") as f:
        f.write(resp)
except Exception:
    with open(sys.argv[2], "w") as f:
        f.write("")
PARSE_JSON
        fi
    ) &
    AI_PID=$!
    echo "AI background PID: $AI_PID" >> "$DEBUG_LOG"
fi

echo "Step 3: Determining project directory..." >> "$DEBUG_LOG"
# Priority: 1) last saved dir from Change... button, 2) frontmost Finder window, 3) default
SAVED_DIR=$(head -1 "$DIR_HISTORY_FILE" 2>/dev/null || echo "")

if [[ -n "$SAVED_DIR" && -d "$SAVED_DIR" ]]; then
    PROJECT_DIR="$SAVED_DIR"
    echo "  Using saved dir: $PROJECT_DIR" >> "$DEBUG_LOG"
else
    echo "  Checking Finder..." >> "$DEBUG_LOG"
    PROJECT_DIR=$(osascript 2>/dev/null <<'FINDDIR'
tell application "Finder"
    if (count of windows) > 0 then
        return POSIX path of (target of front window as alias)
    else
        return ""
    end if
end tell
FINDDIR
) || ""
    echo "  Finder returned: '$PROJECT_DIR'" >> "$DEBUG_LOG"

    if [[ -z "$PROJECT_DIR" ]]; then
        PROJECT_DIR="$DEFAULT_PROJECT_DIR"
    fi
fi
PROJECT_DIR="${PROJECT_DIR%/}"
IMAGE_DIR="${PROJECT_DIR}/images"
echo "  Final: $IMAGE_DIR" >> "$DEBUG_LOG"

# ── Step 4: Load histories ───────────────────────────────────────
PREFIX_CSV=$(cat "$HISTORY_FILE" 2>/dev/null | head -n "$MAX_HISTORY" | paste -sd "," - || echo "")
DEFAULT_PREFIX=$(head -1 "$HISTORY_FILE" 2>/dev/null || echo "ai")
[[ -z "$DEFAULT_PREFIX" ]] && DEFAULT_PREFIX="ai"

DESC_CSV=$(cat "$DESC_HISTORY_FILE" 2>/dev/null | head -n "$MAX_DESC_HISTORY" | paste -sd "," - || echo "")

# ── Step 5: Wait for AI if enabled ───────────────────────────────
AI_DESCRIPTION=""
if [[ "$USE_AI" == "true" && -n "$AI_PID" ]]; then
    echo "Waiting for AI (PID $AI_PID)..." >> "$DEBUG_LOG"
    wait "$AI_PID" 2>/dev/null || true
    AI_PID=""
    if [[ -s "$AI_RESULT_FILE" ]]; then
        AI_DESCRIPTION=$(cat "$AI_RESULT_FILE")
    fi
    echo "AI description: '${AI_DESCRIPTION}'" >> "$DEBUG_LOG"
fi

# ── Step 6: Compute preview path for dialog ──────────────────────
mkdir -p "$IMAGE_DIR"
EXT="png"
PREVIEW_NUM=1
if ls "$IMAGE_DIR"/${DEFAULT_PREFIX}[0-9]*.${EXT} &>/dev/null; then
    HIGHEST=$(ls "$IMAGE_DIR"/${DEFAULT_PREFIX}[0-9]*.${EXT} \
        | sed -E "s|.*/${DEFAULT_PREFIX}([0-9]+)\.${EXT}|\1|" \
        | sort -n \
        | tail -1)
    PREVIEW_NUM=$((HIGHEST + 1))
fi
SAVE_PATH="${IMAGE_DIR}/${DEFAULT_PREFIX}${PREVIEW_NUM}.${EXT}"

# ── Step 7: Show combined dialog ─────────────────────────────────
DIALOG_ARGS=(
    --prefixes "$PREFIX_CSV"
    --descriptions "$DESC_CSV"
    --default-prefix "$DEFAULT_PREFIX"
    --save-path "$SAVE_PATH"
    --image-dir "$IMAGE_DIR"
)

if [[ -n "$AI_DESCRIPTION" ]]; then
    DIALOG_ARGS+=(--ai-description "$AI_DESCRIPTION")
fi

echo "Step 7: Launching dialog..." >> "$DEBUG_LOG"
echo "  python3 path: $(which python3)" >> "$DEBUG_LOG"
echo "  dialog script: ${SCRIPT_DIR}/snap_dialog.py" >> "$DEBUG_LOG"
echo "  args: ${DIALOG_ARGS[*]}" >> "$DEBUG_LOG"
DIALOG_OUTPUT=$(python3 "${SCRIPT_DIR}/snap_dialog.py" "${DIALOG_ARGS[@]}" 2>>"$DEBUG_LOG") || { echo "  Dialog exited with error or cancel" >> "$DEBUG_LOG"; exit 0; }

# Parse output: PREFIX|DESCRIPTION|IMAGE_DIR
PREFIX=$(echo "$DIALOG_OUTPUT" | cut -d'|' -f1)
DESCRIPTION=$(echo "$DIALOG_OUTPUT" | cut -d'|' -f2)
NEW_IMAGE_DIR=$(echo "$DIALOG_OUTPUT" | cut -d'|' -f3-)

if [[ -z "$PREFIX" ]]; then
    exit 0
fi

# Update image dir if user changed it via folder picker, and persist the choice
if [[ -n "$NEW_IMAGE_DIR" && "$NEW_IMAGE_DIR" != "$IMAGE_DIR" ]]; then
    IMAGE_DIR="$NEW_IMAGE_DIR"
    # Save the parent project dir (strip /images suffix) so it's used next time
    CHOSEN_PROJECT_DIR="${IMAGE_DIR%/images}"
    echo "$CHOSEN_PROJECT_DIR" > "$DIR_HISTORY_FILE"
    echo "Saved project dir: $CHOSEN_PROJECT_DIR" >> "$DEBUG_LOG"
fi
mkdir -p "$IMAGE_DIR"

# ── Step 8: Auto-number (uses final IMAGE_DIR after any folder change) ──
NEXT_NUM=1
if ls "$IMAGE_DIR"/${PREFIX}[0-9]*.${EXT} &>/dev/null; then
    HIGHEST=$(ls "$IMAGE_DIR"/${PREFIX}[0-9]*.${EXT} \
        | sed -E "s|.*/${PREFIX}([0-9]+)\.${EXT}|\1|" \
        | sort -n \
        | tail -1)
    NEXT_NUM=$((HIGHEST + 1))
fi

FILENAME="${PREFIX}${NEXT_NUM}.${EXT}"
DEST="${IMAGE_DIR}/${FILENAME}"

# ── Step 9: Move file to destination ─────────────────────────────
mv "$TMPFILE" "$DEST"

# ── Step 10: Update histories ────────────────────────────────────
# Prefix history
grep -vx "$PREFIX" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" 2>/dev/null || true
{ echo "$PREFIX"; head -n $((MAX_HISTORY - 1)) "${HISTORY_FILE}.tmp"; } > "$HISTORY_FILE"
rm -f "${HISTORY_FILE}.tmp"

# Description history
grep -vxF "$DESCRIPTION" "$DESC_HISTORY_FILE" > "${DESC_HISTORY_FILE}.tmp" 2>/dev/null || true
{ echo "$DESCRIPTION"; head -n $((MAX_DESC_HISTORY - 1)) "${DESC_HISTORY_FILE}.tmp"; } > "$DESC_HISTORY_FILE"
rm -f "${DESC_HISTORY_FILE}.tmp"

# ── Step 11: Build markdown reference ────────────────────────────
MD_REF="![${DESCRIPTION}](./images/${FILENAME}?raw=true \"${DESCRIPTION}\")"

# ── Step 12: Confirmation notification ───────────────────────────
osascript -e "display notification \"Saved ${FILENAME}\" with title \"Snap\" subtitle \"Markdown copied to clipboard\"" 2>/dev/null || true

# ── Step 13: Copy markdown reference to clipboard (LAST step) ────
echo -n "$MD_REF" | pbcopy
