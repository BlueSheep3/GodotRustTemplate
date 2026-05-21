# this code is based on:
# https://woile.dev/blog/android-apps-with-slint-on-nixos.html
#
# FIXME This flake currently contains a bunch of system dependant stuff.
# It is made for Linux x86_64, so everything should work on that system,
# but this should have support for more systems in the future.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    naersk,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      perSystem = {
        pkgs,
        inputs',
        lib,
        system,
        ...
      }: let
        name = "RustTemplate";
        version = "0.0.0";

        # includes native export template
        godot = pkgs.godotPackages_4_6.godot;
        # includes export templates other than just native
        godot-export-templates = pkgs.godotPackages_4_6.export-templates-bin;

        ###############################################################################
        #                               NATIVE / LINUX                                #
        ###############################################################################

        naersk-native = pkgs.callPackage naersk {
          cargo = inputs'.fenix.packages.complete.toolchain;
          rustc = inputs'.fenix.packages.complete.toolchain;
        };
        rustext-native = naersk-native.buildPackage {
          name = "${name}-rustext";
          src = ./rust;
          copyLibs = true;
        };
        game-linux = pkgs.stdenv.mkDerivation {
          pname = name;
          inherit version;
          src = ./godot;

          nativeBuildInputs = [
            rustext-native
            godot
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p "godot"
            shopt -s extglob
            mv !(godot) "godot"
            shopt -u extglob

            # godot also requires the library to exist as a debug library to use before exporting
            mkdir -p 'rust/target/release' 'rust/target/debug'
            ln -s '${rustext-native}/lib/librustext.so' 'rust/target/release/librustext.so'
            ln -s '${rustext-native}/lib/librustext.so' 'rust/target/debug/librustext.so'

            export HOME="$(mktemp -d)"
            mkdir -p "$HOME/.local/share/godot/"
            ln -s '${godot.export-template}/share/godot/export_templates' "$HOME/.local/share/godot/"
            mkdir -p export

            # there is some really weird crash here that happens when godot closes
            # this causes this step to fail, even though godot actually does export the game
            godot --headless --path 'godot' --export-release 'Linux x86_64' '../export/${name}' 2>stderr || true
            grep 'handle_crash: Program crashed with signal 11' stderr

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -D -m 755 -t "$out/libexec" "export/${name}"
            install -D -m 644 -t "$out/libexec" "export/${name}.pck"
            install -D -m 644 -t "$out/libexec" "export/librustext.so"
            install -d -m 755 "$out/bin"
            ln -s "$out/libexec/${name}" "$out/bin/${name}"
            runHook postInstall
          '';
        };

        ###############################################################################
        #                                   ANDROID                                   #
        ###############################################################################

        platformVersion = "35";
        systemImageType = "default";
        androidEnv = pkgs.androidenv.override {licenseAccepted = true;};
        androidComp = (
          androidEnv.composeAndroidPackages {
            cmdLineToolsVersion = "8.0";
            includeNDK = true;
            # we need some platforms
            platformVersions = [
              "30"
              platformVersion
            ];
            includeSystemImages = true;
            systemImageTypes = [systemImageType];
            abiVersions = [
              "x86"
              "x86_64"
              "armeabi-v7a"
              "arm64-v8a"
            ];
            cmakeVersions = ["3.10.2"];
          }
        );
        android-sdk = pkgs.android-studio.withSdk androidComp.androidsdk;
        android-toolchain = with inputs'.fenix.packages;
          combine [
            complete.toolchain
            targets.aarch64-linux-android.latest.rust-std
          ];
        naersk-android = pkgs.callPackage naersk {
          cargo = android-toolchain;
          rustc = android-toolchain;
        };
        rustext-android = naersk-android.buildPackage {
          name = "${name}-android-rustext";
          src = ./rust;
          copyTarget = true;

          # this command has a weird issue that causes it to fail due to
          # not finding some file even though the build actually succeeeds.
          cargoBuild = oldCmd: ''cargo apk build --target=aarch64-linux-android --features=android --release || true'';

          nativeBuildInputs = [
            pkgs.cargo-apk
            pkgs.jdk
            android-sdk
          ];

          ANDROID_HOME = "${androidComp.androidsdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidComp.androidsdk}/libexec/android-sdk";
          ANDROID_NDK_ROOT = "${androidComp.androidsdk}/libexec/android-sdk/ndk-bundle";

          LD_LIBRARY_PATH = "$LD_LIBRARY_PATH:${
            lib.makeLibraryPath [
              pkgs.wayland
              pkgs.libxkbcommon
              pkgs.fontconfig
            ]
          }";
        };
        game-android = pkgs.stdenv.mkDerivation {
          pname = "${name}-android";
          inherit version;
          src = ./godot;

          nativeBuildInputs = [
            rustext-android
            rustext-native
            godot
            godot-export-templates
            pkgs.jdk
            android-sdk
            pkgs.zstd
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p "godot"
            shopt -s extglob
            mv !(godot) "godot"
            shopt -u extglob

            # TODO setup the release keystore
            # this currently builds in debug mode to avoid having to setup the keystore

            # godot requires a debug version of the native library to use before exporting
            mkdir -p 'rust/target/aarch64-linux-android/debug' 'rust/target/debug'
            ln -s '${rustext-native}/lib/librustext.so' 'rust/target/debug/librustext.so'
            cd rust
            tar -xf '${rustext-android}/target.tar.zst' 'target/release/apk/lib/arm64-v8a/librustext.so'
            ln -s '../../release/apk/lib/arm64-v8a/librustext.so' 'target/aarch64-linux-android/debug/librustext.so'
            cd ..

            export HOME="$(mktemp -d)"
            mkdir -p "$HOME/.local/share/godot/"
            ln -s '${godot-export-templates}/share/godot/export_templates' "$HOME/.local/share/godot/"

            mkdir -p "$HOME/.config/godot/"
            cat >"$HOME/.config/godot/editor_settings-4.6.tres" <<EOF
            [gd_resource type="EditorSettings" format=3]
            [resource]
            export/android/java_sdk_path = "${pkgs.jdk}/lib/openjdk"
            export/android/android_sdk_path = "${androidComp.androidsdk}/libexec/android-sdk"
            EOF

            mkdir -p export
            godot --install-android-build-template --headless --path 'godot' --export-debug 'Android aarch64' '../export/${name}.apk'

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -D -m 755 -t "$out/libexec" "export/${name}.apk"
            install -D -m 644 -t "$out/libexec" "export/${name}.apk.idsig"
            runHook postInstall
          '';
        };
        devshell-android-rust-only = pkgs.mkShell {
          name = "dev-rustext-android";

          buildInputs = [
            android-toolchain
            pkgs.cargo-apk
            pkgs.jdk
            android-sdk
          ];

          ANDROID_HOME = "${androidComp.androidsdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidComp.androidsdk}/libexec/android-sdk";
          ANDROID_NDK_ROOT = "${androidComp.androidsdk}/libexec/android-sdk/ndk-bundle";

          LD_LIBRARY_PATH = "$LD_LIBRARY_PATH:${
            lib.makeLibraryPath [
              pkgs.wayland
              pkgs.libxkbcommon
              pkgs.fontconfig
            ]
          }";
        };

        ###############################################################################
        #                                WEB ASSEMBLY                                 #
        ###############################################################################

        wasm-toolchain = with inputs'.fenix.packages;
          combine [
            complete.toolchain
            targets.wasm32-unknown-emscripten.latest.rust-std
          ];
        naersk-wasm = pkgs.callPackage naersk {
          cargo = wasm-toolchain;
          rustc = wasm-toolchain;
        };
        rustext-wasm-tar-no-threads = naersk-wasm.buildPackage {
          name = "${name}-rustext-wasm-tar-no-threads";
          src = ./rust;
          copyTarget = true;

          nativeBuildInputs = [
            pkgs.emscripten
            godot
            pkgs.llvmPackages.clang-unwrapped.lib
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.clang-unwrapped.lib}/lib";

          # add in the dependencies of std to be able to build it (with -Zbuild-std)
          # https://github.com/nix-community/naersk/issues/146#issuecomment-2176827359
          additionalCargoLock = "${inputs'.fenix.packages.complete.rust-src}/lib/rustlib/src/rust/library/Cargo.lock";

          # during this build godot will be called, which needs a home
          cargoBuild = oldCmd: ''export HOME="$(mktemp -d)"; cargo build --no-default-features --features=wasm,nothreads -Zbuild-std --target=wasm32-unknown-emscripten --release'';
        };
        rustext-wasm-no-threads = pkgs.stdenv.mkDerivation {
          name = "${name}-rustext-wasm-no-threads";
          src = "${rustext-wasm-tar-no-threads}";
          nativeBuildInputs = [pkgs.zstd];

          installPhase = ''
            tar -xf "$src/target.tar.zst"
            mkdir -p "$out/lib"
            mv 'target/wasm32-unknown-emscripten/release/rustext.wasm' "$out/lib/rustext.wasm"
          '';
        };
        game-wasm-no-threads = pkgs.stdenv.mkDerivation {
          pname = "${name}-wasm-no-threads";
          inherit version;
          src = ./godot;

          nativeBuildInputs = [
            rustext-wasm-no-threads
            rustext-native
            godot
            godot-export-templates
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p "godot"
            shopt -s extglob
            mv !(godot) "godot"
            shopt -u extglob

            # godot requires a debug version of the native library to use before exporting
            mkdir -p 'rust/target/wasm32-unknown-emscripten/release' 'rust/target/debug'
            ln -s '${rustext-native}/lib/librustext.so' 'rust/target/debug/librustext.so'
            ln -s '${rustext-wasm-no-threads}/lib/rustext.wasm' 'rust/target/wasm32-unknown-emscripten/release/rustext.wasm'

            export HOME="$(mktemp -d)"
            mkdir -p "$HOME/.local/share/godot/"
            ln -s '${godot-export-templates}/share/godot/export_templates' "$HOME/.local/share/godot/"
            mkdir -p export

            # there is some really weird crash here that happens when godot closes
            # this causes this step to fail, even though godot actually does export the game
            godot --headless --path 'godot' --export-release 'Web' '../export/${name}.html' 2>stderr || true
            grep 'handle_crash: Program crashed with signal 11' stderr

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -D -m 644 -t "$out/libexec" "export/${name}.apple-touch-icon.png"
            install -D -m 644 -t "$out/libexec" "export/${name}.audio.position.worklet.js"
            install -D -m 644 -t "$out/libexec" "export/${name}.audio.worklet.js"
            install -D -m 644 -t "$out/libexec" "export/${name}.html"
            install -D -m 644 -t "$out/libexec" "export/${name}.icon.png"
            install -D -m 644 -t "$out/libexec" "export/${name}.js"
            install -D -m 644 -t "$out/libexec" "export/${name}.pck"
            install -D -m 644 -t "$out/libexec" "export/${name}.png"
            install -D -m 644 -t "$out/libexec" "export/${name}.side.wasm"
            install -D -m 644 -t "$out/libexec" "export/${name}.wasm"
            install -D -m 644 -t "$out/libexec" "export/rustext.wasm"
            runHook postInstall
          '';
        };
        devshell-wasm-rust-only = pkgs.mkShell {
          name = "dev-rustext-wasm";

          buildInputs = [
            pkgs.emscripten
            pkgs.llvmPackages.clang-unwrapped.lib
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.clang-unwrapped.lib}/lib";
        };

        ###############################################################################
        #                                MISCELLANEOUS                                #
        ###############################################################################

        game-all = pkgs.runCommand "${name}-all" {} ''
          mkdir -p "$out"
          ln -s "${game-linux}/libexec" "$out/linux"
          ln -s "${game-android}/libexec" "$out/android"
          ln -s "${game-wasm-no-threads}/libexec" "$out/web"
        '';
      in {
        ###############################################################################
        #                       OUTPUT PACKAGES AND DEV-SHELLS                        #
        ###############################################################################

        # only required for android
        _module.args.pkgs = import self.inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.android_sdk.accept_license = true;
        };

        packages = {
          inherit
            rustext-native
            rustext-android
            rustext-wasm-no-threads
            # rustext-wasm-threads
            game-linux
            game-android
            game-wasm-no-threads
            # game-wasm-threads
            game-all
            ;
        };

        # a dev shell specifically for building the rustext
        # does not include any tooling for godot
        devShells = {
          android-rust-only = devshell-android-rust-only;
          wasm-rust-only = devshell-wasm-rust-only;
        };
      };
    };
}
