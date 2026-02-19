#!/bin/sh
set -euo pipefail

RES_SRC="${SRCROOT}/VideoMinifier/Resources"
RES_DST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

for dir in "$RES_SRC"/*.lproj; do
  if [ -d "$dir" ]; then
    base="$(basename "$dir")"
    dst="$RES_DST/$base"
    mkdir -p "$dst"
    if [ -f "$dir/Localizable.strings" ]; then
      cp -f "$dir/Localizable.strings" "$dst/"
    fi
  fi
done

FFMPEG_SRC="$RES_SRC/bin/ffmpeg"
FFPROBE_SRC="$RES_SRC/bin/ffprobe"
if [ ! -x "$FFMPEG_SRC" ] && [ -x "/opt/homebrew/bin/ffmpeg" ]; then
  FFMPEG_SRC="/opt/homebrew/bin/ffmpeg"
fi
if [ ! -x "$FFPROBE_SRC" ] && [ -x "/opt/homebrew/bin/ffprobe" ]; then
  FFPROBE_SRC="/opt/homebrew/bin/ffprobe"
fi

if [ -x "$FFMPEG_SRC" ]; then
  cp -fL "$FFMPEG_SRC" "$RES_DST/ffmpeg"
  chmod 755 "$RES_DST/ffmpeg"
fi
if [ -x "$FFPROBE_SRC" ]; then
  cp -fL "$FFPROBE_SRC" "$RES_DST/ffprobe"
  chmod 755 "$RES_DST/ffprobe"
fi

LIB_DIR="$RES_DST/lib"
mkdir -p "$LIB_DIR"

SEARCH_DIRS=""
add_search_dir() {
  d="$1"
  [ -d "$d" ] || return 0
  case " $SEARCH_DIRS " in
    *" $d "*) ;;
    *) SEARCH_DIRS="$SEARCH_DIRS $d" ;;
  esac
}

add_search_dir "$(dirname "$FFMPEG_SRC")"
add_search_dir "$(dirname "$FFPROBE_SRC")"
add_search_dir "/opt/homebrew/lib"

for d in /opt/homebrew/opt/*/lib; do
  add_search_dir "$d"
done
for d in /opt/homebrew/Cellar/ffmpeg/*/lib; do
  add_search_dir "$d"
done

resolve_dep() {
  dep="$1"
  from="$2"

  case "$dep" in
    /System/*|/usr/lib/*)
      return 1
      ;;
  esac

  if [ -e "$dep" ]; then
    echo "$dep"
    return 0
  fi

  base="$(basename "$dep")"
  from_dir="$(dirname "$from")"

  if [ -e "$from_dir/$base" ]; then
    echo "$from_dir/$base"
    return 0
  fi

  for d in $SEARCH_DIRS; do
    if [ -e "$d/$base" ]; then
      echo "$d/$base"
      return 0
    fi
  done

  return 1
}

collect_deps() {
  target="$1"
  otool -L "$target" | tail -n +2 | awk '{print $1}' | while IFS= read -r dep; do
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
    esac

    src_dep="$(resolve_dep "$dep" "$target" || true)"
    [ -n "$src_dep" ] || continue

    base="$(basename "$src_dep")"
    dst="$LIB_DIR/$base"
    if [ ! -f "$dst" ]; then
      cp -fL "$src_dep" "$dst"
      chmod 755 "$dst"
      collect_deps "$dst"
    fi
  done
}

patch_links() {
  target="$1"
  mode="$2"

  otool -L "$target" | tail -n +2 | awk '{print $1}' | while IFS= read -r dep; do
    case "$dep" in
      /System/*|/usr/lib/*) continue ;;
    esac

    base="$(basename "$dep")"
    if [ ! -f "$LIB_DIR/$base" ]; then
      continue
    fi

    if [ "$mode" = "exe" ]; then
      new_ref="@loader_path/lib/$base"
    else
      new_ref="@loader_path/$base"
    fi

    install_name_tool -change "$dep" "$new_ref" "$target" 2>/dev/null || true
  done
}

if [ -x "$RES_DST/ffmpeg" ]; then
  collect_deps "$RES_DST/ffmpeg"
fi
if [ -x "$RES_DST/ffprobe" ]; then
  collect_deps "$RES_DST/ffprobe"
fi

for lib in "$LIB_DIR"/*.dylib; do
  [ -f "$lib" ] || continue
  base="$(basename "$lib")"
  install_name_tool -id "@loader_path/$base" "$lib" 2>/dev/null || true
done

if [ -x "$RES_DST/ffmpeg" ]; then
  patch_links "$RES_DST/ffmpeg" exe
fi
if [ -x "$RES_DST/ffprobe" ]; then
  patch_links "$RES_DST/ffprobe" exe
fi
for lib in "$LIB_DIR"/*.dylib; do
  [ -f "$lib" ] || continue
  patch_links "$lib" lib
done

for lib in "$LIB_DIR"/*.dylib; do
  [ -f "$lib" ] || continue
  codesign --force --sign - "$lib" >/dev/null 2>&1 || true
done
if [ -x "$RES_DST/ffmpeg" ]; then
  codesign --force --sign - "$RES_DST/ffmpeg" >/dev/null 2>&1 || true
fi
if [ -x "$RES_DST/ffprobe" ]; then
  codesign --force --sign - "$RES_DST/ffprobe" >/dev/null 2>&1 || true
fi
