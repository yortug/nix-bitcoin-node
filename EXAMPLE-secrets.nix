{
  hostname = "FILL_THIS_IN";
  username = "FILL_THIS_IN";
  wifi_ssid = "FILL_THIS_IN";
  #wifi_psk = "FILL_THIS_IN";
  wifi_psk_hashed = "FILL_THIS_IN";  # generated via: `wpa_passphrase "YOUR_SSID" "YOUR_PSK"`
  user_password_hashed = "FILL_THIS_IN";  # generated via: `mkpasswd -m sha-512 passwordgoeshere`
  btc_rpc_username = "FILL_THIS_IN";
  btc_rpc_password_hashed = "FILL_THIS_IN";  # generated via: `rpcauth.py` (comes from bitcoin repo)
  datum_mining_address = "FILL_THIS_IN";  # reserved bc1 address for reward
  datum_coinbase_primary = "FILL_THIS_IN";  # `miner` assosciated with block if you hit (ignored when pooled)
  datum_coinbase_secondary = "FILL_THIS_IN";  # `user` assosciated with block if you hit
  git_email = "FILL_THIS_IN";
  git_user = "FILL_THIS_IN";
}
