#!/bin/bash
# Exit if not running interactively
[[ $- != *i* ]] && return

fastfetch

# ============================
# Aliases
# ============================

# Package management
alias update='sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean'
alias installpkg='sudo apt install -y'
alias removepkg='sudo apt purge -y'
alias search='apt-cache search'

# System commands
alias reboot='sudo reboot'
alias poweroff='sudo poweroff'
alias info='inxi -Fxxxrza'

# Navigation & files
alias ls='eza -l --color=always --group-directories-first'
alias la='eza -al --color=always --group-directories-first'
alias ..='cd ..'
alias rm='rm -iv'

# Git aliases
alias gc='git clone'
alias dotfiles='git clone https://github.com/dotholder/dotfiles.git'

# yt-dlp aliases
alias yt='yt-dlp'
alias yt-best="yt --cookies-from-browser brave -f bestvideo+bestaudio"
alias ytv='yt -f bestvideo'
alias yta='yt -f bestaudio'
alias yt-playlist="yt-best -o '%(autonumber)s-%(title)s.%(ext)s'"
alias yta-aac="yt --extract-audio --audio-format aac"
alias yta-best="yt --extract-audio --audio-format best"
alias yta-flac="yt --extract-audio --audio-format flac"
alias yta-m4a="yt --extract-audio --audio-format m4a"
alias yta-mp3="yt --extract-audio --audio-format mp3"
alias yta-opus="yt --extract-audio --audio-format opus"
alias yta-vorbis="yt --extract-audio --audio-format vorbis"
alias yta-wav="yt --extract-audio --audio-format wav"
alias downloadchannel='yt-best -w -o "%(title)s.%(ext)s"'

# ============================
# Shell Behavior and Prompt
# ============================

# Ignore case in tab completion
bind 'set completion-ignore-case on'

# Show all completions on first tab press
bind 'set show-all-if-ambiguous on'

# Don't put duplicate lines or lines starting with space in history
HISTCONTROL=ignoreboth

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
      *.bz2)   bunzip2 "$1" ;;
      *.rar)   unrar x "$1" ;;
      *.gz)    gunzip "$1" ;;
      *.zip)   unzip "$1" ;;
      *.Z)     uncompress "$1" ;;
      *.7z)    7z x "$1" ;;
      *.lzma)  lzma -d "$1" ;;
      *.xz)    unxz "$1" ;;
      *.deb)   ar x "$1" ;;
      *)       echo "'$1' cannot be extracted" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Video frame extractor
extract-frames () {
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

  local cores
  cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

  ffmpeg -threads "$cores" -i "$input_file" \
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

  echo "Removing exact duplicate frames..."
  (
    cd "$output_dir" || exit 1
    shopt -s nullglob
    local files=(frame_*.png)

    if [ ${#files[@]} -eq 0 ]; then
      echo "No frames found to deduplicate."
      exit 0
    fi

    declare -A seen
    local deleted_count=0

    while read -r hash file; do
      if [[ -n "${seen[$hash]}" ]]; then
        rm -f "$file"
        ((deleted_count++))
      else
        seen[$hash]=1
      fi
    done < <(md5sum "${files[@]}")

    local remaining=(frame_*.png)
    local i=1
    for file in "${remaining[@]}"; do
      local newname
      newname=$(printf "frame_%08d.png" "$i")
      if [ "$file" != "$newname" ]; then
        mv "$file" "$newname"
      fi
      ((i++))
    done

    local unique_count=$((i - 1))
    echo "✅ Deduplication complete: $deleted_count duplicate(s) removed, $unique_count unique frame(s) kept"
  )
}