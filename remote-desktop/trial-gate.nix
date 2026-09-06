{
  pkgs,
  trial,
  lifecycle,
}:
let
  manifest = pkgs.writeText "sparkwerx-moonlight-trial-gate.json" (
    builtins.toJSON {
      source = trial.source;
      bundle = trial.bundle;
      tools = trial.manifest;
      policy = trial.policy;
      # Identity only, not a realization dependency. Keeping a derivation's
      # output context here would build the privileged test (and its build-time
      # closure) during an ordinary user package build. The front door evaluates
      # this exact recipe immediately before sudo; missing recipes fail closed.
      test_drv = builtins.unsafeDiscardStringContext lifecycle.drvPath;
      test_output = builtins.unsafeDiscardStringContext lifecycle.outPath;
    }
  );
in
pkgs.writeShellApplication {
  name = "sparkwerx-moonlight-trial-gate";
  runtimeInputs = [ pkgs.python3 ];
  text = ''exec python3 ${./trial-gate.py} --manifest ${manifest} "$@"'';
}
