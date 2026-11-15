#!/usr/bin/env bash
# Generates the app icon and sample product photos used by the demo data.
# Run from the project root. Logs go to $TMPDIR/boutik_assets.
set -u
A="ios-boutik/Boutik/Assets.xcassets"
LOG="${TMPDIR:-/tmp}/boutik_assets"
mkdir -p "$LOG"

img() { # name prompt
  local name="$1"; shift
  mkdir -p "$A/$name.imageset"
  printf '{"images":[{"filename":"%s.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}' "$name" > "$A/$name.imageset/Contents.json"
  (rork ai image "$1" --name "$name" --opaque -o "$A/$name.imageset/$name.png"; echo "exit $?") > "$LOG/$name.txt" 2>&1 &
}

STYLE="Realistic product photo for a West African grocery shop point-of-sale app, product centered, soft natural daylight, softly blurred shop shelves in the background, warm and clean, no text overlay"
img p_riz "A woven sack bowl filled with long-grain perfumed white rice with a metal scoop. $STYLE"
img p_huile "Two yellow 1 litre bottles of vegetable cooking oil. $STYLE"
img p_lait "A yellow tin of powdered milk 400 g. $STYLE"
img p_savon "A blue box of laundry detergent powder 500 g. $STYLE"
img p_sucre "A clear plastic bag of white granulated sugar 1 kg. $STYLE"
img p_soda "Bottles of cola soda 1.5 litre lined up. $STYLE"
img p_tomate "Small tins of tomato paste concentrate stacked. $STYLE"
img p_eau "A pack of 1.5 litre mineral water bottles. $STYLE"
img p_pates "Packs of spaghetti pasta 500 g. $STYLE"
img c_kone "Portrait photo of a smiling West African businesswoman in her fifties wearing a colorful wax print headwrap, at a busy market stall, warm daylight, head and shoulders, square crop"

(rork ai image --icon "A rounded friendly shopping bag symbol with a small upward green arrow, white bag on a deep green #0B7A3E background with subtle soft gradient, flat modern iOS icon style, opaque full-bleed" -o assets/generated/icon.png && rork ai edit icon-set assets/generated/icon.png --target ios -o "$A"; echo "exit $?") > "$LOG/icon.txt" 2>&1 &
wait
