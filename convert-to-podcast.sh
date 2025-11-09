#!/bin/bash
# convert_wanshow.sh
# Converts WAN Show mp4 files to m4a audio with proper metadata for Plex

SRC_DIR="/<PATH_TO_DRIVE>/FP/The WAN Show"
DST_DIR="/<PATH_TO_DRIVE>/Podcasts/The WAN Show/"

mkdir -p "$DST_DIR"

tmpfile=$(mktemp /tmp/wanshow.XXXXXX)
trap 'rm -f "$tmpfile"' EXIT

# Build file list of all MP4s with year, release date, filename, full path
find "$SRC_DIR" -type f -name "*.mp4" | while read -r src; do
    [[ ! -f "$src" ]] && continue

    filename=$(basename "$src")
    year=$(echo "$filename" | grep -oE '[0-9]{4}' | head -n1)
    [[ -z "$year" ]] && year=$(date -r "$src" +%Y)

    release_date=$(echo "$filename" | grep -oE '[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4}' | tail -n1)
    if [[ -n "$release_date" ]]; then
        sort_date=$(date -d "$release_date" +%Y-%m-%d 2>/dev/null)
    else
        sort_date=$(date -r "$src" +%Y-%m-%d)
    fi

    echo "$year|$sort_date|$filename|$src"
done > "$tmpfile"

# Generate fixed album IDs per year
declare -A album_ids
years=($(cut -d'|' -f1 "$tmpfile" | sort -u -r))
for year in "${years[@]}"; do
    album_ids["$year"]="wanshow-$year"
done

# Process each year
for year in "${years[@]}"; do
    album="WAN Show $year"
    album_id="${album_ids[$year]}"
    echo "Processing album: $album (ID: $album_id)"

    # Sort files by release date + filename
    mapfile -t files < <(grep "^$year|" "$tmpfile" | sort -t'|' -k2,2 -k3,3)

    # Determine the last track number already in DST_DIR
    existing_tracks=($(ls "$DST_DIR" | grep -i "\.m4a$" | grep "$year" | wc -l))
    track=$((existing_tracks + 1))

    for line in "${files[@]}"; do
        IFS='|' read -r _ sort_date filename src <<< "$line"
        [[ ! -f "$src" ]] && continue

        name_noext="${filename%.*}"
        dst="$DST_DIR/$name_noext.m4a"

        # Skip already converted files
        if [[ -f "$dst" ]]; then
            echo "Skipping existing file: $dst"
            continue
        fi

        # Clean title with fallback
        title=$(echo "$filename" | sed -E 's/^The WAN Show - S[0-9]+E[0-9]+ - //' \
                                      | sed -E 's/\.[Mm][Pp]4$//' \
                                      | sed -E 's/ +/ /g')
        [[ -z "$title" ]] && title="$name_noext"

        cover_art="${SRC_DIR}/${name_noext}.jpg"

        # Create a unique temporary file
        tmp_dst=$(mktemp /tmp/wanshow.XXXXXX.m4a)

        echo "Converting: $src -> $dst"
        echo "Metadata: Album=$album, Track=$track, Title=$title, Date=$sort_date, AlbumID=$album_id"

	if [[ -f "$cover_art" ]]; then
    	    ffmpeg -y -i "$src" -i "$cover_art" \
        	-map 0:a:0? -map 1 \
        	-c:a copy \
        	-metadata album="$album" \
        	-metadata artist="The WAN Show" \
        	-metadata album_artist="The WAN Show" \
        	-metadata title="$title" \
        	-metadata date="$sort_date" \
        	-metadata track="$track" \
        	-metadata musicbrainz_albumid="$album_id" \
        	-disposition:v:1 attached_pic \
        	"$tmp_dst"
	else
    	     ffmpeg -y -i "$src" -map 0:a:0? -c:a copy \
        	-metadata album="$album" \
        	-metadata artist="The WAN Show" \
        	-metadata album_artist="The WAN Show" \
        	-metadata title="$title" \
        	-metadata date="$sort_date" \
        	-metadata track="$track" \
        	-metadata musicbrainz_albumid="$album_id" \
        	"$tmp_dst"
	fi

        # Move completed file to final destination
        mv "$tmp_dst" "$dst"

        track=$((track+1))
    done
done
