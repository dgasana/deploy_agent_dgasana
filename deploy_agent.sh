#!/usr/bin/env bash
# deploy_agent.sh - deploy, run and archive logs for the Student Attendance Tracker.
# Usage: ./deploy_agent.sh [--deploy | --run [name] | --archive [name] | --help]
# With no flag, an interactive menu is shown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
cd "$SCRIPT_DIR" || exit 1

PROJECT_DIR=""   # set during deployment; used by the signal handler

# ---------- helpers ----------
die() { echo "ERROR: $*" >&2; exit 1; }

valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

ask_number() {  # ask_number "prompt" min max  -> echoes a valid integer
    local v
    while true; do
        read -r -p "$1" v
        if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= $2 && v <= $3 )); then echo "$v"; return; fi
        echo "  Please enter a whole number between $2 and $3." >&2
    done
}

# ---------- signal handling (deployment only) ----------
on_interrupt() {
    trap '' INT TSTP   # ignore repeats while cleaning up
    echo
    echo "!! Deployment interrupted (Ctrl+C / Ctrl+Z received)."
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        local zipfile="${PROJECT_DIR}_archive.zip"
        echo "   Archiving the incomplete project to $zipfile ..."
        if zip -rq "$zipfile" "$PROJECT_DIR"; then
            echo "   Archive created: $SCRIPT_DIR/$zipfile"
            rm -rf "$PROJECT_DIR"
            echo "   Removed the incomplete directory $PROJECT_DIR."
        else
            echo "   Could not create the archive; leaving $PROJECT_DIR in place." >&2
        fi
    else
        echo "   Nothing had been created yet, so there is nothing to archive."
    fi
    echo "   Session closed cleanly."
    exit 130
}

# ---------- Feature 2: run ----------
run_app() {
    local dir="$1"
    [[ -d "$dir" ]] || die "Project directory '$dir' not found. Deploy first."
    [[ -f "$dir/attendance_checker.py" ]] || die "'$dir' has no attendance_checker.py."
    echo "Starting the Attendance Tracker in $dir ..."
    ( cd "$dir" && python3 attendance_checker.py )
}

# ---------- Feature 3: archive ----------
archive_logs() {
    local dir="$1" ts found=0
    [[ -d "$dir" ]] || die "Project directory '$dir' not found."
    ts="$(date +%Y%m%d_%H%M%S)"
    local name
    for name in attendance absent; do
        local src="$dir/reports/$name.log"
        if [[ -f "$src" ]]; then
            mkdir -p "$dir/archives/$name" || die "Cannot create archives/$name"
            local dest="$dir/archives/$name/${name}_${ts}.log"
            if cp "$src" "$dest"; then
                echo "Archived $name.log -> $dest"
                found=1
            else
                echo "WARNING: failed to archive $src" >&2
            fi
        else
            echo "Note: $src does not exist - skipping (e.g. nobody was absent)."
        fi
    done
    (( found )) || echo "No logs were archived."
}

