#!/bin/bash
set -e

# ============================================================================
# ZoomMeet Installer
# Installs all dependencies for zoommeet2 and the ZoomMeetApp GUI on macOS.
# ============================================================================

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_MODEL_DIR="$HOME/whisper-models"
WHISPER_MODEL_FILE="ggml-large-v3-turbo.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
WHISPER_PORT=8765
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/whisper.server.plist"

# --- Helpers ----------------------------------------------------------------

info()  { echo ""; echo "==> $1"; }
ok()    { echo "    ✅ $1"; }
skip()  { echo "    ⏭  $1 (already installed)"; }
warn()  { echo "    ⚠️  $1"; }
fail()  { echo "    ❌ $1"; exit 1; }

ask_yes_no() {
    # $1 = prompt, returns 0 for yes, 1 for no
    while true; do
        read -r -p "    $1 [y/n]: " yn
        case "$yn" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "    Please answer y or n." ;;
        esac
    done
}

# --- Pre-flight -------------------------------------------------------------

info "ZoomMeet Installer"
echo "    Install directory: $INSTALL_DIR"
echo ""
echo "    This script will install the dependencies for zoommeet2 and build"
echo "    the ZoomMeetApp GUI. It will ask before making major changes."
echo ""

# --- 1. Xcode Command Line Tools -------------------------------------------

info "Checking Xcode Command Line Tools..."
if xcode-select -p &>/dev/null; then
    skip "Xcode Command Line Tools"
else
    echo "    Xcode Command Line Tools are required (provides Swift, git, etc.)"
    echo "    A system dialog will appear — click 'Install' and wait for it to finish."
    xcode-select --install
    echo ""
    echo "    Press Enter once the installation is complete..."
    read -r
    if ! xcode-select -p &>/dev/null; then
        fail "Xcode Command Line Tools installation did not complete"
    fi
    ok "Xcode Command Line Tools installed"
fi

# --- 2. Homebrew ------------------------------------------------------------

info "Checking Homebrew..."
if command -v brew &>/dev/null; then
    skip "Homebrew"
else
    echo "    Homebrew is required to install sox, jq, BlackHole, and whisper-cpp."
    if ask_yes_no "Install Homebrew?"; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add brew to PATH for the rest of this script
        if [ -f /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    else
        fail "Homebrew is required. Please install it manually: https://brew.sh"
    fi
fi

# --- 3. SoX ----------------------------------------------------------------

info "Checking SoX (audio recording)..."
if command -v sox &>/dev/null; then
    skip "SoX"
else
    echo "    SoX is used for recording and combining audio."
    brew install sox
    ok "SoX installed"
fi

# --- 4. jq -----------------------------------------------------------------

info "Checking jq (JSON parser)..."
if command -v jq &>/dev/null; then
    skip "jq"
else
    brew install jq
    ok "jq installed"
fi

# --- 5. BlackHole 2ch ------------------------------------------------------

info "Checking BlackHole 2ch (virtual audio driver)..."
if system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole"; then
    skip "BlackHole 2ch"
else
    echo "    BlackHole is a virtual audio driver that captures system/Zoom audio."
    brew install blackhole-2ch
    ok "BlackHole 2ch installed"
    echo ""
    warn "You will need to log out and back in (or restart) for BlackHole to appear as an audio device."
    NEEDS_BLACKHOLE_SETUP=true
fi

# --- 6. Node.js -------------------------------------------------------------

info "Checking Node.js..."
if command -v node &>/dev/null; then
    skip "Node.js"
else
    echo "    Node.js is required for the Claude Code CLI."
    brew install node
    ok "Node.js installed"
fi

# --- 7. Claude Code CLI ----------------------------------------------------

info "Checking Claude Code CLI..."
if command -v claude &>/dev/null; then
    skip "Claude Code CLI"
else
    echo "    Claude Code CLI is used to summarize meeting transcripts."
    npm install -g @anthropic-ai/claude-code
    ok "Claude Code CLI installed"
fi

# --- 8. Python llm CLI (optional, for local LLM) --------------------------

info "Local LLM support (optional)"
echo ""
echo "    By default, ZoomMeet uses Claude Code to summarize transcripts."
echo "    If you'd prefer to use a local LLM (e.g. via LM Studio or Ollama),"
echo "    you can install the 'llm' CLI tool."
echo ""

if command -v llm &>/dev/null; then
    skip "llm CLI already installed"
else
    if ask_yes_no "Install the llm CLI tool for local LLM support?"; then
        pip3 install llm
        if command -v llm &>/dev/null; then
            ok "llm CLI installed"
        else
            warn "llm installed but not on PATH — you may need to add ~/.local/bin to your PATH"
        fi
    else
        echo "    Skipped — you can install it later with: pip install llm"
    fi
fi

# --- 9. Whisper: local vs remote ------------------------------------------

info "Whisper transcription setup"
echo ""
echo "    ZoomMeet uses a Whisper server for speech-to-text transcription."
echo "    You can either:"
echo "      1) Install whisper.cpp locally (requires ~1.6 GB model download)"
echo "      2) Use a remote Whisper server (you provide the URL)"
echo ""

WHISPER_MODE=""
WHISPER_API_KEY_VALUE=""
while true; do
    read -r -p "    Choose [1] local or [2] remote: " choice
    case "$choice" in
        1) WHISPER_MODE="local"; break ;;
        2) WHISPER_MODE="remote"; break ;;
        *) echo "    Please enter 1 or 2." ;;
    esac
