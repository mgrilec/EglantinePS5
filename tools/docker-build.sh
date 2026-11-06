#!/usr/bin/env bash
# Run the release build in a container with write access only to this isolated worktree and required mounts.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
projects=$(dirname "$root")
name=${root##*/}
image=eglantineps5-build:ubuntu-26.04

# The build creates these checkout paths when dependencies are absent. The worktree is
# writable in the container, so seed missing sibling git checkouts on the host at their pins.
while IFS=: read -r dep checkout; do
    destination="$projects/$checkout"
    if [[ ! -e $destination ]]; then
        read -r url commit < <(python3 - "$root/tools/deps.json" "$dep" <<'PY'
import json, sys
item = next(x for x in json.load(open(sys.argv[1]))["items"] if x["name"] == sys.argv[2])
print(item["url"], item["commit"])
PY
)
        git clone --no-checkout "$url" "$destination"
        git -C "$destination" fetch origin "$commit"
        git -C "$destination" checkout --detach FETCH_HEAD
    fi
done <<'EOF'
boilerplate:ps5-native-app-boilerplate
ps5-vulkan-tools:mihawk-vulkan-review
ps5-mesa:mihawk-mesa-review
ps5-payload-sdk-fork:mihawk-sdk-review
EOF

# Keep mutable build inputs and outputs on the host across container runs.
mkdir -p "$root/.deps" "$root/.local" "$root/build" "$root/dist" \
    "$root/Eglantine" "$projects/.eglantineps5-docker-cache"

# Build the image when it does not exist. Rebuild it explicitly with `docker build` after
# changing the package list or Dockerfile.
if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker build -f "$root/docker/Dockerfile" -t "$image" "$root"
fi

# A linked worktree's .git file points into the common repository's .git/worktrees directory.
# Expose that metadata writable for submodule initialization and ordinary git operations.
common_git=$(git -C "$root" rev-parse --git-common-dir)
if [[ $common_git != /* ]]; then common_git="$root/$common_git"; fi
common_git=$(cd "$common_git" && pwd)
common_rel=${common_git#"$projects"/}
[[ $common_rel != "$common_git" ]] || { echo "Git metadata is outside $projects: $common_git" >&2; exit 1; }

args=(docker run --rm --user "$(id -u):$(id -g)"
    --mount "type=bind,src=$root,dst=$root"
    --mount "type=bind,src=$common_git,dst=$common_git"
    --mount "type=bind,src=$projects/ps5-native-app-boilerplate,dst=$projects/ps5-native-app-boilerplate"
    --mount "type=bind,src=$projects/mihawk-vulkan-review,dst=$projects/mihawk-vulkan-review"
    --mount "type=bind,src=$projects/mihawk-mesa-review,dst=$projects/mihawk-mesa-review"
    --mount "type=bind,src=$projects/mihawk-sdk-review,dst=$projects/mihawk-sdk-review"
    --mount "type=bind,src=$projects/.eglantineps5-docker-cache,dst=$projects/.eglantineps5-docker-cache"
    --env HOME=$projects/.eglantineps5-docker-cache
    --env XDG_CACHE_HOME=$projects/.eglantineps5-docker-cache/.cache
    --env "JOBS=${JOBS:-3}" --env "RADV_BUILD_JOBS=${RADV_BUILD_JOBS:-3}"
    --workdir "$root" "$image")

if (($# == 0)); then
    set -- make release
fi
exec "${args[@]}" "$@"
