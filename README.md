# deploy_agent

`deploy_agent.sh` deploys, runs and archives logs for the Student Attendance Tracker (`attendance_checker.py`, which is never modified).

## Setup
Put the three **unmodified** source files in `templates/`: `attendance_checker.py`, `assets.csv`, `config.json`. Requires `bash`, `python3`, `zip`.

## Running / choosing a feature
```
./deploy_agent.sh                      # interactive menu (1 Deploy, 2 Run, 3 Archive)
./deploy_agent.sh --deploy             # Feature 1
./deploy_agent.sh --run [name]         # Feature 2
./deploy_agent.sh --archive [name]     # Feature 3
```
`name` is the part after `attendance_tracker_`; it is asked for if omitted.

## Feature 1 - Deploy
Checks for `python3` and `zip`, asks for a project name, creates `attendance_tracker_{name}/` with `attendance_checker.py`, `Helpers/{assets.csv,config.json}` and an empty `reports/`. An existing directory prompts for overwrite (default: abort).
Roster options: **A** copies N rows (+ header) from `templates/assets.csv`; **B** generates N students (up to 20) with counts at 0.
**total_sessions** must be prior sessions + 1: Option A (4 prior sessions) keeps the template's `5`; Option B sets it to `1` with `sed`.
Permissions: `attendance_checker.py` is `chmod +x`, `config.json` is `chmod 600`; both are printed.
**Thresholds:** answer `y` and enter warning (default 75) and failure (default 50). Values must be integers, warning <= 100, failure < warning. `sed` rewrites only the `"warning": N` and `"failure": N` lines in place, so formatting and order are unchanged.
Finally the app is run (Feature 2) to verify the deployment.

## Feature 2 - Run
Runs the app on an already deployed project (the same as `cd attendance_tracker_{name} && python3 attendance_checker.py`):
```
./deploy_agent.sh --run demo      # runs attendance_tracker_demo
./deploy_agent.sh                 # menu option 2, then enter the project name
```
The terminal is handed to the instructor, who marks each student `P`/`A`. The app updates `Helpers/assets.csv` and appends to `reports/attendance.log` and `reports/absent.log`. If the project folder or `attendance_checker.py` is missing, the script exits with a clear error telling you to deploy first. Ctrl+C here is handled by the app itself (progress is saved), not by the deploy trap.
Note: each run adds one session, so before running again raise `total_sessions` in `Helpers/config.json` by 1 (the app prints a note when the roster and `total_sessions` disagree). It is mode 600, so edit it as the owner.

## Feature 3 - Archive
After a run, each existing log is copied into its own folder with a timestamp:
```
archives/attendance/attendance_YYYYMMDD_HHMMSS.log
archives/absent/absent_YYYYMMDD_HHMMSS.log
```
A missing log (e.g. no absentees) is reported and skipped without an error. Final paths are printed.

## Ctrl+C / Ctrl+Z during deploy
`INT` and `TSTP` are trapped from the moment the project directory is created until deployment finishes (they are released before the interactive app starts). On a signal the script prints a message, runs `zip -r attendance_tracker_{name}_archive.zip attendance_tracker_{name}`, removes the half-built directory and exits with code 130. The zip contains whatever existed so far (e.g. `attendance_checker.py`, `Helpers/`, `reports/`).
To test: run `--deploy`, enter a name, then press Ctrl+C (or Ctrl+Z) at the roster prompt; check `unzip -l attendance_tracker_{name}_archive.zip`.

## How the deployment was tested
Verified the layout with `ls -R`, the roster with `cat`, `config.json` thresholds and `total_sessions` with `cat`, permissions with `ls -l`, and ran the app at the end of deploy. Also tested Option A and B, overwrite decline, archive with a missing `absent.log`, and SIGINT mid-deploy.
