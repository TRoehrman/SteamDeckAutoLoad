#!/bin/bash

# Check if Decky Loader is installed
if ! command -v decky &> /dev/null; then
  echo "Decky Loader is not installed. Please install it first."
  exit 1
fi

# Check if SteamGridDB plugin is installed
if ! decky list | grep -q "steamgriddb"; then
  echo "SteamGridDB plugin is not installed. Please install it first."
  exit 1
fi

# Function to find new games
find_new_games() {
    # Get a list of existing Steam entries
    existing_games=$(find ~/.local/share/Steam/steamapps/common/ -type f -executable -print0 | xargs -0 basename)

    # Find all executable files in /home/deck/Games/ and its subfolders, and on the microSD card
    game_files=$(find /home/deck/Games/ /run/media/mmcblk0p1/ -type f -executable -print0)

    # Filter out games that are already in Steam and common uninstallers
    new_games=()
    while IFS= read -r -d '' game; do
        game_name=$(basename "$game")
        if ! echo "$existing_games" | grep -q "$game_name" && ! echo "$game_name" | grep -iq "uninst|uninstall|uninst000"; then
            new_games+=("$game")
        fi
    done <<< "$game_files"
    echo "${new_games[@]}"
}

# Find new games
new_games=($(find_new_games))

# Check for non-silent install mode flag
non_silent=false
if [[ "$1" == "--ns" ]]; then
    non_silent=true
fi

# Add new games to Steam and update metadata with SteamGridDB
if [[ ${#new_games[@]} -gt 0 ]]; then
    for game_path in "${new_games[@]}"; do
        game_name=$(basename "$game_path")

        # Add the game to Steam (regardless of installer keywords)
        echo "Adding $game_name to Steam..."
        steam steam://rungameid/0//-add "$game_path"

        # Check if the executable name contains installer keywords
        if echo "$game_name" | grep -iq "install|setup|redist|dotnet|vc_redist"; then
            # Run the installer with optional silent flag
            if $non_silent; then
                steam steam://rungameid/0//-add "$game_path" &
            else
                steam steam://rungameid/0//-add "$game_path" --silent &
            fi

            # Capture the output of the installer to a temporary file
            installer_output=$(mktemp)
            tail -f "$installer_output" &
            installer_pid=$!
            wait $installer_pid

            # Analyze the installer output to find the installation directory, searching from root
            install_dir=$(grep -oE '"[^"]+/[^"]+\.exe"' "$installer_output" | sed 's/"//g' | xargs -0 dirname | head -n 1)

            # If an installation directory is NOT found, search the entire system
            if [[ ! -d "$install_dir" ]]; then
                echo "Installation directory not found in expected location. Searching the entire system..."
                # Search both the SSD and microSD card roots
                install_dir=$(find / /run/media/mmcblk0p1/ -name "*.exe" -print0 | xargs -0 dirname | head -n 1)
            fi

            # If an installation directory is found, update the Steam shortcut
            if [[ -d "$install_dir" ]]; then
                echo "Updating Steam shortcut for $game_name with $install_dir"
                steam steam://rungameid/0//-add "$install_dir"
            fi

            # Clean up the temporary file
            rm "$installer_output"
        fi

        echo "Updating metadata for $game_name with SteamGridDB..."
        decky steamgriddb --update-all "$game_name"

        # Create a desktop entry
        desktop_file="/home/deck/.local/share/applications/$game_name.desktop"
        echo "[Desktop Entry]" > "$desktop_file"
        echo "Name=$game_name" >> "$desktop_file"
        # echo "Exec=env WINEPREFIX=\"/home/deck/Games/$game_name\" /usr/bin/wine \"$game_path\"" >> "$desktop_file"  # Commented out
        echo "Type=Application" >> "$desktop_file"
        echo "Categories=Game;" >> "$desktop_file"
        chmod +x "$desktop_file"
    done
    echo "All new games added to Steam and metadata updated."
else
    echo "No new games found."
fi
