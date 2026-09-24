#!/bin/bash
# Mean size ratios of YAIF level 5 vs WebP, AVIF and HEIC at equal PSNR and SSIM, over 3 photo crops.
cd "$(dirname "$0")/.."
for f in test/quick/IMG_0412_crop.png test/quick/IMG_0577_crop.png test/quick/IMG_1008_crop.png; do
  RD_QUIET=1 UV_OFFLINE=1 uv run -q --with pillow --with numpy python test/rd.py $f 30 45 60 75 90
done | awk '/yaif\/webp/ { if ($10 != "-") { gsub("%","",$10); w[$1]+=$10; nw[$1]++ } if ($12 != "-") { gsub("%","",$12); a[$1]+=$12; na[$1]++ } if ($14 != "-") { gsub("%","",$14); hh[$1]+=$14; nh[$1]++ } }
END { for (k in w) printf "%s  yaif/webp %.1f%%  yaif/avif %.1f%%  yaif/heic %.1f%%\n", k, w[k]/nw[k], a[k]/na[k], hh[k]/nh[k] }'
