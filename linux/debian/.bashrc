#!/bin/bash
# Exit if not running interactively
[[ $- != *i* ]] && return

# Show system info if fastfetch is installed
command -v fastfetch &>/dev/null && fastfetch

# ============================
# Aliases
# ============================

# Package management
alias update='sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove --purge -y && sudo apt clean'
alias installpkg='sudo apt install -y'
alias removepkg='sudo apt purge -y'
alias search='apt-cache search'

# System commands
alias reboot='sudo reboot'
alias poweroff='sudo poweroff'
alias sysinfo='inxi -Fxxxrza'

# Navigation & files
alias ls='eza -l --color=auto --group-directories-first'
alias la='eza -al --color=auto --group-directories-first'
alias ..='cd ..'

# Git aliases
alias gc='git clone'
alias dotfiles='git clone https://github.com/dotholder/dotfiles.git'

# yt-dlp aliases
alias yt='yt-dlp'
alias yt-best='yt --cookies-from-browser chrome -f "bv*+ba/b"'
alias ytv='yt -f bestvideo'
alias yta='yt -f bestaudio'
alias yt-playlist="yt-best -o '%(autonumber)s-%(title)s.%(ext)s'"
alias yta-aac='yt --extract-audio --audio-format aac'
alias yta-best='yt --extract-audio --audio-format best'
alias yta-flac='yt --extract-audio --audio-format flac'
alias yta-m4a='yt --extract-audio --audio-format m4a'
alias yta-mp3='yt --extract-audio --audio-format mp3'
alias yta-opus='yt --extract-audio --audio-format opus'
alias yta-vorbis='yt --extract-audio --audio-format vorbis'
alias yta-wav='yt --extract-audio --audio-format wav'
alias downloadchannel='yt-best -w -o "%(title)s.%(ext)s"'

# ============================
# Shell Behavior and Prompt
# ============================

# Ignore case in tab completion & show on first tab press
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend # Append history instead of overwriting on shell exit

# Shell prompt
export PS1="\[\033[01;36m\]\w \[\033[01;35m\]ν \[\033[00m\]"

# ============================
# Functions
# ============================

# Archive extractor
ex() {
  if [[ -z "${1:-}" ]]; then
    echo 'Usage: ex <archive_file>'
    return 1
  fi

  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar|*.tar.*|*.tgz|*.tbz2|*.tbz|*.txz|*.tzst) tar xf "$1" ;;
      *.bz2)  bunzip2 "$1" ;;
      *.rar)  unar "$1" ;;
      *.gz)   gunzip "$1" ;;
      *.zip)  unzip "$1" ;;
      *.Z)    uncompress "$1" ;;
      *.7z)   7z x "$1" ;;
      *.lzma) lzma -d "$1" ;;
      *.xz)   unxz "$1" ;;
      *.deb)  ar x "$1" ;;
      *)
        printf "Error: '%s' cannot be extracted via ex()\n" "$1" >&2
        return 1
        ;;
    esac
  else
    printf "Error: '%s' is not a valid file\n" "$1" >&2
    return 1
  fi
}

# Video frame extractor
extract-frames() {
  local input_file="${1:-}"
  local output_dir="${2:-}"
  local required cores filename base_name

  if [[ -z "$input_file" ]]; then
    echo 'Usage: extract-frames <video_file> [output_dir]'
    return 1
  fi

  if [[ ! -f "$input_file" ]]; then
    printf "Error: Input file '%s' does not exist\n" "$input_file" >&2
    return 1
  fi

  for required in ffmpeg find xargs md5sum mktemp; do
    if ! command -v "$required" &>/dev/null; then
      printf "Error: Required command '%s' is not installed\n" "$required" >&2
      return 1
    fi
  done

  filename="${input_file##*/}"
  base_name="${filename%.*}"
  output_dir="${output_dir:-${base_name}_frames}"

  if ! mkdir -p -- "$output_dir"; then
    printf "Error: Could not create output directory '%s'\n" "$output_dir" >&2
    return 1
  fi

  if compgen -G "$output_dir/frame_*.png" >/dev/null; then
    printf "Error: Output directory '%s' already contains frame PNGs. Use a fresh directory.\n" "$output_dir" >&2
    return 1
  fi

  cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  echo 'Extracting frames...'

  if ! ffmpeg -n -threads "$cores" -i "$input_file" \
    -vf mpdecimate \
    -fps_mode passthrough \
    -start_number 1 \
    -c:v png \
    -pred mixed \
    -compression_level 6 \
    -loglevel error -stats \
    "$output_dir/frame_%08d.png"; then
    echo 'Error: ffmpeg extraction failed' >&2
    return 1
  fi

  if ! compgen -G "$output_dir/frame_*.png" >/dev/null; then
    echo 'Error: ffmpeg did not produce any frame PNGs' >&2
    return 1
  fi

  printf '\nRemoving exact duplicate frames...\n'

  (
    cd -- "$output_dir" || exit 1
    shopt -s nullglob
    set -o pipefail

    local manifest record hash file newname
    local deleted_count=0
    local i=1
    local -A seen=()

    manifest=$(mktemp -- '.frame-hashes.XXXXXXXX') || exit 1
    trap 'rm -f -- "$manifest"' EXIT

    if ! find . -maxdepth 1 -type f -name 'frame_*.png' -print0 \
      | xargs -0 -r md5sum --zero -- > "$manifest"; then
      echo 'Error: Could not hash the extracted frames' >&2
      exit 1
    fi

    while IFS= read -r -d '' record; do
      hash="${record:0:32}"
      file="${record:34}"

      if [[ -n "${seen[$hash]+x}" ]]; then
        if ! rm -f -- "$file"; then
          printf "Error: Could not remove duplicate '%s'\n" "$file" >&2
          exit 1
        fi
        ((deleted_count += 1))
      else
        seen[$hash]="$file"
      fi
    done < "$manifest"

    local -a remaining=(frame_*.png)
    if (( ${#remaining[@]} == 0 )); then
      echo 'Error: No frames remaining after deduplication' >&2
      exit 1
    fi

    for file in "${remaining[@]}"; do
      printf -v newname 'frame_%08d.png' "$i"
      if [[ "$file" != "$newname" ]]; then
        if [[ -e "$newname" || -L "$newname" ]]; then
          printf "Error: Renumbering would overwrite '%s'\n" "$newname" >&2
          exit 1
        fi
        if ! mv -- "$file" "$newname"; then
          printf "Error: Could not rename '%s'\n" "$file" >&2
          exit 1
        fi
      fi
      ((i += 1))
    done

    printf 'Deduplication complete: %d duplicate(s) removed, %d unique frame(s) kept\n' \
      "$deleted_count" "$((i - 1))"
  )
}