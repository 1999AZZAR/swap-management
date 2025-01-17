#!/bin/bash

# Define variables
REPO_URL="https://github.com/1999AZZAR/swap-management"
SCRIPT_NAME="swap_manager.sh"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
ALIAS_COMMAND="alias swap='sudo $SCRIPT_NAME'"
BASHRC_FILE="$HOME/.bashrc"
ZSHRC_FILE="$HOME/.zshrc"

echo "Starting installation..."

# Download the script
echo "Downloading $SCRIPT_NAME from $REPO_URL..."
wget -q "$REPO_URL/raw/main/$SCRIPT_NAME" -O "$SCRIPT_NAME"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download the script. Check the repository URL."
    exit 1
fi

# Move the script to the install path
echo "Installing $SCRIPT_NAME to $INSTALL_PATH..."
sudo mv "$SCRIPT_NAME" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

# Add alias to shell configurations
echo "Adding alias to shell configurations..."
if [[ -f $BASHRC_FILE ]]; then
    echo "$ALIAS_COMMAND" >>"$BASHRC_FILE"
    echo "Alias added to $BASHRC_FILE"
fi
if [[ -f $ZSHRC_FILE ]]; then
    echo "$ALIAS_COMMAND" >>"$ZSHRC_FILE"
    echo "Alias added to $ZSHRC_FILE"
fi

# Source the shell configurations
echo "Reloading shell configurations..."
if [[ -n "$ZSH_VERSION" ]]; then
    source "$ZSHRC_FILE"
else
    source "$BASHRC_FILE"
fi

echo "Installation completed successfully!"
echo "You can now use the command 'swap' to manage your system's swap settings."
