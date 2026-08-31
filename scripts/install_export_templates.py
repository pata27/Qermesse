#!/usr/bin/env python3
"""Installe les modeles d'exportation Godot depuis une archive .tpz.

Sorti du workflow parce qu'un heredoc Python imbrique dans un bloc YAML herite
de l'indentation du YAML et casse l'indentation Python. Ici, le script est
lisible, testable, et le workflow se contente de l'appeler.

    python scripts/install_export_templates.py templates.tpz 4.5.stable
"""

import argparse
import os
import pathlib
import platform
import sys
import zipfile


def templates_root() -> pathlib.Path:
    """Emplacement ou Godot cherche ses modeles, par systeme."""
    system = platform.system()
    if system == "Windows":
        base = os.environ.get("APPDATA")
        if not base:
            raise RuntimeError("APPDATA introuvable")
        return pathlib.Path(base) / "Godot" / "export_templates"
    if system == "Darwin":
        return pathlib.Path.home() / "Library" / "Application Support" / "Godot" / "export_templates"
    return pathlib.Path.home() / ".local" / "share" / "godot" / "export_templates"


def install(archive: pathlib.Path, version: str, root: pathlib.Path | None = None) -> pathlib.Path:
    target = (root or templates_root()) / version
    target.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(archive) as bundle:
        members = [name for name in bundle.namelist() if not name.endswith("/")]
        if not members:
            raise RuntimeError(f"{archive} ne contient aucun fichier")
        for member in members:
            # Le .tpz range tout sous un dossier `templates/` ; Godot attend les
            # fichiers a plat dans <version>/.
            flat = member.split("/", 1)[1] if "/" in member else member
            if not flat:
                continue
            (target / flat).write_bytes(bundle.read(member))
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("version", help="par exemple 4.5.stable")
    parser.add_argument("--root", type=pathlib.Path, default=None)
    args = parser.parse_args()

    if not args.archive.is_file():
        print(f"archive introuvable : {args.archive}", file=sys.stderr)
        return 2

    target = install(args.archive, args.version, args.root)
    count = len(list(target.iterdir()))
    print(f"{count} modeles installes dans {target}")
    # Un .tpz complet contient une trentaine de fichiers ; en dessous, quelque
    # chose s'est mal passe et l'export echouerait plus loin, moins clairement.
    if count < 5:
        print("ECHEC : trop peu de modeles installes", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
