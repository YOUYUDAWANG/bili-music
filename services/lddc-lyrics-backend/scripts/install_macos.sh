#!/bin/zsh

set -euo pipefail

label="com.youyudawang.BiliMusic.lddc-lyrics"
deployment_root="${1:-${HOME}/Library/Application Support/BiliMusic/LDDCLyricsBackend}"
host_address="${2:-127.0.0.1}"
port="${3:-8788}"
launch_agents_directory="${HOME}/Library/LaunchAgents"
logs_directory="${HOME}/Library/Logs/BiliMusic"
plist_path="${launch_agents_directory}/${label}.plist"
temporary_plist="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/bilimusic-lddc.XXXXXX.plist")"
uid="$(/usr/bin/id -u)"

cleanup() {
    /bin/rm -f "${temporary_plist}"
}
trap cleanup EXIT

if [[ ! -x "${deployment_root}/scripts/start_macos.sh" ]]; then
    print -u2 -- "Missing macOS start script"
    exit 1
fi

if [[ ! -r "${deployment_root}/server-token.txt" ]]; then
    print -u2 -- "Missing LDDC backend token file"
    exit 1
fi

/bin/mkdir -p "${launch_agents_directory}" "${logs_directory}"
/bin/chmod 700 "${deployment_root}/scripts/start_macos.sh"
/bin/chmod 600 "${deployment_root}/server-token.txt"

/usr/bin/plutil -create xml1 "${temporary_plist}"
/usr/bin/plutil -insert Label -string "${label}" "${temporary_plist}"
/usr/bin/plutil -insert ProgramArguments -xml '<array/>' "${temporary_plist}"
/usr/bin/plutil -insert ProgramArguments.0 -string /bin/zsh "${temporary_plist}"
/usr/bin/plutil -insert ProgramArguments.1 -string "${deployment_root}/scripts/start_macos.sh" "${temporary_plist}"
/usr/bin/plutil -insert WorkingDirectory -string "${deployment_root}" "${temporary_plist}"
/usr/bin/plutil -insert EnvironmentVariables -xml '<dict/>' "${temporary_plist}"
/usr/bin/plutil -insert EnvironmentVariables.BILIMUSIC_LDDC_ROOT -string "${deployment_root}" "${temporary_plist}"
/usr/bin/plutil -insert EnvironmentVariables.LDDC_BACKEND_HOST -string "${host_address}" "${temporary_plist}"
/usr/bin/plutil -insert EnvironmentVariables.LDDC_BACKEND_PORT -string "${port}" "${temporary_plist}"
/usr/bin/plutil -insert EnvironmentVariables.LDDC_BACKEND_TIMEOUT_SECONDS -string 18 "${temporary_plist}"
/usr/bin/plutil -insert RunAtLoad -bool true "${temporary_plist}"
/usr/bin/plutil -insert KeepAlive -xml '<dict><key>SuccessfulExit</key><false/></dict>' "${temporary_plist}"
/usr/bin/plutil -insert ThrottleInterval -integer 30 "${temporary_plist}"
/usr/bin/plutil -insert StandardOutPath -string "${logs_directory}/lddc-lyrics.out.log" "${temporary_plist}"
/usr/bin/plutil -insert StandardErrorPath -string "${logs_directory}/lddc-lyrics.err.log" "${temporary_plist}"

/bin/mv "${temporary_plist}" "${plist_path}"
/bin/chmod 600 "${plist_path}"

/bin/launchctl bootout "gui/${uid}/${label}" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/${uid}" "${plist_path}"
/bin/launchctl kickstart -k "gui/${uid}/${label}"

print -- "LDDC lyrics LaunchAgent installed on ${host_address}:${port}"