done

if [ "$WHISPER_MODE" = "local" ]; then
    # --- 8a. Install whisper-cpp ---
    info "Checking whisper-cpp..."
    if command -v whisper-server &>/dev/null; then
        skip "whisper-cpp"
    else
        brew install whisper-cpp
        ok "whisper-cpp installed"
    fi

    # --- 8b. Download Whisper model ---
    info "Checking Whisper model..."
    if [ -f "$WHISPER_MODEL_DIR/$WHISPER_MODEL_FILE" ]; then
        skip "Whisper model ($WHISPER_MODEL_FILE)"
    else
        echo "    Downloading large-v3-turbo model (~1.6 GB)..."
        mkdir -p "$WHISPER_MODEL_DIR"
        curl -L --progress-bar -o "$WHISPER_MODEL_DIR/$WHISPER_MODEL_FILE" "$WHISPER_MODEL_URL"
        ok "Whisper model downloaded to $WHISPER_MODEL_DIR/$WHISPER_MODEL_FILE"
    fi

    # --- 8c. Install launchd plist ---
    info "Setting up Whisper server auto-start..."
    WHISPER_SERVER_BIN="$(command -v whisper-server)"
    MODEL_PATH="$WHISPER_MODEL_DIR/$WHISPER_MODEL_FILE"

    cat > "$LAUNCHD_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>whisper.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WHISPER_SERVER_BIN}</string>
        <string>-m</string>
        <string>${MODEL_PATH}</string>
        <string>--port</string>
        <string>${WHISPER_PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/whisper-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/whisper-server.err</string>
</dict>
</plist>
EOF

    # Load the plist (unload first if already loaded)
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
    launchctl load "$LAUNCHD_PLIST"
    ok "Whisper server configured to start on login (port $WHISPER_PORT)"

    WHISPER_URL_VALUE="http://localhost:${WHISPER_PORT}/inference"

else
    # --- Remote Whisper ---
    echo ""
    echo "    Enter the full URL of your remote Whisper server."
    echo "    It must accept POST requests with a 'file' field and 'response_format=verbose_json'."
    echo "    Example: http://myserver:8765/inference"
    echo ""
    read -r -p "    Whisper server URL: " WHISPER_URL_VALUE

    if [ -z "$WHISPER_URL_VALUE" ]; then
        fail "No URL provided"
    fi

    echo ""
    read -r -p "    API key for the remote server (press Enter if none): " WHISPER_API_KEY_VALUE
    ok "Using remote Whisper server: $WHISPER_URL_VALUE"
fi

# --- 10. ANTHROPIC_API_KEY -------------------------------------------------

info "Checking Anthropic API key..."
if [ -n "$ANTHROPIC_API_KEY" ]; then
    skip "ANTHROPIC_API_KEY is set"
else
    warn "ANTHROPIC_API_KEY is not set in your environment."
    echo "    Claude Code needs this to summarize transcripts."
    echo "    You can get a key from: https://console.anthropic.com/settings/keys"
    echo ""
    read -r -p "    Enter your API key (or press Enter to skip for now): " api_key
    if [ -n "$api_key" ]; then
        # Append to shell profile
        SHELL_RC="$HOME/.zshrc"
        if [ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ]; then
            SHELL_RC="$HOME/.bashrc"
        fi
        echo "" >> "$SHELL_RC"
        echo "export ANTHROPIC_API_KEY=\"$api_key\"" >> "$SHELL_RC"
        export ANTHROPIC_API_KEY="$api_key"
        ok "API key saved to $SHELL_RC"
    else
        warn "Skipped — you'll need to set ANTHROPIC_API_KEY before using zoommeet2"
    fi
fi

# --- 11. Configuration -----------------------------------------------------

info "Setting up configuration..."

CONFIG_FILE="$INSTALL_DIR/config.yaml"

if [ -f "$CONFIG_FILE" ]; then
    echo "    Existing config.yaml found — keeping it."
    # Update whisper_url if it changed
    if grep -q "^whisper_url:" "$CONFIG_FILE"; then
        sed -i '' "s|^whisper_url:.*|whisper_url: ${WHISPER_URL_VALUE}|" "$CONFIG_FILE"
    else
        echo "whisper_url: ${WHISPER_URL_VALUE}" >> "$CONFIG_FILE"
    fi
    if grep -q "^whisper_api_key:" "$CONFIG_FILE"; then
        sed -i '' "s|^whisper_api_key:.*|whisper_api_key: ${WHISPER_API_KEY_VALUE}|" "$CONFIG_FILE"
    else
        echo "whisper_api_key: ${WHISPER_API_KEY_VALUE}" >> "$CONFIG_FILE"
    fi
    ok "Updated whisper_url in config.yaml"
else
    echo ""
    echo "    Let's set up your config.yaml."
    echo ""

    read -r -p "    Your first name: " cfg_name
    cfg_name="${cfg_name:-User}"

    # List available microphones to help the user choose
    echo ""
    echo "    Available audio input devices:"
    system_profiler SPAudioDataType 2>/dev/null | grep "Device Name" | sed 's/.*Device Name: /        /' || true
    echo ""
    read -r -p "    Microphone device name (exact, case-sensitive): " cfg_mic
    cfg_mic="${cfg_mic:-MacBook Pro Microphone}"

    read -r -p "    Obsidian template path [~/Work/Templates/MeetingTemplate.md]: " cfg_template
    cfg_template="${cfg_template:-~/Work/Templates/MeetingTemplate.md}"

    read -r -p "    Meetings output directory [~/Work/Meetings]: " cfg_meetings
    cfg_meetings="${cfg_meetings:-~/Work/Meetings}"

    cat > "$CONFIG_FILE" << EOF
user_name: ${cfg_name}
microphone: ${cfg_mic}
obsidian_template: ${cfg_template}
meetings_dir: ${cfg_meetings}
whisper_url: ${WHISPER_URL_VALUE}
whisper_api_key: ${WHISPER_API_KEY_VALUE}
llm_command: claude -p --model sonnet
EOF
    ok "config.yaml created"
fi

# --- 12. Obsidian template --------------------------------------------------

info "Checking Obsidian template..."
# Expand ~ in the template path
TEMPLATE_PATH=$(grep "^obsidian_template:" "$CONFIG_FILE" | sed 's/^obsidian_template:[[:space:]]*//' | sed "s|^~|$HOME|")
MEETINGS_PATH=$(grep "^meetings_dir:" "$CONFIG_FILE" | sed 's/^meetings_dir:[[:space:]]*//' | sed "s|^~|$HOME|")

if [ -f "$TEMPLATE_PATH" ]; then
    skip "Template exists at $TEMPLATE_PATH"
else
    echo "    Creating default meeting template..."
    mkdir -p "$(dirname "$TEMPLATE_PATH")"
    cat > "$TEMPLATE_PATH" << 'EOF'
<% tp.date.now("YYYY-MM-DD") %>

# People

# Log

# Action Items
EOF
    ok "Template created at $TEMPLATE_PATH"
fi

mkdir -p "$MEETINGS_PATH"

# --- 13. Make script executable ---------------------------------------------

info "Checking zoommeet2 script..."
chmod +x "$INSTALL_DIR/zoommeet2"
ok "zoommeet2 is executable"

# --- 14. people.txt ---------------------------------------------------------

if [ ! -f "$INSTALL_DIR/llm_instructions.md" ]; then
    cat > "$INSTALL_DIR/llm_instructions.md" << 'LLMEOF'
You are summarizing a meeting transcript. Output EXACTLY two sections with these markers, nothing else:

LOG_START
- (3-10 bullet points summarizing the key discussion points of the meeting)
LOG_END

ACTIONS_START
- [ ] (action items that {{USER_NAME}} needs to do as a result of this meeting, with deadlines if mentioned)
ACTIONS_END

Rules:
- Brevity is key. After coming up with the LOG and the action items, check through again to see if any can be easily combined or eliminated.
- The Log section should have a few bullet points that describe the main topics of the meeting. Aim for no more than 1 bullet point per 1500 words of text, and violate this sparingly.
- Action items use the - [ ] checkbox format. Only include items for {{USER_NAME}}.
- If a deadline was mentioned, put it in parentheses at the end of the item.
- If there are no action items for {{USER_NAME}}, write: - [ ] No action items identified
- Brevity is key. After coming up with the LOG and the action items, check through again to see if any can be easily combined, eliminated, or reduced.
- Do not include anything outside the markers.
LLMEOF
    ok "Created llm_instructions.md (edit to customize Claude's summarization prompt)"
fi

if [ ! -f "$INSTALL_DIR/people.txt" ]; then
    touch "$INSTALL_DIR/people.txt"
    ok "Created empty people.txt (add entries like: Carlos [[Carlos Blanco]])"
fi

# --- 15. Build SwiftUI app -------------------------------------------------

info "Building ZoomMeetApp..."
if [ -d "$INSTALL_DIR/ZoomMeetApp" ]; then
    (cd "$INSTALL_DIR/ZoomMeetApp" && swift build -c release 2>&1)
    if [ $? -eq 0 ]; then
        ok "ZoomMeetApp built successfully"
        echo "    Binary: $INSTALL_DIR/ZoomMeetApp/.build/release/ZoomMeetApp"
    else
        warn "ZoomMeetApp build failed — you can still use the CLI script (zoommeet2)"
    fi
else
    warn "ZoomMeetApp directory not found — skipping GUI build"
fi

# --- Summary ----------------------------------------------------------------

info "Installation complete!"
echo ""
echo "    Usage:"
echo "      CLI:  cd $INSTALL_DIR && ./zoommeet2 Sam Carlos"
echo "      GUI:  cd $INSTALL_DIR/ZoomMeetApp && .build/release/ZoomMeetApp"
echo ""

# Print manual steps if needed
MANUAL_STEPS=false

if [ "${NEEDS_BLACKHOLE_SETUP:-false}" = true ]; then
    if [ "$MANUAL_STEPS" = false ]; then
        echo "    ⚠️  Manual steps remaining:"
        MANUAL_STEPS=true
    fi
    echo ""
    echo "    1. Log out and back in (or restart) for BlackHole to appear"
    echo "    2. Open Audio MIDI Setup (Spotlight > 'Audio MIDI Setup')"
    echo "    3. Click '+' > Create Multi-Output Device"
    echo "    4. Check both your speakers/headphones AND 'BlackHole 2ch'"
    echo "    5. Set this Multi-Output Device as your system output in"
    echo "       System Settings > Sound > Output"
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    if [ "$MANUAL_STEPS" = false ]; then
        echo "    ⚠️  Manual steps remaining:"
        MANUAL_STEPS=true
    fi
    echo ""
    echo "    - Set your Anthropic API key:"
    echo "      export ANTHROPIC_API_KEY=\"sk-ant-...\""
fi

echo ""
