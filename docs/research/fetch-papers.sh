#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
paper_dir="$script_dir/papers"
mkdir -p "$paper_dir"

fetch() {
    name=$1
    url=$2
    expected=$3
    target="$paper_dir/$name"

    curl -fL --retry 2 --output "$target" "$url"
    printf '%s  %s\n' "$expected" "$target" | sha256sum --check --status || {
        printf 'checksum mismatch: %s\n' "$target" >&2
        exit 1
    }
    printf 'verified %s\n' "$name"
}

fetch \
    reynolds-1987-boids.pdf \
    https://www.red3d.com/cwr/papers/1987/SIGGRAPH87.pdf \
    51d39235fc07ddeeb4dea0c7ad780a8c5785a7961982e52447da72a28fd103b0

fetch \
    reynolds-1999-steering.pdf \
    https://www.red3d.com/cwr/papers/1999/gdc99steer.pdf \
    58556b940c8f123de969919fc9a77196f4cc0e470a98b6b12af75c741e42befc

fetch \
    couzin-et-al-2002-collective-memory.pdf \
    https://jmvidal.cse.sc.edu/library/couzin02a.pdf \
    f0f0b6541d7384bdc4eef5f9f3d34d3971d084e4489d7a6a785bcd51faecf3d6

fetch \
    strombom-et-al-2014-shepherding.pdf \
    https://www.repository.cam.ac.uk/bitstreams/1cc02818-9d26-43a8-8d08-d137c9a7754e/download \
    7acd4136c97a1c839e144d567e788304cf7c4744b8b436ab65b45ccec943eb5e
