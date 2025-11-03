#!/bin/bash

# Notification helper script for macOS
# Usage: source notify.sh

# Function to play notification with sound on macOS
notify_success() {
    local message="${1:-Task completed successfully}"
    local title="${2:-Pumba Network Chaos}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Display notification with sound
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\""

        # Also play system sound
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null || true
    fi
}

notify_error() {
    local message="${1:-Task failed}"
    local title="${2:-Pumba Network Chaos}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Display notification with error sound
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Basso\""

        # Also play error sound
        afplay /System/Library/Sounds/Basso.aiff 2>/dev/null || true
    fi
}

notify_info() {
    local message="${1:-Information}"
    local title="${2:-Pumba Network Chaos}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Display notification with subtle sound
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Ping\""

        # Also play info sound
        afplay /System/Library/Sounds/Ping.aiff 2>/dev/null || true
    fi
}

# Function to speak message (text-to-speech)
speak_message() {
    local message="${1:-Task completed}"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        say "$message" &
    fi
}

# Export functions for use in other scripts
export -f notify_success
export -f notify_error
export -f notify_info
export -f speak_message