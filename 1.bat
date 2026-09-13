@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul 2>&1 || chcp 437 >nul 2>&1

REM =========================================================================
REM  YouTube Downloader - Windows Bootstrap + Embedded Bash Runtime
REM  Version 12.1  (explorer.exe browser launch, verbose output)
REM
REM  Usage:
REM    1.bat                 Normal run
REM    1.bat --fresh         Ignore checkpoints
REM    1.bat --no-install    Skip dependency installer
REM    1.bat --debug         Verbose tracing
REM    1.bat --keep-logs     Keep *.log files on exit
REM
REM  Install order:
REM    1. Git Bash          (winget)
REM    2. Python 3.12       (winget)  -- required for pip
REM    3. Node.js LTS       (winget)
REM    4. yt-dlp            (pip)
REM    5. FFmpeg            (pip via imageio-ffmpeg)
REM =========================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "BASH_EXE="
set "BASH_TMP=%SCRIPT_DIR%\.1sh_runtime.sh"
set "PS_HELPER=%TEMP%\.1sh_extract.ps1"
set "PG_DIR=%SCRIPT_DIR%\tools\git"
set "PG_DEST=%SCRIPT_DIR%\PortableGit.7z.exe"
set "PG_URL=https://github.com/git-for-windows/git/releases/latest/download/PortableGit-64-bit.7z.exe"

echo.
echo +==============================================================+
echo ^|   YOUTUBE DOWNLOADER - WINDOWS BOOTSTRAP                     ^|
echo ^|   Version 12.1  (single-file, verbose output)                ^|
echo +==============================================================+
echo.
echo [i] Invoked as : %~nx0
echo [i] Args       : %*
echo [i] Working dir: %CD%
echo [i] Script dir : %SCRIPT_DIR%
echo.

REM =========================================================================
REM  STEP 1: Locate real bash.exe (never the WSL stub)
REM =========================================================================
echo [1/4] Searching for bash.exe...

call :find_bash
if defined BASH_EXE goto :bash_ready

echo     No valid bash.exe found. Attempting installation.
goto :install_git


REM -------------------------------------------------------------------------
REM  SUBROUTINE: find_bash
REM -------------------------------------------------------------------------
:find_bash
set "BASH_EXE="

for %%P in (
    "%ProgramFiles%\Git\bin\bash.exe"
    "%ProgramFiles(x86)%\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
    "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
    "C:\msys64\usr\bin\bash.exe"
    "C:\cygwin64\bin\bash.exe"
    "C:\cygwin\bin\bash.exe"
    "%PG_DIR%\bin\bash.exe"
) do (
    if exist %%P (
        set "BASH_EXE=%%~P"
        goto :eof
    )
)

call :find_bash_in_path
goto :eof


:find_bash_in_path
setlocal EnableDelayedExpansion
for %%P in (bash.exe) do (
    set "CAND=%%~$PATH:P"
    if not "!CAND!"=="" (
        set "SKIP=0"
        echo !CAND! | findstr /i /c:"WindowsApps" >nul && set "SKIP=1"
        echo !CAND! | findstr /i /c:"System32"    >nul && set "SKIP=1"
        echo !CAND! | findstr /i /c:"\wsl"        >nul && set "SKIP=1"
        if "!SKIP!"=="0" (
            endlocal & set "BASH_EXE=!CAND!"
            goto :eof
        )
    )
)
endlocal
goto :eof


REM =========================================================================
REM  SUBROUTINE: cleanup_temp_files (batch-side safety net)
REM =========================================================================
:cleanup_temp_files
del "%SCRIPT_DIR%\.1sh_runtime.sh"         >nul 2>&1
del "%SCRIPT_DIR%\.1sh.state"              >nul 2>&1
del "%SCRIPT_DIR%\.1sh.pids"               >nul 2>&1
del "%SCRIPT_DIR%\.ps-install.log"         >nul 2>&1
del "%SCRIPT_DIR%\.pathdump.tmp"           >nul 2>&1
del "%SCRIPT_DIR%\export_cookies_fixed.py" >nul 2>&1
del "%SCRIPT_DIR%\.extract_cookies.py"     >nul 2>&1
del "%SCRIPT_DIR%\.openbrowser.ps1"        >nul 2>&1
del "%SCRIPT_DIR%\npm_install.log"         >nul 2>&1
del "%TEMP%\.1sh_extract.ps1"              >nul 2>&1

REM Remove generated cookies (regenerated on next run)
del "%SCRIPT_DIR%\cookies.txt"             >nul 2>&1
del "%SCRIPT_DIR%\server\cookies.txt"      >nul 2>&1

REM Remove backups and glob matches
del "%SCRIPT_DIR%\.runtool.*.out"          >nul 2>&1
del "%SCRIPT_DIR%\cookies.txt.bak.*"       >nul 2>&1
del "%SCRIPT_DIR%\cookies.txt.backup.*"    >nul 2>&1
del "%SCRIPT_DIR%\server\cookies.txt.bak.*"    >nul 2>&1
del "%SCRIPT_DIR%\server\cookies.txt.backup.*" >nul 2>&1
del "%SCRIPT_DIR%\server.js.backup.*"      >nul 2>&1
del "%SCRIPT_DIR%\server.js.bak.*"         >nul 2>&1
del "%SCRIPT_DIR%\server\server.js.backup.*" >nul 2>&1
del "%SCRIPT_DIR%\server\server.js.bak.*"    >nul 2>&1
del "%SCRIPT_DIR%\*.log.bak.*"             >nul 2>&1

echo %* | findstr /i /c:"--keep-logs" >nul
if errorlevel 1 (
    del "%SCRIPT_DIR%\1sh.log"     >nul 2>&1
    del "%SCRIPT_DIR%\cleanup.log" >nul 2>&1
    del "%SCRIPT_DIR%\server.log"  >nul 2>&1
)
goto :eof


REM =========================================================================
REM  STEP 2: Install Git Bash via winget
REM =========================================================================
:install_git
echo.
echo [2/4] Installing Git Bash via winget...

set "WINGET_OK=0"
where winget >nul 2>&1
if %errorlevel%==0 set "WINGET_OK=1"

set "WG_RC=1"
setlocal EnableDelayedExpansion
if "!WINGET_OK!"=="1" (
    echo     Running: winget install Git.Git
    winget install --id Git.Git -e --source winget ^
        --accept-package-agreements --accept-source-agreements --silent
    set "WG_RC=!errorlevel!"
) else (
    echo     winget not available.
    set "WG_RC=1"
)
endlocal & set "WG_RC=%WG_RC%"

if "%WINGET_OK%"=="1" if "%WG_RC%"=="0" (
    echo     winget returned success. Waiting 6 seconds...
    timeout /t 6 /nobreak >nul
    call :find_bash
    if defined BASH_EXE (
        echo     Found after install: %BASH_EXE%
        goto :bash_ready
    )
    echo     winget reported success but bash.exe not yet visible.
    echo     Close and reopen this window, then run 1.bat again.
    pause
    exit /b 1
)
if "%WINGET_OK%"=="1" if not "%WG_RC%"=="0" (
    echo     winget install failed ^(exit code %WG_RC%^)
)

echo.
echo     Trying PortableGit direct download...
set "DL_OK=0"

where curl >nul 2>&1
if %errorlevel%==0 (
    echo     Downloading via curl...
    curl -L --fail --retry 2 --connect-timeout 20 -o "%PG_DEST%" "%PG_URL%"
    if %errorlevel%==0 set "DL_OK=1"
)

if "%DL_OK%"=="0" (
    where powershell >nul 2>&1
    if %errorlevel%==0 (
        echo     Downloading via PowerShell...
        powershell -NoProfile -Command ^
            "try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -Uri '%PG_URL%' -OutFile '%PG_DEST%' -UseBasicParsing; exit 0 } catch { exit 1 }"
        if %errorlevel%==0 set "DL_OK=1"
    )
)

if "%DL_OK%"=="0" goto :install_failed
if not exist "%PG_DEST%" goto :install_failed

echo     Extracting PortableGit to %PG_DIR% ...
if not exist "%PG_DIR%" mkdir "%PG_DIR%" >nul 2>&1
"%PG_DEST%" -y -o"%PG_DIR%" >nul 2>&1

