{ pkgs }:
let
  source = pkgs.runCommand "sparkwerx-moonlight-report-source" { } ''
    mkdir -p "$out"
    cp ${./trial-report.py} "$out/trial-report.py"
    cp ${./trial-metrics.py} "$out/trial-metrics.py"
    cp ${./inspect-session.py} "$out/inspect-session.py"
  '';
  policy =
    pkgs.runCommand "sparkwerx-moonlight-report-policy" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        mkdir -p tree/remote-desktop tree/dev "$out"
        cp ${source}/trial-report.py tree/remote-desktop/trial-report.py
        cp ${source}/trial-metrics.py tree/remote-desktop/trial-metrics.py
        cp ${source}/inspect-session.py tree/remote-desktop/inspect-session.py
        cp ${../dev/test_moonlight_report.py} tree/dev/test_moonlight_report.py
        python3 -B -m unittest discover -s tree/dev
        touch "$out/passed"
      '';
in
{
  inherit policy;
  package = pkgs.writeShellApplication {
    name = "sparkwerx-moonlight-report";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      test -e ${policy}/passed
      exec python3 -B ${source}/trial-report.py "$@"
    '';
  };
}
