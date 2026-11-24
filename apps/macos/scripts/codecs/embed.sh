#!/bin/bash
set -euo pipefail
codec_dir="$SRCROOT/scripts/codecs"
python3 "$codec_dir/build.py"
python3 "$codec_dir/build_jxl.py"
tools_dir="$SRCROOT/build/MediaCodecs/tools"
helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/Media"
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$helpers" "$resources"
for program in ffmpeg ffprobe cjxl djxl; do
    install -m 755 "$tools_dir/$program" "$helpers/$program"
    if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
        /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$helpers/$program"
    fi
done
install -m 644 "$tools_dir/Codec Sources.zip" "$resources/Codec Sources.zip"
install -m 644 "$tools_dir/JPEG XL Sources.zip" "$resources/JPEG XL Sources.zip"