if exist "%PG_DIR%\bin\bash.exe" (
    set "BASH_EXE=%PG_DIR%\bin\bash.exe"
    echo     PortableGit ready: %BASH_EXE%
    del "%PG_DEST%" >nul 2>&1
    goto :bash_ready
)

:install_failed
echo.
echo +==============================================================+
echo ^|  Could not install Git Bash automatically.                   ^|
echo ^|                                                              ^|
echo ^|  Install manually:                                           ^|
echo ^|    winget install --id Git.Git -e --source winget            ^|
echo ^|                                                              ^|
echo ^|  Or download from: https://git-scm.com/download/win          ^|
echo ^|                                                              ^|
echo ^|  Then run 1.bat again.                                       ^|
echo +==============================================================+
pause
exit /b 1


:bash_ready
echo     Using: %BASH_EXE%


REM =========================================================================
REM  STEP 3: Extract embedded bash script
REM =========================================================================
echo.
echo [3/4] Extracting embedded bash script...

REM Clean up leftovers from previous crashed run
call :cleanup_temp_files

> "%PS_HELPER%" echo $ErrorActionPreference = 'Stop'
>>"%PS_HELPER%" echo $bat = $env:BAT_PATH
>>"%PS_HELPER%" echo $out = $env:OUT_PATH
>>"%PS_HELPER%" echo $lines = Get-Content -LiteralPath $bat -Encoding UTF8
>>"%PS_HELPER%" echo $start = -1
>>"%PS_HELPER%" echo $end = -1
>>"%PS_HELPER%" echo for ($i = 0; $i -lt $lines.Count; $i++) {
>>"%PS_HELPER%" echo   if ($lines[$i] -match '^REM\s+BASH_SCRIPT_START\s*$') { $start = $i + 1 }
>>"%PS_HELPER%" echo   if ($lines[$i] -match '^REM\s+BASH_SCRIPT_END\s*$')   { $end   = $i - 1; break }
>>"%PS_HELPER%" echo }
>>"%PS_HELPER%" echo if ($start -lt 0) { Write-Error 'START marker missing'; exit 1 }
>>"%PS_HELPER%" echo if ($end   -lt 0) { Write-Error 'END marker missing';   exit 1 }
>>"%PS_HELPER%" echo $slice = $lines[$start..$end]
>>"%PS_HELPER%" echo $lf = [char]10
>>"%PS_HELPER%" echo $crlf = [string][char]13 + [string][char]10
>>"%PS_HELPER%" echo $joined = [string]::Join($lf, $slice)
>>"%PS_HELPER%" echo $text = $joined.Replace($crlf, $lf)
>>"%PS_HELPER%" echo $utf8 = New-Object System.Text.UTF8Encoding($false)
>>"%PS_HELPER%" echo [System.IO.File]::WriteAllText($out, $text, $utf8)
>>"%PS_HELPER%" echo Write-Host ('     Wrote ' + $slice.Count + ' lines to ' + $out)

set "BAT_PATH=%~f0"
set "OUT_PATH=%BASH_TMP%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%"

if not exist "%BASH_TMP%" (
    echo     Extraction failed.
    del "%PS_HELPER%" >nul 2>&1
    pause
    exit /b 1
)
del "%PS_HELPER%" >nul 2>&1
echo     OK


REM =========================================================================
REM  STEP 4: Run embedded bash script
REM =========================================================================
echo.
echo [4/4] Running embedded bash script...
echo.

set "BASH_TMP_UNIX=%BASH_TMP:\=/%"
echo     bash path: %BASH_TMP_UNIX%
echo.

"%BASH_EXE%" "%BASH_TMP_UNIX%" %*
set "EXIT_CODE=%errorlevel%"

echo.
echo [i] Bash script exited with code %EXIT_CODE%

REM Batch-side temp file cleanup (safety net for hard kills)
call :cleanup_temp_files

del "%BASH_TMP%" >nul 2>&1

echo.
if not "%EXIT_CODE%"=="0" (
    echo [!] Non-zero exit code - press any key to close.
) else (
    echo Press any key to close this window...
)
pause >nul

endlocal
if "%EXIT_CODE%"=="" set "EXIT_CODE=0"
exit /b %EXIT_CODE%

exit /b 0


REM =========================================================================
REM  BELOW: EMBEDDED BASH SCRIPT
REM =========================================================================
REM BASH_SCRIPT_START
#!/usr/bin/env bash
# -------------------------------------------------------------------------
#  Embedded runtime - ordered install, verbose output, explorer.exe browser
# -------------------------------------------------------------------------

# =========================================================================
# CONFIG (used by cleanup traps - must be first)
# =========================================================================

SCRIPT_DIR_EARLY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="$SCRIPT_DIR_EARLY/cleanup.log"
GRACEFUL_DELAY=0

# =========================================================================
# LOGGING (verbose)
# =========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" 2>/dev/null || true

STATE_FILE="$SCRIPT_DIR/.1sh.state"
PID_FILE="$SCRIPT_DIR/.1sh.pids"
LOG_FILE="$SCRIPT_DIR/1sh.log"

# =========================================================================
#  CONFIG BLOCK - PORT, URL, and path variables
# =========================================================================
SERVER_DIR=""
SERVER_JS=""
TOOLS_DIR="$SCRIPT_DIR/tools"
FFMPEG_DIR="$TOOLS_DIR/ffmpeg"
COOKIES_FILE="$SCRIPT_DIR/server/cookies.txt"
PORT=3000
URL="http://localhost:$PORT"

# -- Args --
FRESH_RUN=false
SKIP_INSTALL=false
DEBUG_MODE=false
KEEP_LOGS=false
for arg in "$@"; do
    case "$arg" in
        --fresh)      FRESH_RUN=true ;;
        --no-install) SKIP_INSTALL=true ;;
        --debug)      DEBUG_MODE=true; set -x ;;
        --keep-logs)  KEEP_LOGS=true ;;
    esac
done

[ "$FRESH_RUN" = true ] && rm -f "$STATE_FILE"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE" 2>/dev/null || true; }
log()   { echo -e "${GREEN}[v]${NC} $*"; _log "INFO $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; _log "WARN $*"; }
error() { echo -e "${RED}[x]${NC} $*"; _log "ERR  $*"; }
dbg()   { [ "$DEBUG_MODE" = true ] && echo -e "${BLUE}[.]${NC} $*"; _log "DBG  $*"; }
ok()    { echo -e "${CYAN}${BOLD}[OK]${NC} $*"; _log "OK   $*"; }
step()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; _log "STEP $*"; }
info()  { echo -e "$*"; _log "INFO $*"; }

# =========================================================================
# OS DETECTION
# =========================================================================

IS_WSL=false
IS_MAC=false
IS_LINUX=false
IS_WINDOWS=false
IS_CYGWIN=false
IS_MSYS=false

if grep -qE "Microsoft|WSL" /proc/version 2>/dev/null; then
    IS_WSL=true; OS_NAME="WSL (Windows)"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MAC=true; OS_NAME="macOS"
elif [[ "$OSTYPE" == "cygwin"* ]]; then
    IS_CYGWIN=true; IS_WINDOWS=true; OS_NAME="Windows (Cygwin)"
elif [[ "$OSTYPE" == "msys"* ]]; then
    IS_MSYS=true; IS_WINDOWS=true; OS_NAME="Windows (MSYS/Git Bash)"
elif [[ "$OSTYPE" == "win32"* ]]; then
    IS_WINDOWS=true; OS_NAME="Windows"
elif [[ "$OSTYPE" == "linux"* ]]; then
    IS_LINUX=true; OS_NAME="Linux"
else
    OS_NAME="Unknown ($OSTYPE)"
fi

[ -n "$WINDIR" ] || [ -n "$windir" ] && IS_WINDOWS=true

# =========================================================================
# PROCESS CLEANUP
# =========================================================================

cleanup_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$CLEANUP_LOG"
}

detect_os_type() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) OS_TYPE="windows" ;;
        Linux*)               OS_TYPE="linux" ;;
        Darwin*)              OS_TYPE="macos" ;;
        *)                    OS_TYPE="unix" ;;
    esac
}

cleanup_windows_processes() {
    local killed=0
    if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/.1sh.pids" ]; then
        while read -r p; do
            [ -n "$p" ] || continue
            taskkill //F //PID "$p" 2>/dev/null && killed=$((killed + 1))
        done < "$SCRIPT_DIR/.1sh.pids"
        rm -f "$SCRIPT_DIR/.1sh.pids"
    fi
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null
    fi
}

