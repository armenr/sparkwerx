{ pkgs }:
let
  pin = builtins.fromJSON (builtins.readFile ./source.json);
  workerSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/gpustack/gpustack/${pin.sourceRevision}/gpustack/worker/worker.py";
    hash = pin.workerSourceHash;
  };
  collectorSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/gpustack/gpustack/${pin.sourceRevision}/gpustack/worker/collector.py";
    hash = pin.collectorSourceHash;
  };
  privateCollector = pkgs.runCommand "gpustack-gb10-collector-${pin.version}" { } ''
    ${pkgs.python3}/bin/python3 ${./patch-collector.py} ${collectorSource} "$out"
  '';
  privateWorker = pkgs.runCommand "gpustack-private-worker-${pin.version}" { } ''
    cp ${workerSource} "$out"
    substituteInPlace "$out" \
      --replace-fail 'self._address = "0.0.0.0"' 'self._address = cfg.host or "127.0.0.1"'
  '';
in
pkgs.writeShellScriptBin "gpustack-spark" ''
  export SPARK_GPUSTACK_PIN=${./source.json}
  export SPARK_GPUSTACK_MODELS=${./models.json}
  export SPARK_GPUSTACK_WORKER=${privateWorker}
  export SPARK_GPUSTACK_COLLECTOR=${privateCollector}
  exec ${pkgs.python3}/bin/python3 ${./control.py} "$@"
''
