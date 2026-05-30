# 在 shell 中 source 此文件，或加入 ~/.bashrc
export PATH="$HOME/.local/node/bin:$HOME/.local/npm-global/bin:$PATH"
if [[ -f "$HOME/google-cloud-sdk/path.bash.inc" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/google-cloud-sdk/path.bash.inc"
fi
