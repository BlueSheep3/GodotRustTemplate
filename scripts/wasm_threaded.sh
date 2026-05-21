#!/usr/bin/env bash

cd "$(dirname "$0")/../rust"

RUSTFLAGS="-C link-args=-pthread \
-C target-feature=+atomics \
-C link-args=-sSIDE_MODULE=2 \
-C llvm-args=-enable-emscripten-cxx-exceptions=0 \
-Z default-visibility=hidden \
-Z link-native-libraries=no \
-Z emscripten-wasm-eh=false" cargo +nightly build --features=wasm -Zbuild-std --target wasm32-unknown-emscripten
