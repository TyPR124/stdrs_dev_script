#!/bin/bash

set -euo pipefail

targets=(x86_64-unknown-linux-gnu x86_64-pc-windows-gnu x86_64-apple-darwin)
out_dir=html
rust_dir=rust
init_only=false
cargo_log=cargo.log

function print_help() {
    cat << EOF
This script generates internal documentation for the nightly version of Rust's
standard library.

Usage: mkdocs.sh [FLAGS]
    FLAGS:
        --init      Only do initialization tasks.
        --out       Output directory for generated docs. Default: $out_dir
        --rust-dir  The directory to use for the Rust git repo. Default: $rust_dir
        --help      Print this help message and exit.
EOF
}

function check_prereqs() {
    which rustup >> /dev/null || {
        echo 'Please install rustup and try again.'
        echo 'See https://rustup.rs'
        echo 'Or just run:'
        echo "  curl -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly --profile minimal --component rust-docs"
        exit 1
    }
    which git >> /dev/null || { echo 'Please install git and try again.'; exit 1; }
    which rg >> /dev/null || { echo 'Please install ripgrep (rg) and try again.'; exit 1; }
}

while [ $# -gt 0 ]; do
    case "$1" in
        --init)
            init_only=true
            shift
            ;;
        --out)
            out_dir="$2"
            shift; shift
            ;;
        --rust-dir)
            rust_dir="$2"
            shift; shift
            ;;
        --help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown argument '$1'"
            print_help
            echo "Unknown argument '$1'"
            exit 1
            ;;
    esac
done

check_prereqs

rustup toolchain install nightly --profile minimal -c cargo -c rustc -c rust-docs
rustup target add "${targets[@]}"
rustc_hash="$(rustc +nightly -vV | rg '^commit-hash: (.+)$' --replace '$1')"

[ -e "$rust_dir" ]      || mkdir -p "$rust_dir"
[ -d "$rust_dir/.git" ] || git clone https://github.com/rust-lang/rust "$rust_dir"

pushd "$rust_dir" > /dev/null
git fetch --all
git reset --hard "$rustc_hash"
git submodule update --init --recursive --force
popd > /dev/null

if "$init_only"; then exit 0; fi

html_in_header=$(realpath 'in-head.html')
rustdoc_unstable_flags=(-Z unstable-options --document-hidden-items --generate-link-to-definition)
rustdoc_stable_flags=(--document-private-items --crate-version "${rustc_hash:0:7}" --html-in-header "$html_in_header")
export RUSTDOCFLAGS="${rustdoc_stable_flags[*]} ${rustdoc_unstable_flags[*]}"

for target in "${targets[@]}"; do
    echo "Building docs for $target"
    cargo +nightly doc --target "$target" \
        --manifest-path "$rust_dir"/library/std/Cargo.toml \
        --target-dir "$rust_dir"/target \
    > "$cargo_log" 2>&1 || { cat "$cargo_log"; exit 1; }
done
echo "Successfully documented all targets."
echo "Building final output..."
# :? errors on emtpy or null
rm -rf "${out_dir:?}"/*
mkdir -p "$out_dir/nightly"
cp static_root/* "$out_dir"/
for target in "${targets[@]}"; do
    mv "$rust_dir/target/$target/doc" "$out_dir/nightly/$target"
    printf "Updated: $(date -u)\nHash: %s" "$rustc_hash" > "$out_dir/nightly/$target/meta.txt"
done
echo "All done!"
