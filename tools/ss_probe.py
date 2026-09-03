#!/usr/bin/env python3
"""ss_probe — sonde console independante pour le lien serie SilverSprint.

N'a AUCUN code commun avec ss_emu : c'est le principe meme d'un temoin. Elle
ouvre un port serie, mene le handshake de docs/01 §4, lance une course et
affiche les ticks en direct, avec le watchdog 500 ms de docs/01 §6.2.

Ce n'est PAS l'outil du jalon J1 : celui-ci devra passer par le GDExtension,
donc exercer le code reellement embarque. Cette sonde est un temoin croise,
utile pour departager un bug du driver d'un bug du materiel.

Usage :
  ss_probe.py <port> [--duration S] [--mode distance|temps] [--metres N]
"""

import argparse
import os
import re
import sys
import termios
import time

BAUD = termios.B115200
RE_R = re.compile(rb"^R:(\d+),(\d+),(\d+),(\d+),(\d+)$")
RE_FINISH = re.compile(rb"^([0-3])F:(\d+)$")
ROLLER_MM = 114.3
CIRC_MM = ROLLER_MM * 3.141592653589793
# Rafraichissement de la ligne d'etat, en secondes. La boucle tourne a 50 Hz ;
# repeindre a cette cadence fait scintiller un terminal et gonfle la sortie
# redirigee. Meme valeur que `ss_monitor.REFRESH_S`.
REFRESH_S = 0.1


def open_port(path):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    iflag, oflag, cflag, lflag, ispeed, ospeed, cc = attrs
    # Mode brut : aucune traduction, aucun echo, sinon le protocole est fausse.
    iflag = 0
    oflag = 0
    lflag = 0
    cflag = termios.CS8 | termios.CREAD | termios.CLOCAL
    cc = list(cc)
    cc[termios.VMIN] = 0
    cc[termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, [iflag, oflag, cflag, lflag, BAUD, BAUD, cc])
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


