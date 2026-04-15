# ZoomMeet Setup Guide

ZoomMeet records Zoom meetings, transcribes them with Whisper, summarizes them with Claude, and saves structured notes to Obsidian. It can be used as a command-line script (`zoommeet2`) or a GUI app (`ZoomMeetApp`).

## Quick Start

```bash
chmod +x install.sh
./install.sh
```

The installer handles most of the setup automatically. It will check for existing installations and skip anything already present. The rest of this document covers what the installer does and the manual steps it cannot automate.

## What the Installer Does

The installer will prompt you for choices along the way. It installs:

- **Homebrew** (if not present) — package manager for everything else
- **SoX** — audio recording and mixing
- **jq** — JSON parsing
- **BlackHole 2ch** — virtual audio loopback driver
- **Node.js** and **Claude Code CLI** — meeting summarization
- **llm CLI** (optional) — for using a local LLM instead of Claude
- **Whisper** (local or remote) — speech-to-text transcription
- **ZoomMeetApp** — builds the SwiftUI GUI

It also generates `config.yaml` (prompting for your name, microphone, and Obsidian paths) and creates a default Obsidian meeting template if one doesn't exist.

## Manual Steps

These steps cannot be automated and must be done by hand.

### 1. Set Up the Multi-Output Audio Device

BlackHole is a virtual audio driver that captures system audio (what you hear from Zoom) so it can be recorded. For this to work while you still hear the audio yourself, you need a Multi-Output Device that sends audio to both your speakers and BlackHole simultaneously.

**After installing BlackHole, you must log out and back in (or restart) for it to appear.**

Then:

1. Open **Audio MIDI Setup** (press Cmd+Space, type "Audio MIDI Setup")
2. Click the **+** button in the bottom-left corner
3. Select **Create Multi-Output Device**
4. Check both:
   - Your normal output (e.g., "MacBook Pro Speakers" or your headphones)
   - **BlackHole 2ch**
5. Make sure your normal output is listed **first** (drag to reorder if needed)
6. Optionally rename it (e.g., "Zoom + Record") by double-clicking the name

Then set it as your output:

1. Open **System Settings > Sound > Output**
2. Select the Multi-Output Device you just created

You can also hold **Option** and click the volume icon in the menu bar to quickly switch.

> **Note:** The macOS volume slider does not work with Multi-Output Devices. Adjust volume on your physical device or within individual apps.

### 2. Get an Anthropic API Key

Claude Code requires an Anthropic API key to summarize transcripts.

1. Go to https://console.anthropic.com/settings/keys
2. Create a new key
3. Add it to your shell profile:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-YOUR-KEY"' >> ~/.zshrc
source ~/.zshrc
```

The installer will prompt you for this, but you can also set it up later.

### 3. Configure Your Microphone

The installer will list your available audio input devices and ask you to choose one. If you need to change it later, edit `config.yaml`:

```yaml
microphone: Brio 505
```

The name must exactly match the Core Audio device name (case-sensitive). To see available devices:

```bash
system_profiler SPAudioDataType | grep "Device Name"
```

### 4. Set Up Zoom's Audio Output

For ZoomMeet to capture Zoom audio, Zoom must send its audio through the Multi-Output Device:

1. Open **Zoom > Settings > Audio**
2. Set **Speaker** to your Multi-Output Device (e.g., "Zoom + Record"), or "Same as System" if you set it as the system default

### 5. Customize people.txt (Optional)

Add frequently-used attendee names to `people.txt` for autocomplete in the GUI and Obsidian wiki-link resolution in meeting notes:

```
Karl [[Karl Marx]]
Barack [[Barack Obama]]
Marie [[Marie Curie]]
```

Format: `ShortName [[Obsidian Page Name]]`, one per line. The short name is what you type; the wiki-link is what appears in the meeting note.

## Configuration Reference

All configuration is in `config.yaml` in the same directory as the script:

```yaml
user_name: Tim                                         # Your first name (used in transcripts)
microphone: Brio 505                                   # Core Audio input device name
output_device: BlackHole 2ch                           # Core Audio output capture device
obsidian_template: ~/Work/Templates/MeetingTemplate.md # Path to your Obsidian template
meetings_dir: ~/Work/Meetings                          # Where meeting notes are saved
whisper_url: http://localhost:8765/inference            # Whisper server endpoint
whisper_api_key:                                       # API key for remote Whisper (leave blank for local)
llm_command: claude -p --model sonnet                  # Command used to summarize transcripts
llm_base_url:                                          # OpenAI-compatible API base URL (for local LLMs)
```

The Obsidian template must contain these headings (the script inserts content after each):

```markdown
# People
# Log
# Action Items
```

## Customizing the LLM Prompt

The instructions sent to Claude for summarization are stored in `llm_instructions.md` in the same directory as the script. You can edit this file to change how Claude summarizes your meetings. The file is read fresh on every run, so changes take effect immediately.

Use `{{USER_NAME}}` as a placeholder — it will be replaced with the `user_name` value from `config.yaml` at runtime.

The default instructions are:

```
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
```

If you customize the prompt, keep the `LOG_START`/`LOG_END` and `ACTIONS_START`/`ACTIONS_END` markers — the script uses these to extract the sections and insert them into the Obsidian note.

## Changing the LLM

By default, ZoomMeet uses Claude Code (`claude -p --model sonnet`) to summarize transcripts. You can change this to any command-line tool that:

1. Reads the transcript from **stdin**
2. Accepts the prompt as its **last argument**
3. Writes the summary to **stdout**

Edit `llm_command` in `config.yaml`:

```yaml
# Default — Claude Sonnet via Claude Code CLI
llm_command: claude -p --model sonnet

