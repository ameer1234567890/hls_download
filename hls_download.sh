#!/bin/sh
url="$1"
quality="$2"

check_tools() {
  tools="curl ffmpeg"
  for tool in $tools; do
    if [ ! "$(command -v "$tool")" ]; then
      printf "\e[1m%s\e[0m not found! Exiting....\n" "$tool"
      exit 1
    fi
  done
}

download_part() {
  echo "Downloading $partn.... ($i/$num_parts)"
  j=0
  while [ "$native_file_size" != "$remote_file_size" ]; do
    j="$((j + 1))"
    if [ "$j" -gt 10 ]; then
      echo "Too many re-tries! Exiting...."
      exit 1
    fi
    curl -o "$tmpdir"/"$partn" --progress-bar "$hlsq_path""$part"
    native_file_size="$(stat --printf="%s" "$tmpdir"/"$partn" 2>/dev/null)"
    if [ "$remote_file_size" = "" ]; then
      remote_file_size="$(echo "$response" | grep -i 'Content-Length' | awk '{print $2}')"
    fi
  done
}

check_tools

if [ "$url" = "-h" ] || [ "$url" = "--help" ]; then
  echo "Usage: $0 URL [high|low]"
  exit 0
fi

if [ "$url" = "" ]; then
  echo "No URL provided! Exiting...."
  exit 1
fi

curl -I "$url" 2>/dev/null >url_check.txt
curl_status="$?"
http_status="$(head <url_check.txt -n 1 | awk '{print $2}')"
if [ "$curl_status" != 0 ]; then
  echo "cURL Error: $curl_status. Exiting...."
  rm url_check.txt
  exit 1
fi
if [ "$http_status" != 200 ]; then
  echo "URL Error: $http_status. Exiting...."
  rm url_check.txt
  exit 1
fi
rm url_check.txt

video_id="$(echo "$url" | cut -d '/' -f 4)"
tmpdir="tmp_$video_id"
mkdir -p "$tmpdir"

tokens=""
i=0
while [ "$tokens" = "" ]; do
  i="$((i + 1))"
  if [ "$i" -gt 10 ]; then
    echo "Too many re-tries! Exiting...."
    exit 1
  fi
  printf "Requesting video page.... "
  curl -o "$tmpdir"/page.html --silent "$url"
  if [ "$(cat "$tmpdir"/page.html 2>/dev/null)" = "" ]; then
    echo "Invalid response! Exiting...."
    exit 1
  fi
  has_tokens="$(grep <"$tmpdir"/page.html setVideoHLS | cut -d "'" -f 2 | grep '?')"
  if [ "$has_tokens" = "" ]; then
    tokens=""
    echo "Failed!"
  else
    tokens="$(grep <"$tmpdir"/page.html setVideoHLS | cut -d "'" -f 2 | cut -d '?' -f 2)"
    echo "Done!"
  fi
  sleep 2
done

hls_url="$(grep <"$tmpdir"/page.html setVideoHLS | cut -d "'" -f 2)"
if [ "$hls_url" = "" ]; then
  echo "No HLS sources found! Exiting...."
  exit 1
fi

printf "Requesting available formats.... "
curl -o "$tmpdir"/hls.m3u8 --silent "$hls_url"
echo "Done!"
if [ "$(cat "$tmpdir"/hls.m3u8 2>/dev/null)" = "" ]; then
  echo "Format list is empty! Exiting...."
  exit 1
fi

grep <"$tmpdir"/hls.m3u8 hls- | cut -d '-' -f 2 | cut -d '.' -f 1 >"$tmpdir/"hlsq_list.txt
if [ "$(cat "$tmpdir"/hlsq_list.txt 2>/dev/null)" = "" ]; then
  echo "Format list (text) is empty! Exiting...."
  exit 1
fi

if [ "$quality" = "high" ]; then
  hlsq_raw="$(sort <"$tmpdir"/hlsq_list.txt -g | tail -1)"
elif [ "$quality" = "low" ]; then
  hlsq_raw="$(sort <"$tmpdir"/hlsq_list.txt -g | head -1)"
fi

if [ "$hlsq_raw" = "" ]; then
  nl -s ". " -w 1 "$tmpdir"/hlsq_list.txt
  count="$(wc -l "$tmpdir"/hlsq_list.txt | cut -f 1 -d' ')"
  while true; do
    printf "Select option: "
    read -r opt
    if [ "$opt" -eq "$opt" ] 2>/dev/null && [ "$opt" -gt 0 ] 2>/dev/null && [ "$opt" -le "$count" ] 2>/dev/null; then
      break
    fi
  done
  value="$(sed -n "${opt}p" "$tmpdir"/hlsq_list.txt)"
  hlsq_raw="$value"
  echo "Proceeding with $value...."
fi

hlsq="hls-$hlsq_raw.m3u8?$tokens"
hlsqf="hls-$hlsq_raw.m3u8"
hlsq_path="$(echo "$hls_url" | cut -d '?' -f 1)"
hlsq_path="${hlsq_path%????????}"
hlsq_url="$hlsq_path$hlsq"

printf "Requesting HLS playlist.... "
curl -o "$tmpdir"/"$hlsqf" --silent "$hlsq_url"
if [ "$(cat "$tmpdir"/"$hlsqf" 2>/dev/null)" = "" ]; then
  echo "Failed! Exiting...."
  exit 1
fi
echo "Done!"

parts="$(grep <"$tmpdir"/"$hlsqf" hls-)"
num_parts="$(echo "$parts" | wc -w)"

i=0
for part in $parts; do
  i="$((i + 1))"
  partn="$(echo "$part" | cut -d '?' -f 1)"
  response="$(curl -I --silent "$hlsq_path""$part")"
  remote_file_size="$(echo "$response" | grep 'Content-Length' | awk '{print $2}')"
  native_file_size="$(stat --printf="%s" "$tmpdir"/"$partn" 2>/dev/null)"
  if [ "$native_file_size" = "" ]; then
    native_file_size="0"
  fi
  if [ ! -f "$tmpdir/$partn" ]; then
    download_part
  else
    if [ "$native_file_size" -eq "$remote_file_size" ]; then
      echo "$partn Already downloaded. Continuing.... ($i/$num_parts)"
    else
      download_part
    fi
  fi
done

concat_parts=""
for part in $parts; do
  partn="$(echo "$part" | cut -d '?' -f 1)"
  if [ "$concat_parts" = "" ]; then
    concat_parts="$tmpdir/$partn"
  else
    concat_parts="$concat_parts|$tmpdir/$partn"
  fi
done

printf "Combining parts.... "
filename="${video_id}_${hlsq_raw}.mp4"
i=0
while [ -f "$filename" ]; do
  i="$((i + 1))"
  filename="${video_id}_${hlsq_raw}(${i}).mp4"
done
ffmpeg -hide_banner -loglevel panic -i "concat:$concat_parts" -c copy "$filename"

ffmpeg_status="$?"
if [ "$ffmpeg_status" != 0 ]; then
  echo "Failed!"
  echo "ffmpeg Error: $ffmpeg_status. Exiting...."
  exit 1
fi

if [ ! -f "$filename" ]; then
  echo "Failed!"
  echo "Something went wrong! Output file not found! Exiting...."
  exit 1
fi
echo "Done!"

printf "Cleaning up temporary files.... "
sleep 1
rm -rf "$tmpdir"
echo "Done!"
