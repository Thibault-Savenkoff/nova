# fish completion for yaif. Install: copy into ~/.config/fish/completions/yaif.fish
# (or a vendor_completions.d directory) -- fish loads it automatically, no config edit needed.

set -l cmds encode decode convert preview info bench version

complete -c yaif -f -n "not __fish_seen_subcommand_from $cmds" -a "$cmds"
complete -c yaif -f -n "not __fish_seen_subcommand_from $cmds" -l version -d "print the version"

complete -c yaif -n "__fish_seen_subcommand_from encode" -o m -x -a "adaptive lossless lossy" -d mode
complete -c yaif -n "__fish_seen_subcommand_from encode" -o l -x -a "0 1 2 3 4 5" -d "codec level"
complete -c yaif -n "__fish_seen_subcommand_from encode" -o q -x -d "wavelet quality 0-100"
complete -c yaif -n "__fish_seen_subcommand_from encode" -o e -x -d "max error per sample 1-64"
complete -c yaif -n "__fish_seen_subcommand_from encode" -o d -x -d "frame delay in ms"
complete -c yaif -n "__fish_seen_subcommand_from encode" -o live -r -d "Live Photo video"

complete -c yaif -n "__fish_seen_subcommand_from decode convert" -o q -x -d "output quality 1-100"
complete -c yaif -n "__fish_seen_subcommand_from decode convert" -o m -x -a "lossy lossless" -d mode
complete -c yaif -n "__fish_seen_subcommand_from decode convert" -o fast -d "WebP about 4x faster"
complete -c yaif -n "__fish_seen_subcommand_from decode convert" -o hdr -d "HDR rendition"
complete -c yaif -n "__fish_seen_subcommand_from decode convert" -o look -x -a "canon darktable" -d "RAW look"