cleanup_unix_processes() {
    if command -v pkill &> /dev/null; then
        local children=$(pgrep -P $$ 2>/dev/null)
        if [ -n "$children" ]; then
            echo "$children" | while read -r child_pid; do
                kill "$child_pid" 2>/dev/null
            done
        fi
    fi
}

cleanup_processes_force() {
    if [ -n "${SCRIPT_DIR:-}" ] && [ -f "$SCRIPT_DIR/.1sh.pids" ]; then
        while read -r p; do
            [ -n "$p" ] && taskkill //F //PID "$p" 2>/dev/null || true
        done < "$SCRIPT_DIR/.1sh.pids"
        rm -f "$SCRIPT_DIR/.1sh.pids"
    fi
    if [ -n "${SERVER_PID:-}" ]; then
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
}

graceful_cleanup() {
    detect_os_type
    case "$OS_TYPE" in
        windows|msys|cygwin) cleanup_windows_processes ;;
        *)                   cleanup_unix_processes ;;
    esac
    cleanup_processes_force
}

# =========================================================================
# TEMP FILE CLEANUP (removes every script-generated file on exit)
# =========================================================================
cleanup_temp_files() {
    set +e 2>/dev/null

    local removed=0

    local files=(
        "$SCRIPT_DIR/.1sh_runtime.sh"
        "$SCRIPT_DIR/.1sh.state"
        "$SCRIPT_DIR/.1sh.pids"
        "$SCRIPT_DIR/.ps-install.log"
        "$SCRIPT_DIR/.pathdump.tmp"
        "$SCRIPT_DIR/.openbrowser.ps1"
        "$SCRIPT_DIR/export_cookies_fixed.py"
        "$SCRIPT_DIR/.extract_cookies.py"
        "$SCRIPT_DIR/npm_install.log"
        "/tmp/npm_install.log"
        "$TEMP/.1sh_extract.ps1"
        # Cookies — regenerated on every run
        "$SCRIPT_DIR/cookies.txt"
        "$SCRIPT_DIR/server/cookies.txt"
    )

    for f in "${files[@]}"; do
        [ -e "$f" ] && rm -f "$f" 2>/dev/null && removed=$((removed + 1))
    done

    for pattern in \
        "$SCRIPT_DIR/.runtool."*".out" \
        "$SCRIPT_DIR/cookies.txt.bak."* \
        "$SCRIPT_DIR/cookies.txt.backup."* \
        "$SCRIPT_DIR/server/cookies.txt.bak."* \
        "$SCRIPT_DIR/server/cookies.txt.backup."* \
        "$SCRIPT_DIR/server.js.backup."* \
        "$SCRIPT_DIR/server.js.bak."* \
        "$SCRIPT_DIR/server/server.js.backup."* \
        "$SCRIPT_DIR/server/server.js.bak."*
    do
        [ -e "$pattern" ] && rm -f "$pattern" 2>/dev/null && removed=$((removed + 1))
    done

    if [ "$KEEP_LOGS" != true ]; then
        for f in "$SCRIPT_DIR/1sh.log" "$SCRIPT_DIR/cleanup.log" "$SCRIPT_DIR/server.log"; do
            [ -e "$f" ] && rm -f "$f" 2>/dev/null && removed=$((removed + 1))
        done
    fi

    [ "$DEBUG_MODE" = true ] && echo "[cleanup] removed $removed temp file(s)"
    return 0
}

trap 'graceful_cleanup; cleanup_temp_files' EXIT
trap 'cleanup_processes_force; cleanup_temp_files; exit 130' INT
trap 'graceful_cleanup; cleanup_temp_files; exit 143' TERM
trap 'graceful_cleanup; cleanup_temp_files; exit 129' HUP
trap 'graceful_cleanup; cleanup_temp_files; exit 131' QUIT

# =========================================================================
# ACTIVITY-AWARE TIMEOUT
# =========================================================================
run_with_timeout() {
    local timeout_seconds="${RUN_TIMEOUT_SECONDS:-300}"
    local max_retries="${RUN_TIMEOUT_RETRIES:-2}"
    local hard_cap_mult="${RUN_TIMEOUT_HARD_CAP:-20}"
    local retry_count=0
    local cmd="$@"

    while [ $retry_count -le $max_retries ]; do
        log "Running: $cmd (attempt $((retry_count+1))/$((max_retries+1)))"

        local outlog="$SCRIPT_DIR/.runtool.$$.out"
        : > "$outlog"

        eval "$cmd" < /dev/null > "$outlog" 2>&1 &
        local CMD_PID=$!

        local elapsed=0
        local last_size=0
        local idle_seconds=0
        local hard_cap=$((timeout_seconds * hard_cap_mult))
        local last_progress_print=0

        while kill -0 $CMD_PID 2>/dev/null; do
            sleep 5
            elapsed=$((elapsed + 5))

            local current_size=0
            if [ -f "$outlog" ]; then
                current_size=$(wc -c < "$outlog" 2>/dev/null | tr -d ' \r\n')
                [ -z "$current_size" ] && current_size=0
            fi

            if [ "$current_size" -gt "$last_size" ]; then
                idle_seconds=0
                last_size=$current_size
            else
                idle_seconds=$((idle_seconds + 5))
            fi

            if [ $((elapsed - last_progress_print)) -ge 30 ]; then
                last_progress_print=$elapsed
                log "  ... running (${elapsed}s elapsed, idle ${idle_seconds}s, output ${current_size} bytes)"
            fi

            if [ "$idle_seconds" -ge "$timeout_seconds" ]; then
                warn "Process IDLE for ${idle_seconds}s - killing (assumed hung)"
                if [ "$IS_WINDOWS" = true ]; then
                    taskkill //PID $CMD_PID //F //T 2>/dev/null || true
                    taskkill //IM pip.exe //F 2>/dev/null || true
                    taskkill //IM pip3.exe //F 2>/dev/null || true
                    taskkill //IM winget.exe //F //T 2>/dev/null || true
                    taskkill //IM node.exe //F 2>/dev/null || true
                else
                    kill -9 $CMD_PID 2>/dev/null || true
                fi
                sleep 3
                wait $CMD_PID 2>/dev/null || true
                rm -f "$outlog"
                log "Waiting 10s before retry..."
                sleep 10
                retry_count=$((retry_count + 1))
                continue 2
            fi

            if [ "$elapsed" -ge "$hard_cap" ]; then
                warn "Process HARD CAP reached (${elapsed}s) - killing"
                if [ "$IS_WINDOWS" = true ]; then
                    taskkill //PID $CMD_PID //F //T 2>/dev/null || true
                    taskkill //IM winget.exe //F //T 2>/dev/null || true
                else
                    kill -9 $CMD_PID 2>/dev/null || true
                fi
                sleep 3
                wait $CMD_PID 2>/dev/null || true
                rm -f "$outlog"
                retry_count=$((retry_count + 1))
                continue 2
            fi
        done

        wait $CMD_PID 2>/dev/null
        local EXIT_CODE=$?

        if [ -s "$outlog" ] && [ "$DEBUG_MODE" = true ]; then
            dbg "Final output:"
            tail -n 20 "$outlog" | while read -r line; do
                dbg "  | $line"
            done
        fi
        rm -f "$outlog"

        if [ $EXIT_CODE -eq 0 ]; then
            ok "Command completed successfully!"
            return 0
        else
            warn "Command failed with exit code: $EXIT_CODE"
            retry_count=$((retry_count + 1))
            [ $retry_count -le $max_retries ] && {
                log "Waiting 10 seconds before retry..."
                sleep 10
            }
        fi
    done
    error "Failed after $((max_retries+1)) attempts"
    return 1
}

