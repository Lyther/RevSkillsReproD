# shellcheck shell=bash
# bytellm-key.sh — source only.
# Load a ByteLLM client or .env KEY=value line without printing it.

bytellm_default_key_file() {
    # Client key only. Sibling ByteLLM/.env holds upstream registry keys
    # (line 11 = Qwen3-max pool) and must not be sent as Bearer.
    if [[ -n "${BYTELLM_KEY_FILE:-}" ]]; then
        printf '%s' "${BYTELLM_KEY_FILE}"
        return 0
    fi
    printf '%s' "${HOME}/.ssh/bytellm"
}

# Prints the secret to stdout. Caller must capture it; do not log.
bytellm_read_key() {
    local file="${1:-}"
    local line_no="${2:-11}"
    local raw name
    [[ -f "${file}" ]] || return 1
    [[ "${line_no}" =~ ^[1-9][0-9]*$ ]] || return 1
    raw="$(sed -n "${line_no}p" "${file}" | tr -d '\r\n')"
    [[ -n "${raw}" ]] || return 1
    [[ "${raw}" != \#* ]] || return 1
    if [[ "${raw}" == *=* ]]; then
        name="${raw%%=*}"
        if [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            printf '%s' "${raw#*=}"
            return 0
        fi
    fi
    printf '%s' "${raw}"
}
