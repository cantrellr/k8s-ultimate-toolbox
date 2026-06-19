#!/bin/bash
# Install the toolbox helper script on Ubuntu
# Usage: ./install-toolbox.sh [--user]
#
# Options:
#   --user    Install to ~/.local/bin (no sudo required)
#   (default) Install to /usr/local/bin (requires sudo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLBOX_SCRIPT="$SCRIPT_DIR/toolbox"

# Check if toolbox script exists
if [[ ! -f "$TOOLBOX_SCRIPT" ]]; then
    echo "Error: toolbox script not found at $TOOLBOX_SCRIPT"
    exit 1
fi

# Parse arguments
USER_INSTALL=false
if [[ "$1" == "--user" ]]; then
    USER_INSTALL=true
fi

if [[ "$USER_INSTALL" == true ]]; then
    # User-only install
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    cp "$TOOLBOX_SCRIPT" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/toolbox"
    
    echo "Installed toolbox to $INSTALL_DIR/toolbox"
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        echo "NOTE: $INSTALL_DIR is not in your PATH."
        echo "Add this line to your ~/.bashrc:"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo "Then run: source ~/.bashrc"
    fi
else
    # System-wide install
    INSTALL_DIR="/usr/local/bin"
    
    if [[ $EUID -ne 0 ]]; then
        echo "System-wide install requires sudo. Running with sudo..."
        sudo cp "$TOOLBOX_SCRIPT" "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/toolbox"
    else
        cp "$TOOLBOX_SCRIPT" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/toolbox"
    fi
    
    echo "Installed toolbox to $INSTALL_DIR/toolbox"
fi

echo ""
echo "Usage:"
echo "  toolbox              # exec into toolbox pod (default namespace)"
echo "  toolbox <namespace>  # specify different namespace"