# =========================================================================
# PATH AUGMENTATION
# =========================================================================
add_known_tool_dirs() {
    local candidates=(
        "$LOCALAPPDATA/Microsoft/WinGet/Links"
        "/c/Program Files/Git/bin"
        "/c/Program Files/Git/usr/bin"
        "/c/Program Files/Git/usr/local/bin"
        "/c/Program Files/nodejs"
        "/c/Program Files/Python313"
        "/c/Program Files/Python313/Scripts"
        "/c/Program Files/Python312"
        "/c/Program Files/Python312/Scripts"
        "/c/Program Files/Python311"
        "/c/Program Files/Python311/Scripts"
        "$LOCALAPPDATA/Programs/Python/Python313"
        "$LOCALAPPDATA/Programs/Python/Python313/Scripts"
        "$LOCALAPPDATA/Programs/Python/Python312"
        "$LOCALAPPDATA/Programs/Python/Python312/Scripts"
        "$LOCALAPPDATA/Programs/Python/Python311"
        "$LOCALAPPDATA/Programs/Python/Python311/Scripts"
        "$USERPROFILE/AppData/Local/Microsoft/WinGet/Links"
        "/usr/local/bin"
        "$HOME/.local/bin"
    )
    local n=0
    for d in "${candidates[@]}"; do
        if [ -d "$d" ]; then
            case ":$PATH:" in
                *":$d:"*) ;;
                *) PATH="$d:$PATH"; n=$((n + 1)) ;;
            esac
        fi
    done
    [ "$n" -gt 0 ] && ok "PATH: added $n known tool directories"
    return 0
}

# =========================================================================
# REAL BINARY RESOLVER (skips WSL stubs)
# =========================================================================
resolve_real_binary() {
    local name="$1"
    local candidates=()

    case "$name" in
        node|node.exe)
            candidates=( "/c/Program Files/nodejs/node.exe" "/c/Program Files/nodejs/node" "$LOCALAPPDATA/Programs/nodejs/node.exe" )
            ;;
        npm|npm.cmd)
            candidates=( "/c/Program Files/nodejs/npm.cmd" "/c/Program Files/nodejs/npm" "$LOCALAPPDATA/Programs/nodejs/npm.cmd" )
            ;;
        npx|npx.cmd)
            candidates=( "/c/Program Files/nodejs/npx.cmd" "/c/Program Files/nodejs/npx" )
            ;;
        python|python.exe)
            candidates=(
                "$LOCALAPPDATA/Programs/Python/Python313/python.exe"
                "$LOCALAPPDATA/Programs/Python/Python312/python.exe"
                "$LOCALAPPDATA/Programs/Python/Python311/python.exe"
                "/c/Program Files/Python313/python.exe"
                "/c/Program Files/Python312/python.exe"
                "/c/Program Files/Python311/python.exe"
            )
            ;;
        python3|python3.exe)
            local py
            py=$(resolve_real_binary "python") || true
            [ -n "$py" ] && { echo "$py"; return 0; }
            candidates=(
                "$LOCALAPPDATA/Programs/Python/Python313/python3.exe"
                "$LOCALAPPDATA/Programs/Python/Python312/python3.exe"
                "$LOCALAPPDATA/Programs/Python/Python311/python3.exe"
            )
            ;;
        pip|pip.exe|pip3|pip3.exe)
            local py
            py=$(resolve_real_binary "python") || true
            if [ -n "$py" ]; then
                local pydir
                pydir="$(dirname "$py")"
                for f in pip.exe pip3.exe pip pip3; do
                    [ -x "$pydir/Scripts/$f" ] && { echo "$pydir/Scripts/$f"; return 0; }
                    [ -x "$pydir/$f" ] && { echo "$pydir/$f"; return 0; }
                done
            fi
            return 1
            ;;
        yt-dlp|yt-dlp.exe)
            local py
            py=$(resolve_real_binary "python") || true
            if [ -n "$py" ]; then
                local pydir
                pydir="$(dirname "$py")"
                for f in yt-dlp.exe yt-dlp; do
                    [ -x "$pydir/Scripts/$f" ] && { echo "$pydir/Scripts/$f"; return 0; }
                    [ -x "$pydir/$f" ] && { echo "$pydir/$f"; return 0; }
                done
            fi
            candidates=(
                "$LOCALAPPDATA/Microsoft/WinGet/Links/yt-dlp.exe"
                "$LOCALAPPDATA/Programs/Python/Python313/Scripts/yt-dlp.exe"
                "$LOCALAPPDATA/Programs/Python/Python312/Scripts/yt-dlp.exe"
                "$HOME/.local/bin/yt-dlp.exe"
                "$HOME/.local/bin/yt-dlp"
            )
            ;;
        ffmpeg|ffmpeg.exe)
            local py
            py=$(resolve_real_binary "python") || true
            if [ -n "$py" ]; then
                local pydir
                pydir="$(dirname "$py")"
                for sub in "Lib/site-packages/imageio_ffmpeg/binaries" "lib/site-packages/imageio_ffmpeg/binaries"; do
                    if [ -d "$pydir/$sub" ]; then
                        local f
                        f=$(find "$pydir/$sub" -maxdepth 1 -name "ffmpeg*.exe" 2>/dev/null | head -1)
                        [ -n "$f" ] && [ -x "$f" ] && { echo "$f"; return 0; }
                    fi
                done
            fi
            if [ -n "$LOCALAPPDATA" ]; then
                local sf
                sf=$(find "$LOCALAPPDATA" -maxdepth 4 -name "ffmpeg.exe" -path "*static_ffmpeg*" 2>/dev/null | head -1)
                [ -n "$sf" ] && [ -x "$sf" ] && { echo "$sf"; return 0; }
            fi
            candidates=(
                "/c/ProgramData/chocolatey/bin/ffmpeg.exe"
                "/c/Program Files/ffmpeg/bin/ffmpeg.exe"
                "$LOCALAPPDATA/Microsoft/WinGet/Links/ffmpeg.exe"
            )
            ;;
    esac

    local c
    for c in "${candidates[@]}"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done

    local found=""
    while IFS= read -r line; do
        case "$line" in
            *WindowsApps*) continue ;;
            *wsl*)         continue ;;
            *)             found="$line"; break ;;
        esac
    done < <(command -v -a "$name" 2>/dev/null)

    [ -n "$found" ] && { echo "$found"; return 0; }
    return 1
}

# =========================================================================
# SAFE VERSION CHECK
# =========================================================================
safe_version() {
    local bin="$1"
    [ -z "$bin" ] && { echo "unknown"; return 1; }
    local v
    v=$("$bin" --version 2>&1 | head -1 | tr -d '\r\n\0')
    [ -z "$v" ] && echo "(version unknown)" || echo "$v"
}

# =========================================================================
# INVOKE .CMD / .EXE
# =========================================================================
run_native_binary() {
    local bin="$1"; shift
    case "$bin" in
        *.cmd|*.CMD)
            local winpath
            winpath=$(cygpath -w "$bin" 2>/dev/null || echo "$bin")
            MSYS_NO_PATHCONV=1 cmd //c "$winpath" "$@" < /dev/null
            ;;
        *)
            "$bin" "$@" < /dev/null
            ;;
    esac
}

