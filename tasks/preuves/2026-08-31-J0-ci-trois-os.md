# Preuve — Jalon **J0** franchi

**Date** 2026-08-31 · **Run CI** [33390935079](https://github.com/pata27/SilverSprint-v3/actions/runs/33390935079) · commit `43e4a1e`

`docs/05` lot 0 : *« `godot --headless --script tests/run.gd` sort en code 0 dans la CI, sur les trois OS. »*

## Résultat — 7 jobs, 3 OS, tous verts

```
✓ Lint GDScript                        9s
✓ Tests C++ (ubuntu-latest)           33s
✓ Tests C++ (macos-latest)            28s
✓ Tests C++ (windows-latest)          45s
✓ Tests headless Godot (ubuntu-latest) 21s
✓ Tests headless Godot (macos-latest)  28s
✓ Tests headless Godot (windows-latest) 45s
```

`gh run watch --exit-status` sort en **0**.

## Extraits

Suite Godot headless, ubuntu :

```
Godot Engine v4.5.stable.official.876b29033
  GUT version:  9.6.1
  res://tests/unit/test_smoke.gd
    * test_la_chaine_headless_fonctionne
    * test_les_constantes_physiques_de_docs_01_sont_coherentes
  2/2 passed.
  ---- All tests passed! ----
```

Tests C++ natifs, windows (MSVC) — ils ne lancent pas Godot :

```
1/1 Test #1: ss_emu_tests .....................   Passed    0.62 sec
100% tests passed out of 1
```

soit les **50 cas doctest / 309 assertions** de l'émulateur, compilés et exécutés sous MSVC,
clang/AppleClang et GCC.

## Vérification du runner lui-même

Un runner qui sort toujours en 0 ne prouve rien. Contrôlé localement en ajoutant un test qui
échoue volontairement, puis en le retirant :

```
succes -> exit=0
echec  -> exit=1
```

## Commande reproductible

```sh
./.tools/Godot_v4.5-stable_linux.x86_64 --headless --import
./.tools/Godot_v4.5-stable_linux.x86_64 --headless --script tests/run.gd ; echo $?
```
