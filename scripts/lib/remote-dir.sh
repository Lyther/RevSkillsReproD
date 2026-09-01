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

# Expand a leading ~ to the given absolute home. Does not expand ~user.
remote_dir_expand_home() {
    local path="${1:-}"
    local home="${2:-}"
    [[ -n "${path}" && -n "${home}" ]] || return 1
    [[ "${home}" == /* ]] || return 1
    # Compare against a literal ~/ prefix. Tilde must not expand to $HOME here.
    # shellcheck disable=SC2088
    if [[ "${path}" == "~" ]]; then
        printf '%s\n' "${home}"
    elif [[ "${path}" == "~/"* ]]; then
        printf '%s/%s\n' "${home}" "${path#"~/"}"
    else
        printf '%s\n' "${path}"
    fi
}

remote_dir_quote() {
    printf '%q' "$1"
}
