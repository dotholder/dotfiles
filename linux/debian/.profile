#!/bin/bash
# Exit if not running interactively
[[ $- != *i* ]] && return

fastfetch

# ============================
# Aliases
# ============================

# Package management
alias update='sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean'
alias install='sudo apt install -y'
alias remove='sudo apt purge -y'
alias search='apt-cache search'

# System commands
alias reboot='sudo systemctl reboot'
alias poweroff='sudo systemctl poweroff'
alias info='inxi -Fxxxrza'

# Navigation & files
alias ls='exa -l --color=always --group-directories-first'
alias la='exa -al --color=always --group-directories-first'
alias ..='cd ..'
alias rm='rm -iv'

# Git aliases
alias gc='git clone'
alias dotfiles='git clone https://github.com/dotholder/dotfiles.git'

# yt-dlp aliases
alias yt-playlist="yt-best -cio '%(autonumber)s-%(title)s.%(ext)s'"
alias yta-aac="yt --extract-audio --audio-format aac"
alias yta-best="yt --extract-audio --audio-format best"
alias yta-flac="yt --extract-audio --audio-format flac"
alias yta-m4a="yt --extract-audio --audio-format m4a"
alias yta-mp3="yt --extract-audio --audio-format mp3"
alias yta-opus="yt --extract-audio --audio-format opus"
alias yta-vorbis="yt --extract-audio --audio-format vorbis"
alias yta-wav="yt --extract-audio --audio-format wav"
alias yt-best="yt --cookies-from-browser firefox -f bestvideo+bestaudio"
alias yt='yt-dlp'
alias ytv='yt -f bestvideo'
alias yta='yt -f bestaudio'
alias downloadchannel='yt-best -ciw -o "%(title)s.%(ext)s"'

# ============================
# Shell Behavior and Prompt
# ============================

# Make tab cycle through completion options instead of just listing them
bind 'TAB:menu-complete'

# Show all completions on first tab press if there are multiple options
bind 'set show-all-if-ambiguous on'

# Don't put duplicate lines or lines starting with space in the history
HISTCONTROL=ignoreboth

# Ignore case in tab completion
bind "set completion-ignore-case on"


# Shell prompt
PS1="\[\e[1;31m\][\[\e[33m\]\u\[\e[32m\]@\[\e[34m\]\h \[\e[35m\]\W\[\e[31m\]]\[\e[37m\]\\$ \[\e[0m\]"

# ====================
# Scripts
# ====================

# Archive extractor
ex () {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar*|*.tgz|*.tbz2|*.tbz|*.txz|*.tzst|*.tar.zst|*.tar.gz|*.tar.bz2|*.tar.xz)
        tar xf "$1" ;;
      *.bz2)               bunzip2 "$1"       ;;
      *.rar)               unrar x "$1"       ;;
      *.gz)                gunzip "$1"        ;;
      *.zip)               unzip "$1"         ;;
      *.Z)                 uncompress "$1"    ;;
      *.7z)                7z x "$1"          ;;
      *.lzma)              lzma -d "$1"       ;;
      *.xz)                unxz "$1"          ;;
      *.deb)               ar x "$1"          ;;
      *)                   echo "'$1' cannot be extracted" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}



# Video frame extractor
function extract-frames {
  local input_file="$1"
  local output_dir="${2:-}"
  
  if [ -z "$input_file" ]; then
    echo "Usage: extract-frames <video_file> [output_dir]"
    return 1
  fi
  
  if [ ! -f "$input_file" ]; then
    echo "Error: Input file \"$input_file\" does not exist"
    return 1
  fi
  
  local filename="${input_file##*/}"
  local base_name="${filename%.*}"
  output_dir="${output_dir:-${base_name}_frames}"
  
  mkdir -p "$output_dir"
  
  echo "Extracting frames..."
  echo "Output → $output_dir/frame_00000001.png"
  echo "This may take a long time."
  
  ffmpeg -threads "$(nproc)" -i "$input_file" \
    -vsync 0 \
    -start_number 1 \
    -c:v png \
    -pred mixed \
    -compression_level 6 \
    "$output_dir/frame_%08d.png" \
    -loglevel error -stats
  
  if [ $? -ne 0 ]; then
    echo "Error: ffmpeg extraction failed"
    return 1
  fi
  
  echo "✅ Extraction complete"
  
  # --- Deduplication: remove exact pixel duplicates (global, not just consecutive) ---
  echo "Removing exact duplicate frames (keeping first occurrence)..."
  cd "$output_dir" || return 1
  
  declare -A seen
  
  # First pass: delete duplicates while preserving order
  mapfile -t files < <(printf "%s\n" frame_*.png 2>/dev/null | sort -V)
  
  local deleted_count=0
  for file in "${files[@]}"; do
    if [ -f "$file" ]; then
      local hash=$(md5sum "$file" | awk '{print $1}')
      if [[ ${seen[$hash]+exists} ]]; then
        rm -f "$file"
        ((deleted_count++))
      else
        seen[$hash]=1
      fi
    fi
  done
  
  # Second pass: renumber remaining unique frames sequentially (no gaps)
  mapfile -t remaining < <(printf "%s\n" frame_*.png 2>/dev/null | sort -V)
  
  local i=1
  for file in "${remaining[@]}"; do
    local newname=$(printf "frame_%08d.png" "$i")
    if [ "$file" != "$newname" ]; then
      mv "$file" "$newname"
    fi
    ((i++))
  done
  
  local unique_count=$((i - 1))
  echo "✅ Deduplication complete: $deleted_count duplicate(s) removed, $unique_count unique frame(s) kept"
  
  cd - > /dev/null
}