# =========================================================================
# REFRESH PATH FROM WINDOWS REGISTRY
# =========================================================================
refresh_windows_path() {
    [ "$IS_WINDOWS" != true ] && return 0

    local ps_exe=""
    if command -v pwsh >/dev/null 2>&1; then
        ps_exe="pwsh"
    elif [ -f "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
        ps_exe="/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    elif command -v powershell >/dev/null 2>&1; then
        ps_exe="powershell"
    fi

    [ -z "$ps_exe" ] && return 0

    local tmp="$SCRIPT_DIR/.pathdump.tmp"
    : > "$tmp"

    RUN_TIMEOUT_SECONDS=15 RUN_TIMEOUT_RETRIES=0 \
        run_with_timeout "env MSYS_NO_PATHCONV=1 $ps_exe -NoProfile -NonInteractive -Command \"[Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')\"" \
        > "$tmp" 2>/dev/null

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 0
    fi

    local raw
    raw=$(tr -d '\r' < "$tmp" 2>/dev/null)
    rm -f "$tmp"

    [ -z "$raw" ] && return 0

    local unix_path=""
    command -v cygpath >/dev/null 2>&1 && unix_path=$(cygpath -up "$raw" 2>/dev/null)
    [ -z "$unix_path" ] && unix_path=$(echo "$raw" | tr ';' ':' | sed -E 's|([A-Za-z]):\\|/\L\1/|g; s|\\|/|g')

    [ -n "$unix_path" ] && export PATH="$unix_path:$PATH"
    ok "PATH refreshed from Windows registry"
    return 0
}

# =========================================================================
# TOOL INSTALL HELPERS (verbose)
# =========================================================================
winget_install_if_missing() {
    local resolver_name="$1"
    local winget_id="$2"
    local display_name="$3"

    local existing
    existing=$(resolve_real_binary "$resolver_name") || true
    if [ -n "$existing" ]; then
        ok "$display_name already present: $(safe_version "$existing")  [$existing]"
        return 0
    fi

    if ! command -v winget >/dev/null 2>&1; then
        warn "winget not available - cannot install $display_name"
        return 1
    fi

    log "$display_name not found - installing via winget..."
    log "  Package: $winget_id"

    local wt="${WINGET_TIMEOUT:-600}"
    RUN_TIMEOUT_SECONDS=$wt RUN_TIMEOUT_RETRIES=1 RUN_TIMEOUT_HARD_CAP=20 \
        run_with_timeout "env MSYS_NO_PATHCONV=1 winget install --id $winget_id -e --source winget --accept-package-agreements --accept-source-agreements --silent"

    add_known_tool_dirs
    refresh_windows_path

    existing=$(resolve_real_binary "$resolver_name") || true
    if [ -n "$existing" ]; then
        ok "$display_name installed: $(safe_version "$existing")  [$existing]"
        return 0
    else
        warn "$display_name install may have failed"
        return 1
    fi
}

pip_install_or_upgrade() {
    local pkg="$1"
    local display_name="$2"
    local resolver_name="${3:-}"

    local py_bin
    py_bin=$(resolve_real_binary "python") || true
    if [ -z "$py_bin" ]; then
        error "Python not available - cannot pip install $display_name"
        return 1
    fi

    log "Installing/upgrading $display_name via pip..."
    log "  Package: $pkg"
    log "  Python: $py_bin"

    local pt="${PIP_TIMEOUT:-600}"
    if RUN_TIMEOUT_SECONDS=$pt RUN_TIMEOUT_RETRIES=1 RUN_TIMEOUT_HARD_CAP=20 \
        run_with_timeout "\"$py_bin\" -m pip install --no-input --no-cache-dir --upgrade $pkg"; then
        add_known_tool_dirs
        refresh_windows_path
        if [ -n "$resolver_name" ]; then
            local existing
            existing=$(resolve_real_binary "$resolver_name") || true
            if [ -n "$existing" ]; then
                ok "$display_name ready: $(safe_version "$existing")  [$existing]"
            else
                warn "$display_name installed but not found on PATH"
            fi
        fi
        return 0
    else
        warn "pip install of $pkg failed"
        return 1
    fi
}

# =========================================================================
# INSTALL / CHECK DEPENDENCIES (ordered)
# =========================================================================
install_missing_tools() {
    step "INSTALLING / UPDATING TOOLS"

    if [ "$SKIP_INSTALL" = true ]; then
        warn "--no-install: skipping tool installer"
        return 0
    fi

    export PATH="$LOCALAPPDATA/Microsoft/WinGet/Links:$PATH"

    echo ""
    log "== Step 1/5: Git Bash =="
    if [ -x "/c/Program Files/Git/bin/bash.exe" ]; then
        ok "Git Bash already present: /c/Program Files/Git/bin/bash.exe"
    else
        winget_install_if_missing "bash" "Git.Git" "Git Bash"
    fi

    echo ""
    log "== Step 2/5: Python =="
    winget_install_if_missing "python" "Python.Python.3.12" "Python 3.12"

    echo ""
    log "== Step 3/5: Node.js =="
    winget_install_if_missing "node" "OpenJS.NodeJS.LTS" "Node.js LTS"

    echo ""
    log "== Step 4/5: yt-dlp =="
    pip_install_or_upgrade "yt-dlp" "yt-dlp" "yt-dlp"

    echo ""
    log "== Step 5/5: FFmpeg =="
    if ! pip_install_or_upgrade "imageio-ffmpeg" "FFmpeg (imageio-ffmpeg)" "ffmpeg"; then
        warn "Trying static-ffmpeg as fallback..."
        pip_install_or_upgrade "static-ffmpeg" "FFmpeg (static-ffmpeg)" "ffmpeg"
    fi

    add_known_tool_dirs
    refresh_windows_path

    echo ""
    log "Post-install tool check:"
    for t in node npm python yt-dlp ffmpeg git; do
        local r
        r=$(resolve_real_binary "$t") || true
        if [ -n "$r" ]; then
            ok "  $t -> $r  ($(safe_version "$r"))"
        else
            warn "  $t -> STILL MISSING"
        fi
    done

    return 0
}

# =========================================================================
# DETECT REPOSITORY STRUCTURE
# =========================================================================
detect_repo_structure() {
    step "DETECTING REPOSITORY STRUCTURE"

    log "Analyzing current directory structure..."
    find "$SCRIPT_DIR" -maxdepth 2 -type f \( -name "*.js" -o -name "*.json" -o -name "*.html" \) 2>/dev/null | head -20

    local FOUND_SERVER=false

    if [ -f "$SCRIPT_DIR/server/server.js" ]; then
        SERVER_DIR="$SCRIPT_DIR/server"
        SERVER_JS="$SCRIPT_DIR/server/server.js"
        FOUND_SERVER=true
        ok "Found: server.js in /server subfolder"
    elif [ -f "$SCRIPT_DIR/server.js" ]; then
        SERVER_DIR="$SCRIPT_DIR"
        SERVER_JS="$SCRIPT_DIR/server.js"
        FOUND_SERVER=true
        ok "Found: server.js in root folder"
    else
        log "Searching for server files..."
        for possible_name in "server.js" "app.js" "index.js" "main.js"; do
            if [ -f "$SCRIPT_DIR/$possible_name" ] && grep -q "express\|require\|http\|listen\|app\.get\|app\.post" "$SCRIPT_DIR/$possible_name" 2>/dev/null; then
                SERVER_DIR="$SCRIPT_DIR"
                SERVER_JS="$SCRIPT_DIR/$possible_name"
                FOUND_SERVER=true
                ok "Found server file: $possible_name (in root)"
                break
            fi
            if [ -f "$SCRIPT_DIR/server/$possible_name" ] && grep -q "express\|require\|http\|listen\|app\.get\|app\.post" "$SCRIPT_DIR/server/$possible_name" 2>/dev/null; then
                SERVER_DIR="$SCRIPT_DIR/server"
                SERVER_JS="$SCRIPT_DIR/server/$possible_name"
                FOUND_SERVER=true
                ok "Found server file: $possible_name (in /server)"
                break
            fi
        done
    fi

    if [ "$FOUND_SERVER" = false ]; then
        error "Could NOT find server.js or any server file!"
        SERVER_DIR="$SCRIPT_DIR"
        SERVER_JS="$SCRIPT_DIR/server.js"
    else
        ok "Repository structure detected!"
        log "Server directory: ${BOLD}$SERVER_DIR${NC}"
        log "Server file: ${BOLD}$SERVER_JS${NC}"
        COOKIES_FILE="$SERVER_DIR/cookies.txt"
    fi
}

# =========================================================================
# FALLBACK: yt-dlp
# =========================================================================
install_ytdl() {
    step "YT-DLP VERIFICATION"

    local YTDLP_BIN
    YTDLP_BIN=$(resolve_real_binary "yt-dlp") || true
    if [ -n "$YTDLP_BIN" ]; then
        ok "yt-dlp available: $(safe_version "$YTDLP_BIN")  [$YTDLP_BIN]"
        return 0
    fi

    warn "yt-dlp missing - attempting pip install..."
    pip_install_or_upgrade "yt-dlp" "yt-dlp" "yt-dlp"
}

# =========================================================================
# FALLBACK: FFmpeg
# =========================================================================
setup_ffmpeg() {
    step "FFMPEG VERIFICATION"

    local FF_BIN
    FF_BIN=$(resolve_real_binary "ffmpeg") || true
    if [ -n "$FF_BIN" ]; then
        ok "FFmpeg available: $FF_BIN"
        return 0
    fi

    warn "FFmpeg missing - attempting pip install..."
    pip_install_or_upgrade "imageio-ffmpeg" "FFmpeg (imageio-ffmpeg)" "ffmpeg" || \
        pip_install_or_upgrade "static-ffmpeg" "FFmpeg (static-ffmpeg)" "ffmpeg"
}

# =========================================================================
# BROWSER DETECTION
# =========================================================================
detect_browser() {
    echo "[v] Detecting browsers for cookie extraction..." >&2

    if [ "$IS_WINDOWS" = true ] || [ "$IS_CYGWIN" = true ] || [ "$IS_MSYS" = true ]; then
        if [ -d "$LOCALAPPDATA/Microsoft/Edge/User Data" ]; then
            echo "[OK] Found browser: edge" >&2
            echo "edge"; return 0
        fi
        if [ -d "$LOCALAPPDATA/Google/Chrome/User Data" ]; then
            echo "[OK] Found browser: chrome" >&2
            echo "chrome"; return 0
        fi
        if [ -d "$LOCALAPPDATA/Vivaldi/User Data" ]; then
            echo "[OK] Found browser: vivaldi" >&2
            echo "vivaldi"; return 0
        fi
        if [ -d "$LOCALAPPDATA/BraveSoftware/Brave-Browser/User Data" ]; then
            echo "[OK] Found browser: brave" >&2
            echo "brave"; return 0
        fi
        if [ -d "$APPDATA/Mozilla/Firefox/Profiles" ]; then
            echo "[OK] Found browser: firefox" >&2
            echo "firefox"; return 0
        fi
    elif [ "$IS_MAC" = true ]; then
        [ -d "$HOME/Library/Application Support/Microsoft Edge" ] && { echo "edge"; return 0; }
        [ -d "$HOME/Library/Application Support/Google/Chrome" ] && { echo "chrome"; return 0; }
        [ -d "$HOME/Library/Application Support/Firefox/Profiles" ] && { echo "firefox"; return 0; }
    else
        [ -d "$HOME/.config/microsoft-edge" ] && { echo "edge"; return 0; }
        [ -d "$HOME/.config/google-chrome" ] && { echo "chrome"; return 0; }
        [ -d "$HOME/.mozilla/firefox" ] && { echo "firefox"; return 0; }
    fi

    echo "[ERROR] No supported browser found!" >&2
    return 1
}

# =========================================================================
# TEST COOKIES
# =========================================================================
test_cookies() {
    local BROWSER="$1"
    log "Testing cookie extraction from $BROWSER..."

    local YTDLP_BIN
    YTDLP_BIN=$(resolve_real_binary "yt-dlp") || YTDLP_BIN="yt-dlp"

    local TEST_OUTPUT
    if TEST_OUTPUT=$("$YTDLP_BIN" --cookies-from-browser "$BROWSER" --skip-download --flat-playlist "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1); then
        ok "Cookie extraction working!"
        return 0
    else
        warn "Cookie test warning (may still work):"
        echo "$TEST_OUTPUT" | tail -5
        return 0
    fi
}

# =========================================================================
# CHECK EXISTING COOKIES
# =========================================================================
check_existing_cookies() {
    log "Checking for existing cookies.txt..."

    if [ -f "$COOKIES_FILE" ] && [ -s "$COOKIES_FILE" ]; then
        local n
        n=$(grep -vc '^#\|^$' "$COOKIES_FILE" 2>/dev/null || echo "0")
        if [ "$n" -gt 0 ]; then
            ok "cookies.txt already exists with $n cookie entries!"
            export COOKIES_EXPORTED=true
            return 0
        fi
    fi

    if [ -f "$SCRIPT_DIR/cookies.txt" ] && [ -s "$SCRIPT_DIR/cookies.txt" ]; then
        local n
        n=$(grep -vc '^#\|^$' "$SCRIPT_DIR/cookies.txt" 2>/dev/null || echo "0")
        if [ "$n" -gt 0 ]; then
            ok "cookies.txt found in script directory with $n entries"
            mkdir -p "$(dirname "$COOKIES_FILE")"
            cp "$SCRIPT_DIR/cookies.txt" "$COOKIES_FILE"
            ok "cookies.txt copied to: $COOKIES_FILE"
            export COOKIES_EXPORTED=true
            return 0
        fi
    fi

    log "No existing cookies.txt found."
    export COOKIES_EXPORTED=false
    return 1
}

# =========================================================================
# KILL EDGE + EXTRACT COOKIES
# =========================================================================
kill_edge_and_extract_cookies() {
    step "AGGRESSIVELY KILLING EDGE & EXTRACTING COOKIES"

    log "Edge must be completely closed to extract cookies."

    check_edge_running() {
        if [ "$IS_WINDOWS" = true ] || [ "$IS_CYGWIN" = true ] || [ "$IS_MSYS" = true ]; then
            if command -v tasklist >/dev/null 2>&1; then
                tasklist 2>/dev/null | grep -i "msedge.exe" >/dev/null 2>&1
                return $?
            elif [ -f /c/Windows/System32/tasklist.exe ]; then
                /c/Windows/System32/tasklist.exe 2>/dev/null | grep -i "msedge.exe" >/dev/null 2>&1
                return $?
            fi
        elif [ "$IS_MAC" = true ]; then
            pgrep -f "Microsoft Edge" >/dev/null 2>&1
            return $?
        else
            pgrep -f "microsoft-edge" >/dev/null 2>&1
            return $?
        fi
        return 1
    }

    kill_edge() {
        if [ "$IS_WINDOWS" = true ] || [ "$IS_CYGWIN" = true ] || [ "$IS_MSYS" = true ]; then
            if [ -f /c/Windows/System32/taskkill.exe ]; then
                /c/Windows/System32/taskkill.exe //F //T //IM msedge.exe 2>/dev/null || true
            fi
        elif [ "$IS_MAC" = true ]; then
            pkill -f "Microsoft Edge" 2>/dev/null || true
        else
            pkill -f "microsoft-edge" 2>/dev/null || true
        fi
    }

    local ATTEMPT=0
    local MAX_ATTEMPTS=20

    while check_edge_running; do
        ATTEMPT=$((ATTEMPT + 1))
        if [ $ATTEMPT -gt $MAX_ATTEMPTS ]; then
            warn "Edge still running after $MAX_ATTEMPTS attempts!"
            read -p "Press Enter after closing Edge completely... " || true
            check_edge_running && { error "Edge still running."; return 1; }
            break
        fi
        echo -n "  Attempt $ATTEMPT: Killing Edge processes..."
        kill_edge
        echo " done."
        sleep 5
    done

    log "All Edge processes killed!"
    log "Waiting 5 seconds for file locks..."
    sleep 5

    log "Creating Python cookie extractor..."
    local PYTHON_SCRIPT="$SCRIPT_DIR/.extract_cookies.py"

    cat > "$PYTHON_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
import os, sys, sqlite3, shutil
from pathlib import Path

def try_browser(name, cookie_path):
    if not cookie_path.exists():
        return None
    tmp = Path('temp_cookies.db')
    try:
        shutil.copy2(cookie_path, tmp)
        print(f"[{name}] copied cookie DB")
    except Exception as e:
        print(f"[{name}] copy failed: {e}")
        return None
    conn = cur = None
    try:
        conn = sqlite3.connect(str(tmp))
        cur = conn.cursor()
        cur.execute("""SELECT host_key, path, is_secure, expires_utc, name, value
                       FROM cookies
                       WHERE host_key LIKE '%youtube.com%'
                       OR host_key LIKE '%google.com%'""")
        rows = cur.fetchall()
        if not rows:
            print(f"[{name}] no matching cookies")
            return None
        out = Path('cookies.txt')
        with open(out, 'w', encoding='utf-8') as f:
            f.write('# Netscape HTTP Cookie File\n')
            for host, path, secure, expires, cname, value in rows:
                try:
                    exp = int(expires / 1000000 - 11644473600) if expires > 0 else 0
                except Exception:
                    exp = 0
                sf = 'TRUE' if secure else 'FALSE'
                f.write(f"{host}\t{sf}\t{path}\t{sf}\t{exp}\t{cname}\t{value}\n")
        print(f"[{name}] extracted {len(rows)} cookies -> {out}")
        return out
    except Exception as e:
        print(f"[{name}] error: {e}")
        return None
    finally:
        if cur: cur.close()
        if conn: conn.close()
        try: tmp.unlink()
        except Exception: pass

def main():
    la = os.environ.get('LOCALAPPDATA', '')
    candidates = [
        ('edge',    Path(la) / 'Microsoft' / 'Edge' / 'User Data' / 'Default' / 'Network' / 'Cookies'),
        ('chrome',  Path(la) / 'Google' / 'Chrome' / 'User Data' / 'Default' / 'Network' / 'Cookies'),
        ('brave',   Path(la) / 'BraveSoftware' / 'Brave-Browser' / 'User Data' / 'Default' / 'Network' / 'Cookies'),
        ('vivaldi', Path(la) / 'Vivaldi' / 'User Data' / 'Default' / 'Network' / 'Cookies'),
    ]
    for name, p in candidates:
        if try_browser(name, p):
            sys.exit(0)
    print("No cookies extracted from any browser")
    sys.exit(1)

if __name__ == '__main__':
    main()
PYEOF

    chmod +x "$PYTHON_SCRIPT"
    ok "Python cookie extractor created at: $PYTHON_SCRIPT"

    local PY_BIN
    PY_BIN=$(resolve_real_binary "python") || true
    if [ -z "$PY_BIN" ]; then
        error "Python not available - cannot run cookie extractor"
        rm -f "$PYTHON_SCRIPT" 2>/dev/null
        export COOKIES_EXPORTED=false
        return 1
    fi

    cd "$SCRIPT_DIR"

    if check_edge_running; then
        warn "Edge started again! Killing it..."
        kill_edge
        sleep 3
    fi

    if "$PY_BIN" "$PYTHON_SCRIPT" 2>&1; then
        if [ -f "$SCRIPT_DIR/cookies.txt" ] && [ -s "$SCRIPT_DIR/cookies.txt" ]; then
            local n
            n=$(grep -vc '^#\|^$' "$SCRIPT_DIR/cookies.txt" 2>/dev/null || echo "0")
            ok "Python extraction succeeded! ($n cookie entries)"
            mkdir -p "$(dirname "$COOKIES_FILE")"
            cp "$SCRIPT_DIR/cookies.txt" "$COOKIES_FILE"
            ok "cookies.txt copied to: $COOKIES_FILE"
            export COOKIES_EXPORTED=true
            return 0
        fi
    fi

    warn "Python extraction failed"
    export COOKIES_EXPORTED=false
    return 1
}

# =========================================================================
# MANUAL COOKIES EXPORT
# =========================================================================
manual_cookies_export() {
    step "FALLBACK: MANUAL COOKIES EXPORT"

    echo ""
    echo "=============================================================="
    echo "  AUTOMATIC COOKIE EXTRACTION FAILED"
    echo ""
    echo "  Export cookies manually:"
    echo "    1. Install 'Get cookies.txt LOCALLY' extension"
    echo "    2. Go to YouTube.com and log in"
    echo "    3. Click the extension icon > Export cookies.txt"
    echo "    4. Save to: $COOKIES_FILE"
    echo "=============================================================="
    echo ""

    read -p "Press Enter after you've saved cookies.txt to continue... " || true

    if [ -f "$COOKIES_FILE" ] && [ -s "$COOKIES_FILE" ]; then
        ok "cookies.txt found and loaded!"
        export COOKIES_EXPORTED=true
        return 0
    else
        warn "No cookies.txt found. Continuing without cookies..."
        export COOKIES_EXPORTED=false
        return 1
    fi
}

# =========================================================================
# COOKIE EXTRACTION WITH FALLBACKS
# =========================================================================
export_cookies_with_fallbacks() {
    local BROWSER="$1"
    step "COOKIE EXTRACTION"

    if kill_edge_and_extract_cookies; then
        export COOKIES_EXPORTED=true
        return 0
    fi
    if check_existing_cookies; then
        export COOKIES_EXPORTED=true
        return 0
    fi
    if manual_cookies_export; then
        export COOKIES_EXPORTED=true
        return 0
    fi

    warn "All cookie extraction methods failed!"
    export COOKIES_EXPORTED=false
    return 1
}

# =========================================================================
# INSTALL NPM DEPENDENCIES
# =========================================================================
install_npm_dependencies() {
    step "INSTALLING NODE.JS DEPENDENCIES"

    if [ ! -d "$SERVER_DIR" ]; then
        error "Server directory not found: $SERVER_DIR"
        return 1
    fi

    if [ ! -f "$SERVER_DIR/package.json" ]; then
        warn "No package.json found in: $SERVER_DIR"
        return 1
    fi

    log "Installing npm dependencies in: $SERVER_DIR"
    cd "$SERVER_DIR" || {
        error "Cannot change to server directory: $SERVER_DIR"
        return 1
    }

    local NODE_BIN
    NODE_BIN=$(resolve_real_binary "node") || true
    local NPM_BIN
    NPM_BIN=$(resolve_real_binary "npm") || true

    if [ -z "$NODE_BIN" ]; then
        error "Real node.exe not found"
        cd "$SCRIPT_DIR" || true
        return 1
    fi
    if [ -z "$NPM_BIN" ]; then
        error "Real npm not found"
        cd "$SCRIPT_DIR" || true
        return 1
    fi

    ok "Node.js: $(safe_version "$NODE_BIN")  [$NODE_BIN]"

    local NPM_VER
    NPM_VER=$(run_native_binary "$NPM_BIN" --version 2>/dev/null | tr -d '\r\n\0' || echo "unknown")
    ok "npm: $NPM_VER  [$NPM_BIN]"

    log "Running npm install..."
    local nt="${NPM_TIMEOUT:-600}"
    RUN_TIMEOUT_SECONDS=$nt RUN_TIMEOUT_RETRIES=1 RUN_TIMEOUT_HARD_CAP=20 \
        run_with_timeout "run_native_binary \"$NPM_BIN\" install --no-audit --no-fund"

    cd "$SCRIPT_DIR" || true
}

# =========================================================================
# PATCH SERVER
# =========================================================================
patch_server() {
    step "PATCHING SERVER CONFIGURATION"

    if [ ! -f "$SERVER_JS" ]; then
        warn "Server file not found: $SERVER_JS"
        return 1
    fi

    local BACKUP_FILE="${SERVER_JS}.backup.$(date +%s)"
    cp "$SERVER_JS" "$BACKUP_FILE" 2>/dev/null
    log "Backup created: $BACKUP_FILE"

    if grep -q -- "--cookies-from-browser" "$SERVER_JS" 2>/dev/null && [ -f "$COOKIES_FILE" ]; then
        log "Patching server to use cookies file instead of browser..."
        local SAFE_COOKIES_FILE
        SAFE_COOKIES_FILE=$(echo "$COOKIES_FILE" | sed 's/[\/&]/\\&/g')
        if sed -i 's|--cookies-from-browser [^"'\'' ]*|--cookies '"$SAFE_COOKIES_FILE"'|g' "$SERVER_JS" 2>/dev/null; then
            ok "Server patched to use cookies file!"
        else
            warn "Could not patch server (sed failed)"
        fi
    else
        ok "Server configuration looks good!"
    fi
}

# =========================================================================
# COPY MODIFIED FILES
# =========================================================================
copy_modified_files() {
    step "APPLYING ENHANCEMENTS"
    if [ -n "$SERVER_DIR" ]; then
        mkdir -p "$SERVER_DIR/downloads" 2>/dev/null
        ok "Downloads directory ready: $SERVER_DIR/downloads"
    fi
}

# =========================================================================
# START SERVER
# =========================================================================
start_server() {
    step "STARTING SERVER"

    if [ ! -f "$SERVER_JS" ]; then
        error "Server file not found: $SERVER_JS"
        return 1
    fi

    if [ ! -d "$SERVER_DIR" ]; then
        error "Server directory not found: $SERVER_DIR"
        return 1
    fi

    local NODE_BIN
    NODE_BIN=$(resolve_real_binary "node") || true
    if [ -z "$NODE_BIN" ]; then
        error "Real node.exe not found - cannot start server"
        return 1
    fi
    log "Using node: $NODE_BIN"

    if [ "$IS_WINDOWS" = true ]; then
        if command -v netstat >/dev/null 2>&1; then
            local PORT_PID
            PORT_PID=$(netstat -ano 2>/dev/null | grep ":$PORT " | grep LISTENING | awk '{print $5}' | head -1 | tr -d '\r')
            if [ -n "$PORT_PID" ] && [ "$PORT_PID" != "0" ]; then
                log "Killing existing process on port $PORT (PID: $PORT_PID)"
                taskkill //F //PID "$PORT_PID" 2>/dev/null || true
                sleep 2
            fi
        fi
        taskkill //IM node.exe //F 2>/dev/null && {
            log "Killed existing node.exe processes"
            sleep 2
        } || log "No existing node.exe processes"
    else
        if command -v lsof >/dev/null 2>&1; then
            local EXISTING_PID
            EXISTING_PID=$(lsof -ti :$PORT 2>/dev/null)
            if [ -n "$EXISTING_PID" ]; then
                log "Killing existing process on port $PORT (PID: $EXISTING_PID)"
                kill -9 "$EXISTING_PID" 2>/dev/null || true
                sleep 1
            fi
        fi
    fi

    log "Port $PORT is now available"

    if [ "$IS_WINDOWS" = true ]; then
        local _win_home="${USERPROFILE:-${HOME}}"
        export DOWNLOADS_DIR="$_win_home/Downloads/YouTube-Downloader"
    else
        export DOWNLOADS_DIR="$HOME/Downloads/YouTube-Downloader"
    fi
    log "DOWNLOADS_DIR=$DOWNLOADS_DIR"

    local FF_BIN
    FF_BIN=$(resolve_real_binary "ffmpeg") || true
    if [ -n "$FF_BIN" ]; then
        local FF_DIR
        FF_DIR="$(dirname "$FF_BIN")"
        export PATH="$FF_DIR:$PATH"
        log "Added ffmpeg dir to PATH: $FF_DIR"
    fi

    cd "$SERVER_DIR" || {
        error "Failed to change to server directory: $SERVER_DIR"
        return 1
    }

    if [ ! -d "node_modules/express" ]; then
        warn "'express' module missing. Running npm install..."
        local NPM_BIN
        NPM_BIN=$(resolve_real_binary "npm") || true
        if [ -n "$NPM_BIN" ]; then
            local nt="${NPM_TIMEOUT:-600}"
            RUN_TIMEOUT_SECONDS=$nt RUN_TIMEOUT_RETRIES=1 RUN_TIMEOUT_HARD_CAP=20 \
                run_with_timeout "run_native_binary \"$NPM_BIN\" install --no-audit --no-fund"
        fi
    fi

    DOWNLOADS_DIR="$DOWNLOADS_DIR" "$NODE_BIN" "$SERVER_JS" > "$SCRIPT_DIR/server.log" 2>&1 &
    SERVER_PID=$!

    local _sp_winpid=0
    if command -v ps >/dev/null 2>&1; then
        _sp_winpid=$(ps -W 2>/dev/null | awk -v pid=$SERVER_PID '$1==pid {print $4; exit}')
    fi
    _sp_winpid=${_sp_winpid:-0}
    if [ "$_sp_winpid" -gt 0 ] 2>/dev/null; then
        echo "$_sp_winpid" >> "$SCRIPT_DIR/.1sh.pids"
        log "Recorded server WinPID $_sp_winpid for cleanup"
    fi

    log "Waiting for port $PORT to accept connections..."
    local waited=0
    local port_up=false
    while [ $waited -lt 15 ]; do
        sleep 1
        waited=$((waited + 1))
        if command -v netstat >/dev/null 2>&1; then
            if netstat -ano 2>/dev/null | grep -q ":$PORT .*LISTENING"; then
                port_up=true
                break
            fi
        else
            [ $waited -ge 3 ] && { port_up=true; break; }
        fi
    done

    if kill -0 $SERVER_PID 2>/dev/null; then
        if [ "$port_up" = true ]; then
            ok "Server started successfully! (PID: $SERVER_PID)"
            log "Server running at: $URL"
        else
            warn "Server process alive but port $PORT not yet listening (waited ${waited}s)"
            log "Server running at: $URL (may not be ready yet)"
        fi
        log "Server startup log:"
        tail -10 "$SCRIPT_DIR/server.log" 2>/dev/null | while read line; do
            log "  $line"
        done
        return 0
    else
        error "Server failed to start!"
        error "Check log: $SCRIPT_DIR/server.log"
        error "Last 20 lines:"
        tail -20 "$SCRIPT_DIR/server.log" 2>/dev/null | while read line; do
            error "  $line"
        done
        return 1
    fi
}

