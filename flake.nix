{
  description = "casper-event-standard";

  nixConfig = {
    extra-substituters = [
      "https://crane.cachix.org"
      "https://nix-community.cachix.org"
      "https://cspr.cachix.org"
    ];
    extra-trusted-public-keys = [
      "crane.cachix.org-1:8Scfpmn9w+hGdXH/Q9tTLiYAE/2dnJYRJP7kl80GuRk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cspr.cachix.org-1:vEZlmbOsmTXkmEi4DSdqNVyq25VPNpmSm6qCs4IuTgE="
    ];
  };

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;
  };

  outputs = inputs@{ flake-parts, treefmt-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      imports = [
        treefmt-nix.flakeModule
        # ./nixos
        # ./dummy-contract
      ];
      perSystem = { self', inputs', pkgs, lib, ... }:
        let
          # nightly-2023-03-25: https://github.com/casper-network/casper-node/blob/release-2.0.0-rc4/smart_contracts/rust-toolchain
          toolchainAttrs = { channel = "nightly"; date = "2023-03-25"; sha256 = "sha256-vWMW7tpbU/KseRztVYQ6CukrQWJgPgtlFuB6OPoZ/v8="; };
          rustToolchain = with inputs'.fenix.packages; combine [
            (toolchainOf toolchainAttrs).toolchain
            (targets.wasm32-unknown-unknown.toolchainOf toolchainAttrs).rust-std
          ];
          # rustToolchain = with inputs'.fenix.packages; combine [
          #   stable.toolchain
          #   targets.wasm32-unknown-unknown.stable.rust-std
          # ];
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;

          packageAttrs = {
            pname = "casper-event-standard";

            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./casper-event-standard-macro
                ./casper-event-standard
                ./integration-tests
              ];
            };

            nativeBuildInputs = [ pkgs.pkg-config ];
            buildInputs = with pkgs; [
              openssl.dev
            ] ++ lib.optionals stdenv.isDarwin [
              libiconv
              darwin.apple_sdk.frameworks.Security
              darwin.apple_sdk.frameworks.SystemConfiguration
            ];

            # the coverage report will run the tests
            doCheck = false;
          };
        in
        {
          devShells.default = pkgs.mkShell {
            inputsFrom = [ self'.packages.default ];
          };

          packages = {
            casper-event-standard-deps = craneLib.buildDepsOnly packageAttrs;

            casper-event-standard-docs = craneLib.cargoDoc (packageAttrs // {
              cargoArtifacts = self'.packages.casper-event-standard-deps;
            });

            casper-event-standard = craneLib.buildPackage (packageAttrs // {
              cargoArtifacts = self'.packages.casper-event-standard-deps;
            });

            default = self'.packages.casper-event-standard;
          };

          checks = {
            lint = craneLib.cargoClippy (packageAttrs // {
              cargoArtifacts = self'.packages.casper-event-standard-deps;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

            coverage-report = craneLib.cargoTarpaulin (packageAttrs // {
              cargoArtifacts = self'.packages.casper-event-standard-deps;
            });
          };

          treefmt = {
            projectRootFile = ".git/config";
            programs.nixpkgs-fmt.enable = true;
            programs.rustfmt.enable = true;
            programs.rustfmt.package = craneLib.rustfmt;
            settings.formatter = { };
          };
        };
      flake = {
        herculesCI.ciSystems = [ "x86_64-linux" ];
      };
    };
}
