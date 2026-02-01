# ./pkgs/joinmarket.nix
{ pkgs, joinmarket-src, old-nixpkgs, secp256k1 }:

let


pkgs-old = import old-nixpkgs { system = pkgs.system; };

chromalog = pkgs-old.python3Packages.buildPythonPackage rec { 
  pname = "chromalog";
  version = "1.0.5";

  format = "setuptools";

  src = pkgs.fetchFromGitHub {
    owner = "freelan-developers";
    repo = "chromalog";
    rev = version;
    hash = "sha256-4CYfyM7aX12oLES9h/4liKVcmEi+IJn/5Jvyl0XRRF4=";
  };

  propagatedBuildInputs = with pkgs-old.python3Packages; [ colorama future six ];

  doCheck = false;

};


python-bitcointx = pkgs-old.python3Packages.buildPythonPackage rec { 
  pname = "python-bitcointx";
  version = "1.1.5";
  format = "setuptools";

  src = pkgs.fetchFromGitHub {
    owner = "Simplexum";
    repo = "python-bitcointx";
    rev = "python-bitcointx-v${version}";
    hash = "sha256-KXndYEsJ8JRTiGojrKXmAEeGDlHrNGs5MtYs9XYiqMo=";
  };
  doCheck = false;
  patchPhase = ''
  for path in core/secp256k1.py tests/test_load_secp256k1.py; do
    substituteInPlace "bitcointx/$path" \
      --replace-fail "ctypes.util.find_library('secp256k1')" "'${secp256k1}/lib/libsecp256k1.so'"
  done
'';

};


bencoder-pyx = pkgs-old.python3Packages.buildPythonPackage rec {
    pname = "bencoder.pyx";
    version = "3.0.1";

    format = "setuptools";

    src = pkgs.fetchurl {
      url = "https://github.com/whtsky/bencoder.pyx/archive/9a47768f3ceba9df9e6fbaa7c445f59960889009.tar.gz";
      hash = "sha256-nzIDtvz/2Io66Kwha4z9S+qLmAJIVyd7IhauJXsxBfo=";
    };

    nativeBuildInputs = with pkgs-old.python3Packages; [
      cython
    ];

    doCheck = false;

  };


  autobahn = pkgs-old.python3Packages.buildPythonPackage rec {
    pname = "autobahn";
    version = "20.12.3";  # pinned older version from nix-bitcoin's autobahn.nix
    format = "setuptools";
    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-QQqT4OKYgsi11asF0iCwdgm4hu9fI8C405FTJU/9aJU=";
    };
    propagatedBuildInputs = with pkgs-old.python3Packages; [ twisted cryptography ];
    doCheck = false;
  };


in

pkgs-old.python3Packages.buildPythonApplication rec {
  pname = "joinmarket";
  version = "0.9.11";

  format = "pyproject";

  src = joinmarket-src;

  # Patch dependency pins so we can use nixpkgs' current versions
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'cryptography==41.0.6' 'cryptography>=41' \
      --replace-fail 'twisted==23.10.0'     'twisted>=23'     \
      --replace-fail 'service-identity==21.1.0' 'service-identity>=21' \
      --replace-fail 'txtorcon==23.11.0'    'txtorcon>=23'    \
      || true  # in case some lines are missing in future commits
  '';

  propagatedBuildInputs = with pkgs-old.python3Packages; [
    # Core runtime deps (from JoinMarket + nix-bitcoin's list)
    twisted
    python-bitcoinlib
    python-bitcointx
    pycryptodomex
    pyopenssl
    libnacl
    coincurve
    matplotlib
    scipy
    numpy
    pandas
    seaborn
    requests
    urllib3
    certifi
    charset-normalizer
    idna
    service-identity
    txtorcon

    # Extras commonly needed (from nix-bitcoin + runtime testing)
    chromalog      # colored logging (packaged in nix-bitcoin)
    argon2-cffi
    autobahn
    bencoder-pyx
    klein
    mnemonic
    pyjwt
    werkzeug
    qrcode
    pillow         # for qrcode
    txaio
  ];


nativeBuildInputs = with pkgs-old.python3Packages; [
  setuptools
  wheel
  pip
];

  # Skip tests (they need tor + bitcoind + miniircd setup)
  doCheck = false;
  
  pythonImportsCheck = [
    "jmbase"
    "jmbitcoin"
    "jmclient"
    "jmdaemon"
  ];
  
  makeWrapperArgs = [
    "--prefix PATH : ${pkgs-old.lib.makeBinPath [ pkgs-old.python3 ]}"
    "--set PYTHONPATH ${placeholder "out"}/${pkgs-old.python3.sitePackages}"
  ];

postInstall = ''
  mkdir -p $out/bin
  cpJm() {
    local src_file="scripts/$1"
    local dest_name="jm-''${1%.py}"
    cp "$src_file" "$out/bin/$dest_name"
  }
  cpJm add-utxo.py
  cpJm bond-calculator.py
  cpJm bumpfee.py
  cpJm genwallet.py
  cpJm receive-payjoin.py
  cpJm sendpayment.py
  cpJm sendtomany.py
  cpJm tumbler.py
  cpJm wallet-tool.py
  cpJm yg-privacyenhanced.py
  cp scripts/joinmarketd.py     "$out/bin/joinmarketd"     || true
  cp scripts/jmwalletd.py       "$out/bin/jmwalletd"       || true
  local obw="$out/libexec/joinmarket-ob-watcher"
  mkdir -p "$obw"
  cp scripts/obwatch/ob-watcher.py "$obw/ob-watcher"
  cp -r scripts/obwatch/{orderbook.html,sybil_attack_calculations.py,vendor} "$obw/" || true
  chmod +x "$out/bin/"* "$obw/ob-watcher" || true
  patchShebangs "$out/bin"
  patchShebangs "$obw"
  ln -s "$obw/ob-watcher" "$out/bin/jm-ob-watcher"
'';


}
