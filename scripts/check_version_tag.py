#!/usr/bin/env python3
"""Vérifie qu'un tag de release porte la version déclarée dans `project.godot`.

Pourquoi ce script existe : les archives de release sont nommées d'après le
tag (`v0.9.1` → `…-0.9.1-…zip`), tandis que le titre de la fenêtre et le JSON
de course lisent `application/config/version` dans `project.godot`. Un tag
posé sans avoir relevé la version du projet publie un logiciel qui se
contredit — et c'est le JSON, envoyé au développeur, qui mentirait sur son
build. Ce contrôle transforme ce cas en échec de release, avant l'export.

Usage : check_version_tag.py --tag v0.9.0-beta [--project project.godot]
Code 0 si le tag (sans son `v`) est la version du projet, 1 sinon.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def project_version(path: pathlib.Path) -> str:
    match = re.search(r'^config/version="([^"]*)"', path.read_text(encoding="utf-8"), re.M)
    if match is None:
        sys.exit("%s : aucune ligne config/version" % path)
    return match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, help="le tag git, par exemple v0.9.0-beta")
    parser.add_argument("--project", default=str(ROOT / "project.godot"))
    args = parser.parse_args()
    tagged = args.tag[1:] if args.tag.startswith("v") else args.tag
    declared = project_version(pathlib.Path(args.project))
    if tagged != declared:
        print(
            "version du tag %s : « %s » ; project.godot : « %s » — relever config/version"
            " avant de taguer, ou retaguer" % (args.tag, tagged, declared)
        )
        return 1
    print("tag %s : version %s, celle de project.godot" % (args.tag, declared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
