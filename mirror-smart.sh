#!/usr/bin/env bash
set -euo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CODENAME=$(lsb_release -cs 2>/dev/null || (source /etc/os-release && echo "${VERSION_CODENAME:-noble}"))
if [[ -z "${CODENAME}" ]]; then
  echo -e "${RED}Could not detect Ubuntu codename.${NC}"
  exit 1
fi

# Updated and expanded mirror lists
IR_MIRRORS=(
  "https://mirror.arvancloud.ir/ubuntu"
  "https://mirror.manageit.ir/ubuntu"
#  "http://mirror.asiatech.ir/ubuntu"
  "http://mirror.iranserver.com/ubuntu"
  "https://archive.ubuntu.petiak.ir/ubuntu"
#  "https://ubuntu.hostiran.ir/ubuntuarchive"
  "https://mirror.iranserver.com/ubuntu"
  "https://ir.ubuntu.sindad.cloud/ubuntu"
  "https://mirrors.pardisco.co/ubuntu"
#  "http://mirror.aminidc.com/ubuntu"
#  "http://mirror.faraso.org/ubuntu"
  "https://ir.archive.ubuntu.com/ubuntu"
  "https://ubuntu-mirror.kimiahost.com"
#  "https://ubuntu.bardia.tech"
  "https://mirror.0-1.cloud/ubuntu"
#  "http://linuxmirrors.ir/pub/ubuntu"
#  "http://repo.iut.ac.ir/repo/Ubuntu"
#  "https://ubuntu.shatel.ir/ubuntu"
#  "http://ubuntu.byteiran.com/ubuntu"
#  "https://mirror.rasanegar.com/ubuntu"
#  "http://mirrors.sharif.ir/ubuntu"
#  "http://mirror.ut.ac.ir/ubuntu"
#  "http://repo.iut.ac.ir/repo/ubuntu"
#  "https://mirror.parsdev.com/ubuntu"
#  "https://mirror.mobinhost.com/ubuntu"
#  "https://linuxmirrors.ir/pub/ubuntu"
  "https://mirrors.kubarcloud.com/ubuntu"
  "https://repo.abrha.net/ubuntu"
#  "https://en-mirror.ir/ubuntu"
#  "https://mirror.afranet.com/ubuntu"
  "https://mirror.atlantiscloud.ir/ubuntu"
  "https://mirror.digitalvps.ir/ubuntu"
#  "https://iran.chabokan.net/ubuntu"
)

GLOBAL_MIRRORS=(
  "http://archive.ubuntu.com/ubuntu"
  "https://archive.ubuntu.com/ubuntu"
  "https://us.archive.ubuntu.com/ubuntu"
  "https://de.archive.ubuntu.com/ubuntu"
  "https://nl.archive.ubuntu.com/ubuntu"
  "https://fr.archive.ubuntu.com/ubuntu"
  "https://gb.archive.ubuntu.com/ubuntu"
  "https://ca.archive.ubuntu.com/ubuntu"
)

UA="Mozilla/5.0 (X11; Ubuntu; Linux x86_64)"
RESULTS=()
MAX_RETRIES=2
VALIDATION_RETRIES=3
SKIP_REQUESTED=false

# Setup terminal for non-blocking Enter key detection
setup_nonblock_input() {
  # Save terminal settings and switch to raw mode (no echo, no line buffer)
  OLD_STTY=$(stty -g 2>/dev/null || true)
  stty -echo -icanon min 0 time 0 2>/dev/null || true
}

restore_input() {
  stty "$OLD_STTY" 2>/dev/null || true
}

# Check if Enter was pressed (non-blocking)
check_skip() {
  local ch
  ch=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
  # Enter key = 0a (newline) or 0d (carriage return)
  if [[ "$ch" == "0a" || "$ch" == "0d" ]]; then
    SKIP_REQUESTED=true
  fi
}

# Function to check if a suite exists and is complete
check_suite() {
  local base="$1" suite="$2" retry="${3:-0}"
  local url="$base/dists/$suite/InRelease"
  local code
  
  code=$(curl -4 --ipv4 -A "$UA" -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 6 --max-time 10 -L "$url" 2>/dev/null || echo "000")
  
  if [[ "$code" != "200" ]] && [[ $retry -lt $MAX_RETRIES ]]; then
    sleep 1
    check_suite "$base" "$suite" $((retry + 1))
    return $?
  fi
  
  [[ "$code" == "200" ]]
}

