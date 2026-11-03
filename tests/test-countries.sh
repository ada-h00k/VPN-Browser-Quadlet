#!/usr/bin/env bash
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/countries.sh
source "$ROOT/lib/countries.sh"

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s (expected <%s>, got <%s>)\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq 'Switzerland' "$(normalize_country_list ch)" 'CH alias is repaired'
assert_eq 'Switzerland' "$(normalize_country_list CH)" 'uppercase CH alias is repaired'
assert_eq 'Switzerland' "$(normalize_country_list switzerland)" 'country names are case-normalized'
assert_eq 'Germany,Netherlands' "$(normalize_country_list 'de, NL')" 'comma-separated aliases are normalized'
assert_eq 'Czech Republic' "$(normalize_country_list cz)" 'multi-word country is mapped'

if normalize_country_list 'not-a-country' >/dev/null 2>&1; then
    printf 'FAIL: unsupported country must be rejected\n' >&2
    exit 1
fi

printf 'All country-normalization tests passed.\n'
