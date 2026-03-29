{ lib, stdenvNoCC, makeWrapper, fzf, gum, jq, nix-search-tv }:

stdenvNoCC.mkDerivation rec {
  pname = "nixdash";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    install -Dm755 nixdash.sh $out/bin/nixdash
    mkdir -p $out/lib
    cp lib/*.sh $out/lib/
    install -Dm644 completions/_nixdash $out/share/zsh/site-functions/_nixdash
  '';

  postFixup = ''
    wrapProgram $out/bin/nixdash \
      --prefix PATH : ${lib.makeBinPath [ fzf gum jq nix-search-tv ]}
  '';

  meta = with lib; {
    description = "TUI for managing Nix packages";
    homepage = "https://github.com/AThevon/nixdash";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "nixdash";
  };
}
