
#!/usr/bin/env bash

set -uo pipefail

if ! command -v podman >/dev/null 2>&1; then
    printf 'ERROR: podman is not installed\n' >&2
    exit 1
fi

mapfile -t containers < <(
    podman ps --format '{{.Names}}' | sort
)

if (( ${#containers[@]} == 0 )); then
    printf 'No running containers found\n'
    exit 0
fi

success=0
failed=0
skipped=0

for container in "${containers[@]}"; do
    printf '\n========================================\n'
    printf 'Container: %s\n' "$container"
    printf '========================================\n'

    os_id=$(podman exec "$container" \
        sh -c '. /etc/os-release; printf "%s" "$ID"' \
        2>/dev/null) || os_id="unknown"

    os_like=$(podman exec "$container" \
        sh -c '. /etc/os-release; printf "%s" "${ID_LIKE:-}"' \
        2>/dev/null) || os_like=""

    printf 'Distribution: %s\n' "$os_id"

    case "$os_id" in
        fedora|rhel|rocky|almalinux|centos|ol)
            cmd='
                if command -v dnf5 >/dev/null 2>&1; then
                    dnf5 upgrade --refresh -y
                elif command -v dnf >/dev/null 2>&1; then
                    dnf upgrade --refresh -y
                else
                    exit 127
                fi
            '
            ;;
        opensuse-tumbleweed|opensuse-slowroll)
            cmd='zypper --non-interactive refresh &&
                 zypper --non-interactive dup'
            ;;
        opensuse-leap|sles)
            cmd='zypper --non-interactive refresh &&
                 zypper --non-interactive update'
            ;;
        debian|ubuntu)
            cmd='apt-get update &&
                 DEBIAN_FRONTEND=noninteractive apt-get upgrade -y'
            ;;
        alpine)
            cmd='apk update && apk upgrade'
            ;;
        *)
            case " $os_like " in
                *" rhel "*|*" fedora "*)
                    cmd='dnf upgrade --refresh -y'
                    ;;
                *)
                    printf 'SKIPPED: unsupported distribution\n'
                    ((skipped+=1))
                    continue
                    ;;
            esac
            ;;
    esac

    if podman exec --user 0 "$container" \
        sh -c "$cmd"; then
        printf 'SUCCESS: %s\n' "$container"
        ((success+=1))
    else
        printf 'FAILED: %s\n' "$container" >&2
        ((failed+=1))
    fi
done

printf '\n========================================\n'
printf 'UPDATE SUMMARY\n'
printf '========================================\n'
printf 'Successful: %d\n' "$success"
printf 'Failed:     %d\n' "$failed"
printf 'Skipped:    %d\n' "$skipped"
printf 'Total:      %d\n' "${#containers[@]}"

if (( failed > 0 )); then
    exit 1
fi

exit 0
