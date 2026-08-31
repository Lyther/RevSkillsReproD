# shellcheck shell=bash
# remote-dir.sh — source only.
# Allowlist REMOTE_DIR / DEPLOY_HOST before interpolating them into ssh.

remote_dir_ok() {
    local path="${1:-}"
    [[ -n "${path}" ]] || return 1
    [[ "${path}" != *..* ]] || return 1
    [[ "${path}" =~ ^[~a-zA-Z0-9._/-]+$ ]]
}

remote_host_ok() {
    local host="${1:-}"
    [[ -n "${host}" ]] || return 1
    [[ "${host}" =~ ^[A-Za-z0-9._-]+$ ]]
}

remote_dir_quote() {
    printf '%q' "$1"
}