# Function to validate mirror by checking key package files
validate_mirror() {
  local base="$1"
  local test_file="$base/dists/$CODENAME/main/binary-amd64/Packages.gz"
  
  for i in $(seq 1 $VALIDATION_RETRIES); do
    local size=$(curl -4 --ipv4 -A "$UA" -sL --connect-timeout 5 --max-time 8 \
      -w "%{size_download}" -o /dev/null "$test_file" 2>/dev/null || echo "0")
    
    # Packages.gz should be at least 500KB for a valid mirror
    if [[ "${size:-0}" -gt 500000 ]]; then
      return 0
    fi
    
    [[ $i -lt $VALIDATION_RETRIES ]] && sleep 2
  done
  
  return 1
}

# Function to check if mirror is currently syncing
is_mirror_syncing() {
  local base="$1"
  local inrelease_url="$base/dists/$CODENAME/InRelease"
  
  # Check if InRelease file was modified very recently (last 15 minutes)
  local last_modified=$(curl -4 --ipv4 -A "$UA" -sI --connect-timeout 5 \
    "$inrelease_url" 2>/dev/null | grep -i "last-modified:" | cut -d' ' -f2-)
  
  if [[ -n "$last_modified" ]]; then
    local mod_epoch=$(date -d "$last_modified" +%s 2>/dev/null || echo "0")
    local now_epoch=$(date +%s)
    local diff=$((now_epoch - mod_epoch))
    
    # If modified in last 15 minutes, likely syncing
    [[ $diff -lt 900 ]]
  else
    return 1
  fi
}