# =========================================================================
# OPEN BROWSER - explorer.exe method (works reliably from Git Bash)
# =========================================================================
open_browser() {
    step "OPENING BROWSER"
    log "Opening browser at: $URL"

    if [ "$IS_WINDOWS" = true ] || [ "$IS_CYGWIN" = true ] || [ "$IS_MSYS" = true ]; then
        # explorer.exe launches the URL through the Windows shell, which
        # resolves to the user's default browser automatically. It opens a
        # new tab if the browser is already running, or launches it fresh.
        # This is the only method that works reliably from Git Bash on Win11.
        if [ -f /c/Windows/explorer.exe ]; then
            MSYS_NO_PATHCONV=1 /c/Windows/explorer.exe "$URL" < /dev/null > /dev/null 2>&1
            sleep 2
            ok "Browser opened (explorer.exe): $URL"
            return 0
        fi

        # Fallback: explorer via PATH
        if command -v explorer >/dev/null 2>&1; then
            MSYS_NO_PATHCONV=1 explorer "$URL" < /dev/null > /dev/null 2>&1
            sleep 2
            ok "Browser opened (explorer): $URL"
            return 0
        fi

        warn "Could not launch explorer.exe"
        warn "Please open manually: $URL"
        return 1
    elif [ "$IS_MAC" = true ]; then
        open "$URL" 2>/dev/null && ok "Browser opened" || warn "Could not open browser"
    else
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$URL" 2>/dev/null && ok "Browser opened" || warn "Could not open browser"
        elif command -v firefox >/dev/null 2>&1; then
            firefox "$URL" 2>/dev/null &
            ok "Browser opened (firefox)"
        else
            warn "Please open manually: $URL"
        fi
    fi
}

