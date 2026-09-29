#!/usr/bin/env bash
# Downloads the Blender open movies (CC BY) used by `make benchmark-footage` into .footage/ (~480 MB).
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)/.footage"
mkdir -p "$DIR"

fetch() {
  local name="$1" url="$2" sha="$3"
  if [[ -f "$DIR/$name" ]] && echo "$sha  $DIR/$name" | shasum -a 256 -c --status; then
    echo "✓ $name"
    return
  fi
  curl -fL --retry 3 -o "$DIR/$name" "$url"
  echo "$sha  $DIR/$name" | shasum -a 256 -c
}

fetch sintel_trailer.mp4 https://download.blender.org/durian/trailer/sintel_trailer-720p.mp4 \
  cb0fe73fc0a7d543459996c0cdab730997e6eac1013d3ede18796f777cb7f273
fetch bbb_trailer.mov https://download.blender.org/peach/trailer/trailer_720p.mov \
  cb7be60feb4fd4ff5b006e35e824201a48361b7ebc2f2bbcaf3351912035561a
fetch tos.mov https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov \
  efa9062d9cdb7a338e40ad530dfdf234806743f29ae6a1a136b97ece4e588e8f
fetch ed.mov https://download.blender.org/ED/elephantsdream-480-h264-st-aac.mov \
  a7dbacae5fa2bc345dbd7b10588575f3e2bba36012e9a93df5346467053b0634