# Function to manage backups
manage_backups() {
  echo -e "${BLUE}====================================${NC}"
  echo -e "${BLUE}Backup Manager${NC}"
  echo -e "${BLUE}====================================${NC}"

  # Find all backup files (both sources.list and ubuntu.sources backups)
  mapfile -t BACKUPS < <(ls /etc/apt/sources.list.bak.* /etc/apt/sources.list.d/ubuntu.sources.bak.* 2>/dev/null || true)
  mapfile -t BACKUPS < <(printf '%s\n' "${BACKUPS[@]}" | grep -v '^$' | sort -r || true)

  if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No backups found.${NC}"
    echo -e "Backups are created automatically when you change your mirror."
    echo ""
    return
  fi

  echo -e "Found ${GREEN}${#BACKUPS[@]}${NC} backup(s):\n"

  for i in "${!BACKUPS[@]}"; do
    local bfile="${BACKUPS[$i]}"
    local bdate
    # Extract date/time from filename (sources.list.bak.YYYY-MM-DD-HHMMSS)
    bdate=$(basename "$bfile" | sed 's/sources.list.bak.//' | sed 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1 \2:\3:\4/')

    # Extract mirrors from backup file (supports legacy 'deb' and DEB822 'URIs:' format)
    local mirrors
    # Match lines starting with 'deb' or 'deb-src', skip options in brackets [...]
    mirrors=$(grep -E '^deb' "$bfile" 2>/dev/null \
      | sed 's/^\(deb\(-src\)\?\)[[:space:]]\+\(\[[^]]*\][[:space:]]\+\)\?//' \
      | awk '{print $1}' | grep -E '^https?://' | sort -u | tr '\n' ' ' || true)
    if [[ -z "${mirrors// /}" ]]; then
      mirrors=$(grep -E '^URIs:' "$bfile" 2>/dev/null \
        | sed 's/^URIs:[[:space:]]*//' | tr ' ' '\n' \
        | grep -E '^https?://' | sort -u | tr '\n' ' ' || true)
    fi
    if [[ -z "${mirrors// /}" ]]; then
      mirrors="(unknown format - check file manually)"
    fi

    echo -e "  $((i+1)). ${YELLOW}$bdate${NC}"
    echo -e "     File: $bfile"
    echo -e "     Mirrors: ${GREEN}$mirrors${NC}"
    echo ""
  done

  read -r -p "Enter backup number to restore (or 'q' to go back): " BCHOICE

  if [[ "$BCHOICE" == "q" ]]; then
    echo "Cancelled."
    return
  fi

  if ! [[ "$BCHOICE" =~ ^[0-9]+$ ]] || \
     [[ "$BCHOICE" -lt 1 ]] || \
     [[ "$BCHOICE" -gt "${#BACKUPS[@]}" ]]; then
    echo -e "${RED}Invalid choice.${NC}"
    return
  fi

  local SELECTED_BACKUP="${BACKUPS[$((BCHOICE-1))]}"

  # Show mirror details of selected backup
  echo ""
  echo -e "${BLUE}====================================${NC}"
  echo -e "${BLUE}Selected backup details:${NC}"
  echo -e "${BLUE}====================================${NC}"
  echo -e "${YELLOW}File:${NC} $SELECTED_BACKUP"
  echo ""
  echo -e "${YELLOW}Content (deb lines):${NC}"
  {
    grep -E '^deb' "$SELECTED_BACKUP" 2>/dev/null || true
    grep -E '^URIs:|^Suites:|^Components:|^Types:' "$SELECTED_BACKUP" 2>/dev/null || true
  } | sort -u | while read -r line; do
    echo -e "  ${GREEN}$line${NC}"
  done
  # If nothing printed, show raw non-comment lines
  local raw_lines
  raw_lines=$(grep -Ev '^[[:space:]]*(#|$)' "$SELECTED_BACKUP" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  if [[ "$raw_lines" -eq 0 ]]; then
    echo -e "  ${YELLOW}(file appears empty or only comments)${NC}"
  fi
  echo ""

  read -r -p "Are you sure you want to restore this backup? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return
  fi

  # Determine original file path from backup filename
  local ORIGINAL_FILE
  if [[ "$SELECTED_BACKUP" == *"ubuntu.sources.bak."* ]]; then
    ORIGINAL_FILE="/etc/apt/sources.list.d/ubuntu.sources"
  else
    ORIGINAL_FILE="/etc/apt/sources.list"
  fi

  # Take a backup of current file before restoring
  local PRE_RESTORE_BACKUP="${ORIGINAL_FILE}.bak.$(date +%F-%H%M%S)"
  echo -n "Saving current config as backup: $PRE_RESTORE_BACKUP ... "
  if sudo cp "$ORIGINAL_FILE" "$PRE_RESTORE_BACKUP" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    exit 1
  fi

  # Restore selected backup
  echo -n "Restoring backup to $ORIGINAL_FILE ... "
  if sudo cp "$SELECTED_BACKUP" "$ORIGINAL_FILE" 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    exit 1
  fi

  # Run apt update
  echo ""
  echo -e "${BLUE}Running apt update...${NC}"
  if sudo apt update; then
    echo ""
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}Restore successful!${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "Restored from: ${YELLOW}$SELECTED_BACKUP${NC}"
    echo -e "Previous config saved to: ${YELLOW}$PRE_RESTORE_BACKUP${NC}"
  else
    echo ""
    echo -e "${RED}apt update FAILED after restore!${NC}"
    echo -e "To undo this restore:"
    echo -e "  ${YELLOW}sudo cp $PRE_RESTORE_BACKUP /etc/apt/sources.list${NC}"
    echo -e "  ${YELLOW}sudo apt update${NC}"
    exit 1
  fi
}

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}Ubuntu Mirror Smart Selector${NC}"
echo -e "${BLUE}====================================${NC}"
echo -e "Ubuntu codename: ${GREEN}$CODENAME${NC}"
echo -e "${BLUE}====================================${NC}"
echo "Select an option:"
echo "  1) Iran only"
echo "  2) International only"
echo "  3) Iran + International"
echo "  4) Test all and show top 5 (for manual selection)"
echo "  5) Manage backups"
echo ""

read -r -p "Your choice (1/2/3/4/5): " MODE

case "$MODE" in
  1) MIRRORS=("${IR_MIRRORS[@]}"); AUTO_SELECT=true ;;
  2) MIRRORS=("${GLOBAL_MIRRORS[@]}"); AUTO_SELECT=true ;;
  3) MIRRORS=("${IR_MIRRORS[@]}" "${GLOBAL_MIRRORS[@]}"); AUTO_SELECT=true ;;
  4) MIRRORS=("${IR_MIRRORS[@]}" "${GLOBAL_MIRRORS[@]}"); AUTO_SELECT=false ;;
  5) manage_backups; exit 0 ;;
  *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