# ---------- Feature 1: deploy ----------
deploy() {
    # Pre-flight
    local missing=0 tool
    for tool in python3 zip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "ERROR: required tool '$tool' is not installed." >&2; missing=1
        fi
    done
    (( missing )) && exit 1
    [[ -f "$TEMPLATES/attendance_checker.py" && -f "$TEMPLATES/config.json" ]] \
        || die "templates/ must contain attendance_checker.py and config.json."

    local input
    while true; do
        read -r -p "Enter a name for the project: " input
        valid_name "$input" && break
        echo "  Use only letters, numbers, '_' or '-'."
    done
    PROJECT_DIR="attendance_tracker_${input}"

    if [[ -e "$PROJECT_DIR" ]]; then
        local ans
        read -r -p "'$PROJECT_DIR' already exists. Overwrite? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR"
        else
            local keep="$PROJECT_DIR"; PROJECT_DIR=""
            die "Aborted: '$keep' left untouched."
        fi
    fi

    trap on_interrupt INT TSTP

    mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" || die "Could not create directories."
    cp "$TEMPLATES/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py"
    cp "$TEMPLATES/config.json" "$PROJECT_DIR/Helpers/config.json"
    local roster="$PROJECT_DIR/Helpers/assets.csv" config="$PROJECT_DIR/Helpers/config.json"

    echo "How should the roster be built?"
    echo "  A) Copy from templates/assets.csv"
    echo "  B) Generate a fresh roster"
    local choice
    while true; do
        read -r -p "Choose A or B: " choice
        [[ "$choice" =~ ^[AaBb]$ ]] && break
    done

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        [[ -f "$TEMPLATES/assets.csv" ]] || die "templates/assets.csv is missing."
        local avail=$(( $(wc -l < "$TEMPLATES/assets.csv") - 1 ))
        local n; n=$(ask_number "How many students to copy (1-$avail)? " 1 "$avail")
        head -n $((n + 1)) "$TEMPLATES/assets.csv" > "$roster"
        # template config already has total_sessions: 5 (4 prior sessions + today)
    else
        local names=("Alice Johnson" "Bob Smith" "Carol White" "David Brown" "Eve Davis"
                     "Frank Miller" "Grace Wilson" "Henry Moore" "Ivy Taylor" "Jack Anderson"
                     "Karen Thomas" "Leo Jackson" "Mia Harris" "Noah Martin" "Olivia Clark"
                     "Paul Lewis" "Quinn Walker" "Rita Hall" "Sam Young" "Tina King")
        local emails=(alice bob carol david eve frank grace henry ivy jack
                      karen leo mia noah olivia paul quinn rita sam tina)
        local n; n=$(ask_number "How many students (1-${#names[@]})? " 1 "${#names[@]}")
        echo "Email,Names,Attendance Count,Absence Count" > "$roster"
        local i
        for ((i = 0; i < n; i++)); do
            echo "${emails[i]}@example.com,${names[i]},0,0" >> "$roster"
        done
        # fresh roster = first session
        sed -i.bak 's/"total_sessions": *[0-9]*/"total_sessions": 1/' "$config" && rm -f "$config.bak"
    fi
    echo "Roster created: $roster ($(( $(wc -l < "$roster") - 1 )) students)"

    # Permissions
    chmod +x "$PROJECT_DIR/attendance_checker.py"
    chmod 600 "$config"
    echo "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$config" | awk '{print "  " $1 "  " $NF}'

    # Thresholds
    local upd
    read -r -p "Update the attendance alert thresholds? [y/N]: " upd
    if [[ "$upd" =~ ^[Yy]$ ]]; then
        local w f
        while true; do
            read -r -p "Warning threshold [75]: " w; w="${w:-75}"
            read -r -p "Failure threshold [50]: " f; f="${f:-50}"
            if [[ "$w" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ ]] && (( w <= 100 && f < w )); then break; fi
            echo "  Both must be whole numbers, warning <= 100 and failure < warning."
        done
        sed -i.bak -e "s/\"warning\": *[0-9]*/\"warning\": $w/" \
                   -e "s/\"failure\": *[0-9]*/\"failure\": $f/" "$config" && rm -f "$config.bak"
        echo "Thresholds updated: warning=$w failure=$f"
    fi

    # Deployment finished: release the traps before the interactive app starts
    trap - INT TSTP
    echo "Deployment complete: $PROJECT_DIR"
    echo "Verifying deployment by running the application..."
    run_app "$PROJECT_DIR"
}

# ---------- entry point ----------
project_for() {  # use arg if given, else ask
    local n="$1"
    if [[ -z "$n" ]]; then read -r -p "Project name (the part after attendance_tracker_): " n; fi
    echo "attendance_tracker_${n#attendance_tracker_}"
}

case "${1:-}" in
    --deploy)  deploy ;;
    --run)     run_app "$(project_for "${2:-}")" ;;
    --archive) archive_logs "$(project_for "${2:-}")" ;;
    --help|-h) sed -n '2,3p' "$0" ;;
    "")
        echo "=== Attendance Tracker Deploy Agent ==="
        echo "1) Deploy the application"
        echo "2) Run the application"
        echo "3) Archive log files"
        echo "4) Quit"
        read -r -p "Select [1-4]: " sel
        case "$sel" in
            1) deploy ;;
            2) run_app "$(project_for "")" ;;
            3) archive_logs "$(project_for "")" ;;
            *) echo "Bye." ;;
        esac ;;
    *) die "Unknown option '$1'. Try --help." ;;
esac
