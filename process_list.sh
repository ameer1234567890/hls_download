#!/bin/sh
list="$1"
quality="$2"

if [ "$list" = "-h" ] || [ "$list" = "--help" ]; then
  echo "Usage: $0 LIST_FILE [low|high]"
  exit 0
fi

if [ "$list" = "" ]; then
  echo "No list provided! Exiting...."
  exit 1
fi

if [ ! -f "$list" ]; then
  echo "List file does not exist! Exiting...."
  exit 1
fi

list_file_size="$(stat --printf="%s" "$list" 2> /dev/null)"
if [ "$list_file_size" -eq 0 ]; then
  echo "List is empty! Exiting...."
  exit 1
fi

bkfile_name="$(echo "$list" | cut -d '.' -f 1)"
bkfile_ext="$(echo "$list" | cut -d '.' -f 2)"
cp "$list" "${bkfile_name}"_orig."$bkfile_ext"
list_items="$(cat "$list")"
for link in $list_items; do
  echo "Processing $link"
  ./hls_download.sh "$link" "$quality"
  script_status="$?"
  if [ "$script_status" -eq 0 ]; then
    printf "Success! Removing URL from list...."
    new_list="$(< "$list" grep -v "$link")"
    echo "$new_list" > "$list"
    echo "Done!"
  else
    echo "Error processing list item: $script_status. Skipping to next item...."
  fi
done
