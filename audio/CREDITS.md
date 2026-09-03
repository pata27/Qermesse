# Sons enregistrés — sources et licences

Presque toute la bande-son est **synthétisée** (`sound_forge.gd`, `music_forge.gd`) : rien à
télécharger, rien à perdre à l'export, et surtout tout ce qui doit SUIVRE la course — les rouleaux
dont la hauteur suit la vitesse, la nappe qui monte avec l'intensité, les trois couches de musique
qui doivent boucler en phase — ne peut pas être un échantillon figé.

Trois sons font exception, et ce sont exactement les trois que la synthèse rend mal : une foule est
faite de centaines de voix corrélées, une cloche est une géométrie de bronze. Les approcher en code
donnait, de l'aveu de l'écoute, « du bruit blanc » et « plein de bips ». Ils viennent donc
d'enregistrements réels, choisis **sans clause de partage à l'identique** pour ne rien imposer à ce
projet ni à ce qu'on en distribue.

| Fichier | Source | Auteur | Licence | Modifications |
|---|---|---|---|---|
| `samples/cloche.ogg` | [20150323 SM Glocke 5](https://commons.wikimedia.org/wiki/File:20150323_SM_Glocke_5.ogg) — Wikimedia Commons | Wikimedia Commons | **CC0 1.0** (domaine public) | Extrait 28,0 → 32,4 s ; **accéléré ×2,33** — bande magnétique, hauteur et tempo ensemble — pour passer d'un bourdon d'église à une sonnerie de piste ; mono ; fondus ; normalisé à −1 dBFS ; Vorbis q5 |
| `samples/clameur.ogg` | [Slow starting applause](https://commons.wikimedia.org/wiki/File:Slow_starting_applause.ogg) — Wikimedia Commons | stephan | **Domaine public** | Extrait 20,0 → 25,5 s, là où la salle est à plein régime ; mono ; fondus ; normalisé à −1 dBFS ; Vorbis q5 |
| `samples/reaction.ogg` | [Slow starting applause](https://commons.wikimedia.org/wiki/File:Slow_starting_applause.ogg) — Wikimedia Commons | stephan | **Domaine public** | Extrait 26,5 → 27,8 s ; mono ; fondus ; normalisé à −1 dBFS ; Vorbis q5 |

### Ce qui a été essayé et écarté

[Ohhh ahhh](https://commons.wikimedia.org/wiki/File:Ohhh_ahhh.ogg) (starlite, domaine public) servait
d'abord de réaction en course, et se mêlait à la clameur d'arrivée. À l'écoute, ce n'est pas une
clameur : c'est un « ohhhh » collectif de **déception**, celui d'une salle qui voit rater quelque
chose. Lancé toutes les quelques secondes pendant une course, il la rendait franchement lugubre.
Retiré des deux. La leçon vaut d'être notée : un enregistrement au titre juste peut porter une
émotion exactement contraire à celle qu'on cherche, et cela ne se voit sur aucune mesure.

## La règle qu'on s'impose

**Aucune clause de partage à l'identique.** CC0, domaine public ou CC-BY, jamais CC BY-SA : une
clause SA suivrait le fichier modifié dans toute distribution, et cela ne se décide pas au détour
d'un choix de bruitage. La plupart des enregistrements de cloche et de foule de Wikimedia Commons
sont en CC BY-SA — ils ont été écartés pour cette seule raison, y compris quand ils sonnaient
mieux.

**Les fichiers sont versionnés dans le dépôt**, convertis en Vorbis mono (122 Ko au total). Rien
n'est téléchargé pour construire : la règle de reproductibilité du projet tient toujours, elle
portait sur le BUILD, pas sur l'origine des sons.

**Tout est réutilisable sans citer personne** — les trois fichiers sont CC0 ou domaine public.
Ce tableau existe quand même : savoir d'où vient un son, et ce qu'on lui a fait, est ce qui permet
de le refaire.