# Example — Ollama with a local model
llm_command: ollama run llama3

# Example — OpenAI-compatible API via curl
llm_command: my-llm-wrapper.sh
```

If your LLM tool doesn't accept stdin + a trailing argument natively, write a small wrapper script that adapts the interface. The script will be called as:

```bash
cat transcript.txt | <llm_command> "<contents of llm_instructions.md>"
```

### Using a Local LLM with the `llm` CLI

If you'd rather not send your meeting transcripts to the cloud, you can run a local LLM instead. The [`llm`](https://llm.datasette.io/) CLI tool by Simon Willison works well for this — it reads from stdin and accepts a prompt argument, which is exactly what ZoomMeet expects.

**1. Install `llm`**

```bash
pip install llm
```

The installer will offer to do this for you, or you can install it later.

**2. Run a local LLM server**

You need a local server that provides an OpenAI-compatible API. Popular options:

- [LM Studio](https://lmstudio.ai/) — GUI app, start the server from the "Local Server" tab (default: `http://127.0.0.1:1234/v1`)
- [Ollama](https://ollama.ai/) — CLI-based, runs on `http://localhost:11434/v1` after `ollama serve`

**3. Configure `config.yaml`**

Set `llm_command` to use `llm` with your chosen model, and `llm_base_url` to point to your local server:

```yaml
llm_command: llm -m qwen3.5-9b
llm_base_url: http://127.0.0.1:1234/v1
```

The `llm_base_url` value is passed to the `llm` tool as the `OPENAI_API_BASE` environment variable, which tells it to talk to your local server instead of OpenAI's API.

To switch back to Claude, comment out or remove those lines and restore the defaults:

```yaml
llm_command: claude -p --model sonnet
llm_base_url:
```

**Note:** Local models vary in quality. For meeting summarization, a model with at least 7-9B parameters is recommended. Smaller models may struggle with longer transcripts or miss action items.

## Usage

### GUI

```bash
cd ZoomMeetApp && .build/release/ZoomMeetApp
```

The app lets you select audio devices, choose a template, enter attendee names (with autocomplete), and start/stop recording with a single click. Processing progress is shown in a live log.

### Command Line

```bash
./zoommeet2 Sam Carlos Dan
```

Attendee names are optional. Press Enter to stop recording. The script handles everything else automatically.

## Whisper Server

### Local (default)

The installer sets up whisper-cpp as a persistent background service via launchd. It starts automatically on login. To check its status:

```bash
launchctl list | grep whisper
curl -s http://localhost:8765/inference    # should return a response
```

To view logs:

```bash
cat /tmp/whisper-server.log
cat /tmp/whisper-server.err
```

To restart:

```bash
launchctl unload ~/Library/LaunchAgents/whisper.server.plist
launchctl load ~/Library/LaunchAgents/whisper.server.plist
```

### Remote

If you chose a remote Whisper server during installation, the URL and API key are stored in `config.yaml`. If the server requires authentication, set `whisper_api_key` — it will be sent as a `Bearer` token in the `Authorization` header. The server must accept the same API as whisper.cpp's built-in HTTP server:

- **Endpoint:** POST to the configured URL
- **Fields:** `file` (multipart audio file), `response_format=verbose_json`
- **Response:** JSON with a `segments` array, each containing `start` (float) and `text` (string)

## Troubleshooting

**No audio captured / silent recording**
- Verify your Multi-Output Device is the system output (System Settings > Sound > Output)
- Make sure Zoom's speaker is set to the Multi-Output Device or "Same as System"
- Test BlackHole: `sox -t coreaudio "BlackHole 2ch" -d trim 0 5` (should play back what you hear)

**"Whisper server not reachable"**
- Check the server: `launchctl list | grep whisper`
- Check logs: `cat /tmp/whisper-server.err`
- Try starting manually: `whisper-server -m ~/whisper-models/ggml-large-v3-turbo.bin --port 8765`

**Claude summarization fails**
- Verify your key: `echo $ANTHROPIC_API_KEY`
- Test Claude: `echo "test" | claude -p "Say hello"`

**"sox FAIL" or device not found**
- Device names are case-sensitive. Check exact names: `system_profiler SPAudioDataType | grep "Device Name"`

**GUI window doesn't appear**
- Run from terminal to see errors: `cd ZoomMeetApp && swift run`
