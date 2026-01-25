#!/bin/bash

# Define variables
REPO_URL="https://github.com/1999AZZAR/swap-management"
SCRIPT_NAME="swap_manager.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
ALIAS_COMMAND="alias swap='sudo $SCRIPT_NAME'"
BASHRC_FILE="$HOME/.bashrc"
ZSHRC_FILE="$HOME/.zshrc"

echo "Starting installation..."

# Check if script exists locally
if [[ -f "$SCRIPT_NAME" ]]; then
    echo "Local $SCRIPT_NAME found. Using local version."
else
    # Download the script
    echo "Downloading $SCRIPT_NAME from $REPO_URL..."
    if command -v curl &>/dev/null; then
        curl -sSL "$REPO_URL/raw/master/$SCRIPT_NAME" -o "$SCRIPT_NAME"
    elif command -v wget &>/dev/null; then
        wget -q "$REPO_URL/raw/master/$SCRIPT_NAME" -O "$SCRIPT_NAME"
    else
        echo "Error: Neither curl nor wget found. Please install one of them."
        exit 1
    fi
fi

if [[ ! -f "$SCRIPT_NAME" ]]; then
    echo "Error: Failed to download the script."
    exit 1
fi

# Move the script to the install path
echo "Installing $SCRIPT_NAME to $INSTALL_PATH..."
if [[ $EUID -ne 0 ]]; then
    sudo mv "$SCRIPT_NAME" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
else
    mv "$SCRIPT_NAME" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
fi

# Add alias to shell configurations
echo "Adding alias to shell configurations..."
add_alias_if_missing() {
    local file=$1
    local cmd=$2
    if [[ -f "$file" ]]; then
        if ! grep -Fq "$cmd" "$file"; then
            echo "$cmd" >>"$file"
            echo "Alias added to $file"
        else
            echo "Alias already exists in $file"
        fi
    fi
}

add_alias_if_missing "$BASHRC_FILE" "$ALIAS_COMMAND"
add_alias_if_missing "$ZSHRC_FILE" "$ALIAS_COMMAND"

# Source the shell configurations
echo "Reloading shell configurations..."
if [[ -n "$ZSH_VERSION" ]]; then
    source "$ZSHRC_FILE"
else
    source "$BASHRC_FILE"
fi

echo "Installation completed successfully!"
echo "You can now use the command 'swap' to manage your system's swap settings."
