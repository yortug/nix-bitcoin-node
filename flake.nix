{
  description = "yort's first nixos attempt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # grab datum-gateway source below, need to change commit hash when updated
    datum-src = {
      #url = "git+https://github.com/OCEAN-xyz/datum_gateway.git?rev=5b061233a3d3323771b2be98e17f543e59346619";
      url = "git+https://github.com/yortug/datum_gateway.git?rev=eb63a28bc9634052fb6b9218b511939141a2c500";
      flake = false;
    };
    # grab bip-110 specific pre-release source below, need to change commit hash when updated
    nixpkgs-bip110.url = "github:NixOS/nixpkgs/pull/482673/head";
    joinmarket-src = {
      url = "github:JoinMarket-Org/joinmarket-clientserver/v0.9.11";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, datum-src, nixpkgs-bip110, joinmarket-src, ... }@inputs: let
      secrets = import ./secrets.nix;
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};

      datum = pkgs.stdenv.mkDerivation rec {
        pname = "datum_gateway";
        version = "0.4.0beta";  # Matches tag for easy tracking.
        src = datum-src;
        nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];  
        buildInputs = with pkgs; [ curl jansson libsodium libmicrohttpd ];
        preConfigure = ''
          export NIX_CFLAGS_COMPILE="-DJSON_INTEGER_IS_LONG_LONG=1 $NIX_CFLAGS_COMPILE"
        '';
        buildPhase = "cmake . && make";
        installPhase = ''
          install -Dm755 datum_gateway $out/bin/datum_gateway
        '';
      };

    joinmarket = pkgs.stdenv.mkDerivation rec {
        pname = "joinmarket";
        version = "0.9.11";
        src = joinmarket-src;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        buildInputs = [
          (pkgs.python312.withPackages (ps: with ps; [twisted txtorcon pyopenssl service-identity autobahn pyaes pycryptodomex pyjwt requests urllib3 chardet certifi idna matplotlib]))
        ];

        installPhase = ''
        runHook preInstall

        libdir=$out/lib/joinmarket
        mkdir -p $libdir
        cp -r jm* scripts/*.py $libdir/   # ← files are here (no $sourceRoot needed)

        mkdir -p $out/bin
        for script in scripts/*.py; do
          base=$(basename "$script" .py)
          makeWrapper ${pkgs.python312}/bin/python "$out/bin/jm-$base" \
            --add-flags "$libdir/$base.py" \
            --prefix PYTHONPATH : "$libdir"
        done

        # ob-watcher
        obw=$out/lib/joinmarket-ob-watcher
        mkdir -p $obw
        cp scripts/obwatch/ob-watcher.py "$obw/ob-watcher"
        cp -r scripts/obwatch/{orderbook.html,sybil_attack_calculations.py,vendor} "$obw/"
        makeWrapper ${pkgs.python312}/bin/python "$out/bin/jm-ob-watcher" \
          --add-flags "$obw/ob-watcher" \
          --prefix PYTHONPATH : "$libdir"

        runHook postInstall
        '';
      };
      
    in {
      packages = {
        ${system} = {
          datum = datum;
          joinmarket = joinmarket;
        };
      };
      
      nixosConfigurations."${secrets.hostname}" = nixpkgs.lib.nixosSystem {
        pkgs = nixpkgs.legacyPackages.${system};
        specialArgs = { inherit datum joinmarket; };
        modules = [
          ./configuration.nix
          {
            nixpkgs.overlays = [
              (final: prev: {
                bitcoin-knots-bip110 = nixpkgs-bip110.legacyPackages.${prev.stdenv.hostPlatform.system}.bitcoin-knots-bip110;
              })
            ];
          }
        ];
      };
    };
}
