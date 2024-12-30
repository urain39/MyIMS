#!/bin/sh

##################################################################################
# Created By: urain39@qq.com
# Source URL: https://github.com/urain39/myims
# Last Updated: 2024-09-23 04:34:33 +0800
# Required Commands: coreutils, gawk / busybox awk, imagemagick, unzip, zip
##################################################################################

# Set your TMPDIR to change the parent directory of extract_dir and temp_dir

kill_children() {
  local pid=
  local pids=
  for pid in $(pgrep -P "$1"); do
    kill_children "${pid}"
    {
      kill -TERM "${pid}" 2> /dev/null
      sleep 0.22
      kill -KILL "${pid}" 2> /dev/null
    } &
    pids="${pids}${pids:+" "}$!"
  done

  # We cannot use the wait command directly, because it will wait parent's unfinished background jobs
  for pid in ${pids}; do
    wait "${pid}"
  done
}

trap 'kill_children "$$"; exit 1' INT TERM

image_resize() {
  local width=
  local height=
  local quality=
  local alpha=
  local type_=
  local gray_scale="${GRAY_SCALE:-"16"}"
  local gray_threshold="${GRAY_THRESHOLD:-"0.16"}"
  IFS=';' read -r width height quality alpha type_ << EOF
$( magick "${file_}" \
  -quiet \
  -format '%w;%h;%Q;%A;' \
  -write "info:" \
  -sample "%[fx: w / ${gray_scale}]x%[fx: h / ${gray_scale}]" \
  -channel "RB" \
  -fx "abs(p - g) < ${gray_threshold} ? g : p" \
  -format '%[type];' "info:" 2> /dev/null )
EOF

  if [ "${width}" = "" ] \
    || [ "${height}" = "" ] \
    || [ "${quality}" = "" ]; then
    printf '\r\033[KNote: "%s" corrupted. Copy only.\n' "${file_}"
    cp -- "${file_}" "${temp_dir}/!${file_##*/}" || return 1

    # Increase progress bar
    echo "0" >&9

    return 0
  fi

  # Quiet
  convert_args='\
-quiet'

  if [ "${alpha}" != "Undefined" ]; then
    printf '\r\033[KNote: "%s" has an alpha channel. Save it separately.\n' "${file_}"

    # Alpha channel fixes
    convert_args="${convert_args}"' \
\( \
  +clone \
  -alpha "extract" \
  -write "mpr:alpha" \
  -negate \
  -background "black" \
  -alpha "shape" \
\) \
-compose "src-over" \
-composite \
\( \
  "mpr:alpha" \
  -quality "${quality}" \
  -"${resize_method}" "${resize_}" \
  -write "${temp_dir}/@${file__}" \
\) \
-compose "dst" \
-composite'

    # Reprint progress bar
    echo "2147483647" >&9
  fi

  # Compressions
  convert_args="${convert_args}"' \
-colorspace "${colorspace}" \
-interlace "none" \
-quality "${quality}"'

  local resize_method="${RESIZE_METHOD:-"resize"}"

  case "${resize_method}" in
    [Ss][Cc][Aa][Ll][Ee])
      resize_method="scale"
      ;;
    [Ss][Aa][Mm][Pp][Ll][Ee])
      resize_method="sample"
      ;;
    [Tt][Hh][Uu][Mm][Bb][Nn][Aa][Ii][Ll])
      resize_method="thumbnail"
      ;;
    *)
      resize_method="resize"
      ;;
  esac

  local short_edge="${SHORT_EDGE:-"2160"}"

  # Resize rules:
  #   If width < height, width=$((short_edge))px
  #   If width = height, width=$((short_edge * 4 / 3))px
  #   If width > height, height=$((short_edge))px
  local short_before="${width}"
  local resize_="${short_edge}x>"
  if [ "${width}" -eq "${height}" ]; then
    short_edge="$((short_edge * 4 / 3))"
    resize_="${short_edge}x>"
  elif [ "${width}" -gt "${height}" ]; then
    short_before="${height}"
    # shellcheck disable=SC2034
    resize_="x${short_edge}>"
  fi

  # Resizing
  convert_args="${convert_args}"' \
-"${resize_method}" "${resize_}"'

  # Sampling
  convert_args="${convert_args}"' \
-sampling-factor "2x2,1x1,1x1"'

  # Defaults
  local colorspace="YCbCr"
  local depth="8"
  local format="jpg"
  local dither_pattern="h6x6a"

  # Decrease quality only for very high-quality images
  if [ "${quality}" -gt "92" ]; then
    quality="0"  # 0 means default (almost high-quality)
  fi

  # Global post effect
  local postfx="${GLOBAL_POSTFX:-}"

  # Monochrome optimization
  case "${type_}" in
    Bilevel|Grayscale|GrayscaleAlpha)
      local short_after="$((short_before < short_edge ? short_before : short_edge))"
      if [ "${short_after}" -le "2160" ]; then
        # shellcheck disable=SC2034
        dither_pattern="o3x3"
      fi

      convert_args="${convert_args}"' \
-ordered-dither "${dither_pattern},16"'

      # shellcheck disable=SC2034
      colorspace="Gray"
      # shellcheck disable=SC2034
      depth="4"  # 16 colors
      format="png"
      quality="85"  # Compression level 8 with adaptive PNG filtering

      # Grayscale post effect
      postfx="${GRAY_POSTFX:-"${postfx}"}"
      ;;
    *)
      ;;
  esac

  # Force override if user defined DITHER_PATTERN
  dither_pattern="${DITHER_PATTERN:-"${dither_pattern}"}"

  if [ "${postfx}" != "" ]; then
    convert_args="${convert_args}"" \
${postfx}"
  fi

  # Color depth (preferably placed after ordered-dither)
  convert_args="${convert_args}"' \
-depth "${depth}"'

  # Common optimization
  convert_args="${convert_args}"' \
-type "optimize"'

  # shellcheck disable=SC2034
  local file__="!${file_%.*}-resize.${format}"

  eval 'magick "${file_}"' \
    "${convert_args}"' \
"${temp_dir}/${file__}" 2> /dev/null' || return 1

  # Increase progress bar
  echo "0" >&9
}