# =========================================================================
# KEEP TERMINAL OPEN
# =========================================================================
keep_terminal_open() {
    echo ""
    echo "+==============================================================+"
    echo "|                                                              |"
    echo "|   SERVER IS RUNNING - KEEP THIS WINDOW OPEN                  |"
    echo "|                                                              |"
    echo "|   URL: ${BOLD}$URL${NC}"
    echo "|   Downloads: ${BOLD}${SERVER_DIR:-unknown}/downloads${NC}"
    echo "|                                                              |"
    echo "|   Press Ctrl+C to stop the server                           |"
    echo "|                                                              |"
    echo "+==============================================================+"
    echo ""

    while true; do
        sleep 3600
    done
}

# =========================================================================
# MAIN
# =========================================================================
main() {
    echo ""
    echo "+==============================================================+"
    echo "|                                                              |"
    echo "|   YOUTUBE DOWNLOADER - COMPLETE SETUP                        |"
    echo "|                                                              |"
    echo "|   Version 12.1 (explorer.exe browser launch)                 |"
    echo "|                                                              |"
    echo "+==============================================================+"
    echo ""

    log "Starting YouTube Downloader setup..."
    log "Script directory: $SCRIPT_DIR"
    log "Current directory: $(pwd)"
    log "Date: $(date)"

    cd "$SCRIPT_DIR" || {
        error "Failed to change to script directory: $SCRIPT_DIR"
        return 1
    }
    log "Now in directory: $(pwd)"
    echo ""

    add_known_tool_dirs
    refresh_windows_path
    install_missing_tools

    detect_repo_structure
    install_ytdl
    setup_ffmpeg

    local BROWSER
    BROWSER=$(detect_browser) || BROWSER="edge"
    log "Detected browser: $BROWSER"
    test_cookies "$BROWSER"
    export_cookies_with_fallbacks "$BROWSER"

    install_npm_dependencies
    patch_server
    copy_modified_files

    if start_server; then
        open_browser
        echo ""
        echo "+==============================================================+"
        echo "|                                                              |"
        echo "|                   SETUP COMPLETE                             |"
        echo "|                                                              |"
        echo "|  Server: ${BOLD}$URL${NC}"
        echo "|  Downloads: ${BOLD}${SERVER_DIR:-unknown}/downloads${NC}"
        echo "|  Cookies: ${BOLD}${COOKIES_EXPORTED:-browser fallback}${NC}"
        echo "|                                                              |"
        echo "+==============================================================+"
        echo ""
        keep_terminal_open
    else
        error "Server failed to start. See log above."
        return 1
    fi
}

main "$@"
REM BASH_SCRIPT_END