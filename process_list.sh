list="$1"
quality="$2"

if [ \( "$list" == "-h" \) -o \( "$list" == "--help" \) ]; then
  echo "Usage: $0 LIST_FILE [low|high]"
  exit 0
fi

if [ "$list" == "" ]; then
  echo "No list provided! Exiting...."
  exit 1
fi

if [ ! -f "$list" ]; then
  echo "List file does not exist! Exiting...."
  exit 1
fi

list_file_size="`stat --printf=\"%s\" $list 2> /dev/null`"
if [ "$list_file_size" == 0 ]; then
  echo "List is empty! Exiting...."
  exit 1
fi

cp list.txt list_orig.txt
list_items="`cat $list`"
for link in $list_items; do
  echo "Processing $link"
  ./hls_download.sh $link $quality
  script_status="$?"
  if [ "$script_status" == 0 ]; then
    echo "Success! Removing URL from list...."
    #cat list.txt | grep -v $link #> $list
    #read -n1 -r -p "Press any key to continue..."
    echo ""
  else
    echo "Error processing list item: $script_status. Skipping to next item...."
  fi
done
