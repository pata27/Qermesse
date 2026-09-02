#!/usr/bin/env python3
"""Vérifie qu'un module natif construit est CHARGEABLE et expose son point d'entrée.

Pourquoi ce script existe : un GDExtension qui compile mais ne se charge pas ne
fait échouer ni la compilation, ni l'export. Godot démarre, la scène tourne, et
seul le lien série manque — une release « muette » côté boîtier, découverte en
soirée. Ce contrôle transforme ce cas en échec de CI, avant l'export.

Portable : `ctypes` charge une bibliothèque partagée sur Linux, Windows et
macOS, et la résolution du symbole vaut `nm`, `dumpbin` et `otool` à la fois.

Usage : check_extension_binary.py [--target template_release] [--symbol NOM]
"""
import argparse
import ctypes
import pathlib
import sys

BIN_DIR = pathlib.Path(__file__).resolve().parent.parent / "addons" / "serial_link" / "bin"
DEFAULT_SYMBOL = "serial_link_library_init"


def candidates(target: str):
    """Fichiers (pas dossiers) du module pour la cible : .so, .dll, ou le binaire
    à l'intérieur d'un .framework macOS."""
    for path in sorted(BIN_DIR.rglob("*")):
        if path.is_file() and target in path.name and not path.suffix in {".a", ".lib", ".exp"}:
            yield path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="template_release")
    parser.add_argument("--symbol", default=DEFAULT_SYMBOL)
    args = parser.parse_args()

    found = list(candidates(args.target))
    if not found:
        print(f"ECHEC : aucun binaire '{args.target}' dans {BIN_DIR}", file=sys.stderr)
        return 1

    failures = 0
    for path in found:
        try:
            library = ctypes.CDLL(str(path))
            getattr(library, args.symbol)
        except (OSError, AttributeError) as error:
            print(f"ECHEC : {path.name} — {error}", file=sys.stderr)
            failures += 1
            continue
        print(f"ok : {path.name} charge, symbole '{args.symbol}' resolu")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