class Link:
    """Lecteur de lignes tolerant : trames coupees, octets non-UTF-8, \\r\\n."""

    def __init__(self, path):
        self.path = path
        self.fd = None
        self.buf = bytearray()
        self.unknown = 0

    def open(self):
        self.fd = open_port(self.path)
        self.buf.clear()

    def close(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None

    def send(self, text):
        os.write(self.fd, text.encode("ascii"))

    def poll(self):
        """Rend la liste des lignes completes recues. Leve OSError si le lien tombe."""
        try:
            chunk = os.read(self.fd, 4096)
        except BlockingIOError:
            return []
        except OSError:
            raise
        if chunk:
            self.buf.extend(chunk)
        lines = []
        while True:
            i = self.buf.find(b"\r\n")
            if i < 0:
                break
            lines.append(bytes(self.buf[:i]))
            del self.buf[: i + 2]
        return lines


def handshake(link, tries=3, timeout=2.0, send_stop=True):
    """docs/01 §4 : `s` puis `v`, attente de V:SS_v..., 3 essais, timeout 2 s.

    send_stop=False lors d'une reconnexion en pleine course : le `s` du
    handshake initial abattrait la course qu'on vient tout juste de recuperer.
    """
    for attempt in range(1, tries + 1):
        if send_stop:
            link.send("s\n")
        link.send("v\n")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in link.poll():
                if line.startswith(b"V:"):
                    return line[2:].decode("ascii", "replace")
            time.sleep(0.005)
        print(f"  essai {attempt}/{tries} : pas de V: sous {timeout} s")
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("--duration", type=float, default=20.0)
    ap.add_argument("--mode", choices=["distance", "temps"], default="distance")
    ap.add_argument("--metres", type=float, default=100.0)
    args = ap.parse_args()

    link = Link(args.port)
    link.open()

    print(f"port            : {args.port}")
    version = handshake(link)
    if version is None:
        print("ECHEC : aucune reponse V: — ce port n'est pas le boitier.")
        return 1
    print(f"firmware        : {version}")
    print("etat            : IDENTIFIED  (seul etat ou START est autorise)")

    if args.mode == "distance":
        ticks = int(args.metres * 1000 / CIRC_MM)
        assert 1 <= ticks <= 32767, "hors bornes docs/01 §2"
        link.send("d\n")
        link.send(f"l{ticks}\n")
        print(f"course          : distance, {args.metres:g} m = {ticks} ticks")
    else:
        link.send("x\n")
        link.send("t60\n")  # constante sure, docs/01 §5.5
        print("course          : temps, t60 envoye (constante sure)")
    link.send("g\n")
    print("depart demande, decompte en cours\n")

    start = time.monotonic()
    last_r = None
    link_lost = False
    ticks = [0, 0, 0, 0]
    elapsed_ms = 0
    events = []
    reconnect_at = None

    last_paint = 0.0
    finishes = 0
    while time.monotonic() - start < args.duration:
        now = time.monotonic()
        lines = []
        if link.fd is not None:
            try:
                lines = link.poll()
            except OSError as exc:
                if not link_lost:
                    events.append(f"[{now - start:6.2f}s] LIEN COUPE ({exc.strerror})")
                    link_lost = True
                link.close()
                reconnect_at = now + 1.0

        # docs/01 §6.4 : rescan a 1 Hz tant que le lien est absent.
        if link.fd is None and reconnect_at is not None and now >= reconnect_at:
            try:
                link.open()
            except OSError:
                reconnect_at = now + 1.0
            else:
                # Reconnexion en pleine course : `v` seul, JAMAIS `s`.
                ver = handshake(link, tries=1, timeout=0.5, send_stop=False)
                if ver is None:
                    events.append(f"[{now - start:6.2f}s] port rouvert mais pas de V:, on ferme")
                    link.close()
                    reconnect_at = now + 1.0
                else:
                    events.append(
                        f"[{now - start:6.2f}s] RECONNECTE sur {args.port}, firmware {ver}"
                    )
                    reconnect_at = None
                    last_r = now

        for line in lines:
            m = RE_R.match(line)
            if m:
                ticks = [int(g) for g in m.groups()[:4]]
                elapsed_ms = int(m.group(5))
                last_r = now
                if link_lost:
                    events.append(f"[{now - start:6.2f}s] LIEN RETABLI, flux R: repris")
                    link_lost = False
                continue
            if line.startswith(b"CD:"):
                events.append(f"[{now - start:6.2f}s] decompte {line.decode()}")
            elif RE_FINISH.match(line):
                finishes += 1
                events.append(f"[{now - start:6.2f}s] arrivee {line.decode()}")
            elif line.startswith(b"FS:"):
                events.append(f"[{now - start:6.2f}s] FAUX DEPART {line.decode()}")
            elif line.startswith(b"L:") or line.startswith(b"M:"):
                events.append(f"[{now - start:6.2f}s] ack {line.decode()}")
            else:
                link.unknown += 1
                events.append(
                    f"[{now - start:6.2f}s] TRAME INCONNUE (loggee, pas levee) : {line!r}"
                )

        # Watchdog docs/01 §6.2 : 500 ms sans R: pendant une course.
        # Un silence prolonge n'est pas forcement une deconnexion — le firmware
        # peut simplement s'etre fige. On bascule en LINK_LOST dans les deux
        # cas, mais on ne referme le port qu'au bout d'une seconde de silence,
        # pour laisser un gel se resorber tout seul.
        if last_r is not None and not link_lost and now - last_r > 0.5:
            events.append(
                f"[{now - start:6.2f}s] LINK_LOST — {(now - last_r) * 1000:.0f} ms sans R:"
            )
            link_lost = True
        if link_lost and link.fd is not None and now - last_r > 1.0 and reconnect_at is None:
            events.append(f"[{now - start:6.2f}s] silence prolonge, on referme et on rescanne")
            link.close()
            reconnect_at = now + 0.5

        while events:
            print(events.pop(0))
        # La ligne d'etat vit sur stderr : sinon elle ecrase les evenements de
        # stdout, qui sont la trace exploitable.
        #
        # REPEINTE A 10 Hz, pas a chaque tour de boucle. La boucle tourne a
        # 50 Hz : la ligne scintillait sur un terminal, et une sonde de vingt
        # secondes redirigee dans un fichier produisait cinquante-sept
        # kilo-octets. Meme correctif que `ss_monitor`.
        if now - last_paint >= REFRESH_S:
            last_paint = now
            dist = [t * CIRC_MM / 1000.0 for t in ticks]
            sys.stderr.write(
                f"\r  {elapsed_ms / 1000:6.2f}s "
                + "  ".join(f"P{i}:{ticks[i]:4d}t {dist[i]:6.1f}m" for i in range(2))
                + ("   [LIEN COUPE]" if link_lost else "              ")
            )
            sys.stderr.flush()
        time.sleep(0.02)

    sys.stderr.write("\n")
    print(f"trames inconnues : {link.unknown}")
    print(f"arrivees vues    : {finishes}")
    link.close()
    # UNE SONDE QUI N'A RIEN VU NE DOIT PAS DIRE « OK ». Elle arme une course et
    # attend ses `<i>F:` ; n'en voir aucune est le symptome meme qu'on vient
    # chercher — boitier muet, mauvais port, firmware different. Sortir a zero
    # en l'annoncant ferait passer un chemin casse pour un chemin verifie.
    if finishes == 0:
        print("ECHEC : aucune arrivee pendant la fenetre demandee.")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