image_processor() {
  local fd="$1"
  # shellcheck disable=SC2034
  local action=
  local file_=
  local temp_dir=
  echo "${fd}" >&8
  eval 'while IFS="$(printf' "'\t'"')" read -r action file_ temp_dir; do
    case "${action}" in
      process)
        # FIXME: output may be interleaved
        image_resize || {
          printf' "'\r\033[KError: cannot process \"%s\". In most cases, it means processor is killed.\n'" '"${file_}"
          kill -TERM "$$"
          return 1
        }
        ;;
      *)
        return 0
        ;;
    esac
    echo "${fd}" >&8
  done <&'"${fd}"
}

image_repack() {
  case "$#" in
    0)
      echo "<reading sources from stdin...>" >&2

      local input=
      while read -r input; do
        image_repack "${input}" || return 1
        echo "----------------------------------------------"
      done

      return 0
      ;;
    1)
      ;;
    *)
      while [ "$1" != "" ] ; do
        image_repack "$1" || return 1
        echo "----------------------------------------------"
        shift
      done

      return 0
      ;;
  esac

  local source_="$(realpath -s -- "$1")"
  local target=
  local work_dir="${PWD}"
  local tmpdir="${TMPDIR:-"/tmp"}"

  # Ensure space is enough
  rm -rf "${tmpdir}"/extract_dir.*

  # Make sure source is directory
  if [ -f "$(realpath -- "${source_}")" ]; then
    case "${source_##*.}" in
      [Zz][Ii][Pp])
        case "${source_%.*}" in
          *-[Rr][Ee][Pp][Aa][Cc][Kk])
            echo "Skipping source already repacked..."
            return 0
            ;;
          *)
            ;;
        esac
        ;;
      *)
        echo "Error: source must be directory or zip!"
        return 1
        ;;
    esac

    target="${source_%.*}-repack.zip"
    echo "Target: .../${target##*/}"

    if [ -f "$(realpath -- "${target}")" ]; then
      echo "Skipping target already existing..."
      return 0
    fi

    local extract_dir="$(mktemp -d -t "extract_dir.XXXXX")"

    printf 'Unpacking...'
    unzip -jq "${source_}" -d "${extract_dir}" || return 1
    source_="${extract_dir}"
    printf '\r\033[K'
  fi

  # Make sure directory exists
  if [ ! -d "${source_}" ]; then
    echo "Error: source must be directory or zip!"
    return 1
  fi

  if [ "${target}" = "" ]; then
    target="${source_}-repack.zip"
    echo "Target: .../${target##*/}"

    if [ -f "$(realpath -- "${target}")" ]; then
      echo "Skipping target already existing..."
      return 0
    fi
  fi

  local temp_dir="$(mktemp -d -t "temp_dir.XXXXX")"
  cd "${source_}" || return 1

  printf 'Hashing...'
  local total="$(md5sum -- * 2> /dev/null | tee "${temp_dir}/~source.md5sums.txt" | wc -l)"
  printf '\r\033[K'

  if [ "${total}" -lt "1" ]; then
    echo "Skipping source is empty..."

    # Don't forget to go back when you return a non-error code...
    cd "${work_dir}" || return 1
    return 0
  fi

  printf 'Preparing...'
  stat -c '%n	%F	%s	%y' -- * > "${temp_dir}/~source.filestats.tsv" 2> /dev/null || return 1
  printf '\r\033[K'

  # Initial progress bar
  local progress_pipe="${temp_dir}/.progress_pipe"
  mkfifo "${progress_pipe}" \
    && exec 9<> "${progress_pipe}" \
    && { awk 'BEGIN {
    bases[1] = 60
    bases[2] = 60
    bases[3] = 24
    bases[4] = 365
    units[1] = "s"
    units[2] = "m"
    units[3] = "h"
    units[4] = "d"
    units[5] = "y"
    chars[0] = "/"
    chars[1] = "-"
    chars[2] = "\\"
    chars[3] = "|"
    total = 0
    count = 0
    start_time = systime()
  } {
    if (NF != 1) next
    if      ($1 == 0) count++
    else if ($1 == -2147483648) count--
    else if ($1 == 2147483647) ;
    else if ($1 == -2147483647) exit 1
    else if ($1 > 0) { total = $1; count = 0 }
    else count = -$1
    if (count >= total) {
       printf "\r\033[KProcessing: %d / %d (%.2f%%) | Done\n", count, total, count * 100 / total
       exit 0
    }
    printf "\r\033[KProcessing: %d %c %d (%.2f%%) | ETA: ", count, chars[count % 4], total, count * 100 / total
    if (count == 0) {
      start_time = systime()
      printf "N/A"
    } else {
      now_time = systime()
      remain = (total - count) * ((now_time - start_time) / count)
      index_ = 1
      while (remain >= bases[index_]) {
        buffer[index_] = remain % bases[index_]
        remain = int(remain / bases[index_])
        if (++index_ > 4) break
      }
      buffer[index_] = remain
      for (i = index_; i > 0; i--)
        printf "%d%s", buffer[i], units[i]
    }
  }' <&9 & }

  echo "${total}" >&9

  # Initial reporter pipe
  local reporter_pipe="${temp_dir}/.reporter_pipe"
  mkfifo "${reporter_pipe}" \
    && exec 8<> "${reporter_pipe}"

  # Multi-processing
  local job_max="${JOB_MAX:-"2"}"
  case "${job_max}" in
    0|1|2)
      ;;
    *)
      echo "<Warning: process more than 2 may be killed on low-memory devices>" >&2
      ;;
  esac

  if [ "${job_max}" -gt "5" ]; then
    echo "<Warning: shell limited we can only have 5 jobs>"
    job_max=5
  fi

  # Initial processors
  local fd=
  local message_pipe=
  local job_count=0
  while [ "${job_count}" -lt "${job_max}" ]; do
    fd="$((job_count + 3))"
    # shellcheck disable=SC2034
    message_pipe="${temp_dir}/.message_pipe_${job_count}"
    eval 'mkfifo "${message_pipe}" \
      && exec' "${fd}"'<> "${message_pipe}"'
    image_processor "${fd}" &
    : "$((job_count += 1))"
  done

  # Magick arguments
  local convert_args=

  local file_=
  for file_ in *; do
    if [ ! -f "$(realpath -- "${file_}")" ]; then
      continue
    fi

    case "${file_##*.}" in
      [Bb][Mm][Pp]) ;;
      [Jj][Pp][Ee][Gg]) ;;
      [Jj][Pp][Gg]) ;;
      [Pp][Nn][Gg]) ;;
      [Ww][Ee][Bb][Pp]) ;;
      *)
        printf '\r\033[KNote: "%s" is not image. Copy only.\n' "${file_}"
        cp -- "${file_}" "${temp_dir}/!${file_##*/}" || return 1

        # Increase progress bar
        echo "0" >&9

        continue
        ;;
    esac

    # Dispatching
    read -r fd <&8
    eval "printf 'process\t%s\t%s\n'" '"${file_}" "${temp_dir}" >&'"${fd}"
  done

  # Wait and stop processors
  job_count=0
  while read -r fd; do
    eval "echo 'quit'" '>&'"${fd}"
    # Close message pipes (it doesn't destroy buffered message, unless all processors stopped)
    eval 'exec' "${fd}"'<&-' "${fd}"'>&-'
    : "$((job_count += 1))"
    if [ "${job_count}" -ge "${job_max}" ]; then
      break
    fi
  done <&8

  # Close main pipes and wait until all processors stopped
  exec 9<&- 9>&- 8<&- 8>&-
  wait

  rm -rf "${tmpdir}"/extract_dir.*
  cd "${work_dir}" || return 1

  printf 'Repacking...'
  zip -jq -r "${target}" "${temp_dir}"/* || return 1
  rm -rf "${tmpdir}"/temp_dir.*
  printf '\r\033[K'
}

image_repack "$@" || {
  echo "Error: something wrong!?"
  kill -TERM "$$"
}
