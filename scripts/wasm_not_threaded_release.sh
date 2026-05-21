#!/usr/bin/env bash

cd "$(dirname "$0")/../rust"

cargo +nightly build --features=wasm,nothreads -Zbuild-std --target wasm32-unknown-emscripten --release
