#!/usr/bin/env bash

cd "$(dirname "$0")/../rust"

cargo apk build --target=aarch64-linux-android --features=android --release
