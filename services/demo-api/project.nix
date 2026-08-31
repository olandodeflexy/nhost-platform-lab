{ pkgs
, version ? "dev"
, commit ? "unknown"
}:

pkgs.buildGoModule {
  pname = "demo-api";
  inherit version;

  src = ./.;
  vendorHash = null;
  subPackages = [ "cmd/demo-api" ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Version=${version}"
    "-X=github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Commit=${commit}"
    "-X=github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.BuildTime=reproducible"
  ];

  doCheck = true;
}
