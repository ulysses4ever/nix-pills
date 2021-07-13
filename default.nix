{ pkgs ? import <nixpkgs> {}, revCount, shortRev }:
let
  lib = pkgs.lib;

  sources = let

      # We want nix examples, but not the top level nix to build things
      noTopLevelNix = path: type: let
          relPath = lib.removePrefix (toString ./. + "/") (toString path);
        in builtins.match "[^/]*\.nix" relPath == null;

      extensions = [ ".xml" ".txt" ".nix" ".bash" ];

    in lib.cleanSourceWith {
      filter = noTopLevelNix;
      src = lib.sourceFilesBySuffices ./. extensions;
    };

  combined = pkgs.runCommand "nix-pills-combined"
    {
      buildInputs = [ pkgs.libxml2 ];
      meta.description = "Nix Pills with as a single docbook file";
      inherit revCount shortRev;
    }
    ''
      cp -r ${sources} ./sources
      chmod -R u+w ./sources

      cd sources

      printf "%s-%s" "$revCount" "$shortRev" > version
      xmllint --xinclude --output $out ./book.xml
    '';

  toc = builtins.toFile "toc.xml"
    ''
      <toc role="chunk-toc">
        <d:tocentry xmlns:d="http://docbook.org/ns/docbook" linkend="book-nix-pills"><?dbhtml filename="index.html"?>
        </d:tocentry>
      </toc>
    '';

  manualXsltprocOptions = toString [
    "--param section.autolabel 1"
    "--param section.label.includes.component.label 1"
    "--stringparam html.stylesheet style.css"
    "--param xref.with.number.and.title 1"
    "--param toc.section.depth 3"
    "--stringparam admon.style ''"
    "--stringparam callout.graphics.extension .svg"
    "--stringparam current.docid nix-pills"
    "--param chunk.section.depth 0"
    "--param chunk.first.sections 1"
    "--param use.id.as.filename 1"
    "--stringparam generate.toc 'book toc appendix toc'"
    "--stringparam chunk.toc ${toc}"
  ];

in pkgs.stdenv.mkDerivation {
  name = "nix-pills";

  src = sources;
  buildInputs = with pkgs; [ jing libxslt fop ];

  installPhase = ''
    jing ${pkgs.docbook5}/xml/rng/docbook/docbook.rng $combined

    # Generate the HTML manual.
    dst=$out/share/doc/nix-pills
    mkdir -p $dst
    xsltproc \
      ${manualXsltprocOptions} \
      --nonet --output $dst/ \
      ${pkgs.docbook5_xsl}/xml/xsl/docbook/xhtml/chunk.xsl \
      ${combined}

    # Generate the PDF manual.
    xsltproc \
      ${manualXsltprocOptions} \
      --nonet --output $dst/nix-pills.fo \
      ${pkgs.docbook5_xsl}/xml/xsl/docbook/fo/docbook.xsl \
      ${combined}
    fop -fo $dst/nix-pills.fo -pdf $dst/nix-pills.pdf
    rm $dst/nix-pills.fo

    mkdir -p $dst/images
    cp -r ${pkgs.docbook5_xsl}/xml/xsl/docbook/images/callouts $dst/images/callouts

    cp ${./style.css} $dst/style.css

    mkdir -p $out/nix-support
    echo "nix-build out $out" >> $out/nix-support/hydra-build-products
    echo "doc nix-pills $dst" >> $out/nix-support/hydra-build-products
  '';
}
