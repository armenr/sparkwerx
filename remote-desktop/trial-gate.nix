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
      # Build all ordinary test prerequisites before sudo, without trying to
      # run the privileged container lifecycle through the normal user daemon.
      fixture = trial.fixture;
      network_test = trial.networkTest;
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
  # The gate imports source modules as root before starting the container test.
  text = ''exec python3 -B ${./trial-gate.py} --manifest ${manifest} "$@"'';
}
