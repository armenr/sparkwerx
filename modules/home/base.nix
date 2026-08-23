{ pkgs, ... }:
{
  programs.home-manager.enable = true;
  xdg.enable = true;

  # Keep the first activation intentionally small. Additional tools will be
  # grouped into role modules after the baseline is accepted.
  home.packages = with pkgs; [
    fd
    jq
    ripgrep
  ];
}