esac

echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}Testing mirrors...${NC}"
echo -e "${YELLOW}  Press Enter at any time to skip current mirror${NC}"
echo -e "${BLUE}====================================${NC}"

TESTED=0
TOTAL=${#MIRRORS[@]}

setup_nonblock_input
trap 'restore_input' EXIT INT TERM

for BASE in "${MIRRORS[@]}"; do
  [[ -z "$BASE" ]] && continue
  TESTED=$((TESTED + 1))

  # Drain any pending Enter press from previous iteration
  SKIP_REQUESTED=false
  check_skip

  echo -n -e "[${TESTED}/${TOTAL}] Testing ${YELLOW}$BASE${NC} ... "
  
  # Check if mirror is currently syncing (run in background so Enter can interrupt)
  if is_mirror_syncing "$BASE"; then
    echo -e "${YELLOW}syncing (skipped)${NC}"
    continue
  fi

  # Check if user pressed Enter to skip
  check_skip
  if [[ "$SKIP_REQUESTED" == "true" ]]; then
    echo -e "${YELLOW}skipped by user${NC}"
    SKIP_REQUESTED=false
    continue
  fi
  
  # Check required suites
  if ! check_suite "$BASE" "$CODENAME" \
     || ! check_suite "$BASE" "$CODENAME-updates" \
     || ! check_suite "$BASE" "$CODENAME-backports"; then
    echo -e "${RED}unreachable${NC}"
    continue
  fi

  # Check if user pressed Enter to skip
  check_skip
  if [[ "$SKIP_REQUESTED" == "true" ]]; then
    echo -e "${YELLOW}skipped by user${NC}"
    SKIP_REQUESTED=false
    continue
  fi

  BASE_DIST="$BASE/dists/$CODENAME"

  # Measure latency
  LATENCY=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 6 \
    -w "%{time_total}" -o /dev/null "$BASE_DIST/InRelease" 2>/dev/null || echo "0")
  LATENCY="${LATENCY:-0}"
  LAT_MS=$(LC_ALL=C awk "BEGIN {printf \"%d\", $LATENCY*1000}")

  # Check if user pressed Enter to skip
  check_skip
  if [[ "$SKIP_REQUESTED" == "true" ]]; then
    echo -e "${YELLOW}skipped by user${NC}"
    SKIP_REQUESTED=false
    continue
  fi

  # Measure speed with Packages.gz
  PKG_URL="$BASE_DIST/main/binary-amd64/Packages.gz"
  STATS=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 8 --max-time 12 \
    --range 0-2097152 -o /dev/null -w "%{size_download} %{time_total} %{http_code}" \
    "$PKG_URL" 2>/dev/null || echo "0 0 000")

  BYTES=$(awk '{print $1}' <<< "$STATS")
  TIME=$(awk '{print $2}' <<< "$STATS")
  CODE=$(awk '{print $3}' <<< "$STATS")

  # Fallback to InRelease if Packages.gz failed
  if [[ "$CODE" != "200" && "$CODE" != "206" ]] || [[ "${BYTES:-0}" -lt 1000 ]]; then
    STATS=$(LC_ALL=C curl -4 --ipv4 -A "$UA" -s -L --connect-timeout 6 --max-time 8 \
      -o /dev/null -w "%{size_download} %{time_total}" \
      "$BASE_DIST/InRelease" 2>/dev/null || echo "0 0")
    BYTES=$(awk '{print $1}' <<< "$STATS")
    TIME=$(awk '{print $2}' <<< "$STATS")
  fi

  SPEED_KB=0
  if [[ "${BYTES:-0}" -gt 0 ]] && LC_ALL=C awk "BEGIN {exit !($TIME > 0.01)}"; then
    SPEED_KB=$(LC_ALL=C awk "BEGIN {printf \"%d\", $BYTES/$TIME/1024}")
  fi

  if [[ "$SPEED_KB" -le 5 ]]; then
    echo -e "${RED}too slow (${SPEED_KB} KB/s)${NC}"
    continue
  fi

  # Calculate score (lower is better)
  # 60% weight on latency, 40% weight on speed
  SCORE=$(LC_ALL=C awk "BEGIN {printf \"%d\", ($LAT_MS*0.6) + (100000/$SPEED_KB)*0.4 }")
  
  echo -e "${GREEN}OK${NC} | ${LAT_MS}ms | ${SPEED_KB} KB/s | score=${SCORE}"

  RESULTS+=("$SCORE $LAT_MS $SPEED_KB $BASE")
