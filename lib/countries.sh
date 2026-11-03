# Country-name normalization for Gluetun's Mullvad provider.
# Copyright (C) 2026 vpn-browser-quadlet contributors
# SPDX-License-Identifier: AGPL-3.0-only

normalize_country_token() {
    local raw="$1" key
    key="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
    case "$key" in
        al|albania) printf 'Albania' ;;
        ar|argentina) printf 'Argentina' ;;
        au|australia) printf 'Australia' ;;
        at|austria) printf 'Austria' ;;
        be|belgium) printf 'Belgium' ;;
        br|brazil) printf 'Brazil' ;;
        bg|bulgaria) printf 'Bulgaria' ;;
        ca|canada) printf 'Canada' ;;
        cl|chile) printf 'Chile' ;;
        co|colombia) printf 'Colombia' ;;
        hr|croatia) printf 'Croatia' ;;
        cy|cyprus) printf 'Cyprus' ;;
        cz|"czech republic") printf 'Czech Republic' ;;
        dk|denmark) printf 'Denmark' ;;
        ee|estonia) printf 'Estonia' ;;
        fi|finland) printf 'Finland' ;;
        fr|france) printf 'France' ;;
        de|germany) printf 'Germany' ;;
        gr|greece) printf 'Greece' ;;
        hk|"hong kong") printf 'Hong Kong' ;;
        hu|hungary) printf 'Hungary' ;;
        id|indonesia) printf 'Indonesia' ;;
        ie|ireland) printf 'Ireland' ;;
        il|israel) printf 'Israel' ;;
        it|italy) printf 'Italy' ;;
        jp|japan) printf 'Japan' ;;
        my|malaysia) printf 'Malaysia' ;;
        mx|mexico) printf 'Mexico' ;;
        nl|netherlands) printf 'Netherlands' ;;
        nz|"new zealand") printf 'New Zealand' ;;
        ng|nigeria) printf 'Nigeria' ;;
        no|norway) printf 'Norway' ;;
        pe|peru) printf 'Peru' ;;
        ph|philippines) printf 'Philippines' ;;
        pl|poland) printf 'Poland' ;;
        pt|portugal) printf 'Portugal' ;;
        ro|romania) printf 'Romania' ;;
        rs|serbia) printf 'Serbia' ;;
        sg|singapore) printf 'Singapore' ;;
        sk|slovakia) printf 'Slovakia' ;;
        si|slovenia) printf 'Slovenia' ;;
        za|"south africa") printf 'South Africa' ;;
        es|spain) printf 'Spain' ;;
        se|sweden) printf 'Sweden' ;;
        ch|switzerland) printf 'Switzerland' ;;
        th|thailand) printf 'Thailand' ;;
        tr|turkey) printf 'Turkey' ;;
        gb|uk|"united kingdom") printf 'UK' ;;
        us|usa|"united states") printf 'USA' ;;
        ua|ukraine) printf 'Ukraine' ;;
        *) return 1 ;;
    esac
}

normalize_country_list() {
    local input="$1" token canonical result=""
    local -a tokens
    IFS=',' read -r -a tokens <<< "$input"
    for token in "${tokens[@]}"; do
        [[ -n "${token//[[:space:]]/}" ]] || continue
        canonical="$(normalize_country_token "$token")" || return 1
        [[ -z "$result" ]] || result+="," 
        result+="$canonical"
    done
    [[ -n "$result" ]] || return 1
    printf '%s' "$result"
}