done

if [ ${#RESULTS[@]} -eq 0 ]; then
  restore_input
  echo -e "${RED}No valid mirrors found.${NC}"
  exit 1
fi

# Restore terminal to normal before user interaction
restore_input

# Sort results by score
mapfile -t SORTED < <(printf "%s\n" "${RESULTS[@]}" | sort -n)

echo ""
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}Test Results (sorted by score):${NC}"
echo -e "${BLUE}====================================${NC}"

if [[ "$AUTO_SELECT" == "true" ]]; then
  LIMIT=3
else
  LIMIT=5
fi

for i in "${!SORTED[@]}"; do
  if [[ $i -ge $LIMIT ]]; then break; fi
  
  LINE="${SORTED[$i]}"
  SCORE=$(awk '{print $1}' <<< "$LINE")
  LAT=$(awk '{print $2}' <<< "$LINE")
  SPD=$(awk '{print $3}' <<< "$LINE")
  URL=$(awk '{print $4}' <<< "$LINE")
  
  echo -e "  $((i+1)). ${GREEN}$URL${NC}"
  echo -e "     Latency: ${LAT}ms | Speed: ${SPD} KB/s | Score: ${SCORE}"
done

echo ""

# Select mirror
if [[ "$AUTO_SELECT" == "true" ]]; then
  SELECTED_LINE="${SORTED[0]}"
  SELECTED_BASE=$(awk '{print $4}' <<< "$SELECTED_LINE")
  
  echo -e "${BLUE}====================================${NC}"
  echo -e "${GREEN}Auto-selected best mirror:${NC}"
  echo -e "  ${YELLOW}$SELECTED_BASE${NC}"
  echo -e "${BLUE}====================================${NC}"
else
  echo "Enter mirror number to use (1-${LIMIT}) or 'q' to quit:"
  read -r -p "Your choice: " CHOICE
  
  if [[ "$CHOICE" == "q" ]]; then
    echo "Cancelled."
    exit 0
  fi
  
  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [[ "$CHOICE" -lt 1 ]] || [[ "$CHOICE" -gt "$LIMIT" ]]; then
    echo -e "${RED}Invalid choice${NC}"
    exit 1
  fi
  
  SELECTED_LINE="${SORTED[$((CHOICE-1))]}"
  SELECTED_BASE=$(awk '{print $4}' <<< "$SELECTED_LINE")
  
  echo -e "${BLUE}====================================${NC}"
  echo -e "${GREEN}Selected mirror:${NC}"
  echo -e "  ${YELLOW}$SELECTED_BASE${NC}"
  echo -e "${BLUE}====================================${NC}"
fi

# Validate selected mirror before applying
echo -n "Validating selected mirror... "
if ! validate_mirror "$SELECTED_BASE"; then
  echo -e "${RED}FAILED${NC}"
  echo -e "${YELLOW}Warning: Selected mirror failed validation. It may be incomplete or syncing.${NC}"
  restore_input
  read -r -p "Continue anyway? (y/N): " CONT
  if [[ ! "$CONT" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
  fi
else
  echo -e "${GREEN}OK${NC}"
fi

# Detect which sources file is actually in use
SOURCES_FILE=""
SOURCES_FORMAT=""
if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
  SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
  SOURCES_FORMAT="deb822"
elif [[ -f /etc/apt/sources.list ]]; then
  SOURCES_FILE="/etc/apt/sources.list"
  SOURCES_FORMAT="legacy"
else
  echo -e "${RED}Could not find apt sources file.${NC}"
  exit 1
fi

echo -e "Sources file: ${YELLOW}$SOURCES_FILE${NC} (format: $SOURCES_FORMAT)"

# If using ubuntu.sources (Noble+), clear sources.list to avoid duplicate warnings
if [[ "$SOURCES_FORMAT" == "deb822" ]] && [[ -f /etc/apt/sources.list ]]; then
  # Check if sources.list has any active (non-comment) deb lines
  ACTIVE_LINES=$(grep -cE '^deb ' /etc/apt/sources.list 2>/dev/null || echo 0)
  if [[ "$ACTIVE_LINES" -gt 0 ]]; then
    echo -n "Clearing duplicate entries from /etc/apt/sources.list ... "
    sudo cp /etc/apt/sources.list "/etc/apt/sources.list.bak.$(date +%F-%H%M%S)" 2>/dev/null || true
    echo "# Cleared by mirror-smart.sh on $(date) — entries moved to ubuntu.sources" \
      | sudo tee /etc/apt/sources.list > /dev/null
    echo -e "${GREEN}OK${NC}"
  fi
fi

# Backup main sources file
BACKUP_FILE="${SOURCES_FILE}.bak.$(date +%F-%H%M%S)"
echo -n "Creating backup: $BACKUP_FILE ... "
if sudo cp "$SOURCES_FILE" "$BACKUP_FILE" 2>/dev/null; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}FAILED${NC}"
  exit 1
fi

# Use selected mirror for security too (security.ubuntu.com is blocked in Iran)
# Most Iranian mirrors carry the security suite as well
SECURITY_BASE="$SELECTED_BASE"

# Write new sources file
echo -n "Writing $SOURCES_FILE ... "
if [[ "$SOURCES_FORMAT" == "deb822" ]]; then
  {
    echo "# Mirror selected by mirror-smart.sh on $(date)"
    echo "# Backup: $BACKUP_FILE"
    echo ""
    echo "Types: deb"
    echo "URIs: $SELECTED_BASE"
    echo "Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security"
    echo "Components: main restricted universe multiverse"
    echo "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
  } | sudo tee "$SOURCES_FILE" > /dev/null
else
  {
    echo "# Mirror selected by mirror-smart.sh on $(date)"
    echo "# Backup: $BACKUP_FILE"
    echo ""
    echo "deb $SELECTED_BASE $CODENAME main restricted universe multiverse"
    echo "deb $SELECTED_BASE $CODENAME-updates main restricted universe multiverse"
    echo "deb $SELECTED_BASE $CODENAME-backports main restricted universe multiverse"
    echo "deb $SECURITY_BASE $CODENAME-security main restricted universe multiverse"
    echo ""
    echo "# Uncomment for source packages:"
    echo "# deb-src $SELECTED_BASE $CODENAME main restricted universe multiverse"
    echo "# deb-src $SELECTED_BASE $CODENAME-updates main restricted universe multiverse"
  } | sudo tee "$SOURCES_FILE" > /dev/null
fi

echo -e "${GREEN}OK${NC}"

# Run apt update
echo ""
echo -e "${BLUE}====================================${NC}"
echo -e "${BLUE}Running apt update...${NC}"
echo -e "${BLUE}====================================${NC}"

if sudo apt update; then
  echo ""
  echo -e "${GREEN}====================================${NC}"
  echo -e "${GREEN}Success!${NC}"
  echo -e "${GREEN}====================================${NC}"
  echo -e "Mirror configured: ${YELLOW}$SELECTED_BASE${NC}"
  echo -e "Backup saved to: ${YELLOW}$BACKUP_FILE${NC}"
  echo ""
  echo -e "To restore previous configuration:"
  echo -e "  ${YELLOW}sudo cp $BACKUP_FILE $SOURCES_FILE${NC}"
  echo -e "  ${YELLOW}sudo apt update${NC}"
else
  echo ""
  echo -e "${RED}====================================${NC}"
  echo -e "${RED}apt update FAILED!${NC}"
  echo -e "${RED}====================================${NC}"
  echo -e "The mirror may be incomplete or syncing."
  echo ""
  echo -e "To restore previous configuration:"
  echo -e "  ${YELLOW}sudo cp $BACKUP_FILE $SOURCES_FILE${NC}"
  echo -e "  ${YELLOW}sudo apt update${NC}"
  exit 1
fi