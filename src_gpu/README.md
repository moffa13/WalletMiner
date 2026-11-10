# keybench (CUDA) — version GPU de ton benchmark de génération de clés

Portage GPU/CUDA du `Benchmark.cpp` CPU. Même pipeline, mêmes résultats :

```
priv (32o) → pubkey compressée (33o) → SHA256 → RIPEMD160
           → 0x00‖hash160 → double-SHA256 (checksum 4o) → base58
```

Le débit est mesuré en clés/s **sur le kernel seul** (cudaEvent), donc directement
comparable au chiffre du CPU.

## Fichiers

| Fichier | Rôle |
|---|---|
| `sha256.cuh` | SHA-256 mono-bloc (≤55 o), host+device, déroulé. |
| `ripemd160.cuh` | RIPEMD-160 host+device (portage de ton `ripemd160.c`). |
| `base58.cuh` | base58 de 25 o, host+device, sans `std::vector`/`std::array`. |
| `address.cuh` | `hash160_from_pubkey`, `address_from_pubkey`, `priv_to_address`. |
| `secp256k1_hook.cuh` | **Le seul endroit à brancher sur ta lib** (priv→pubkey). |
| `benchmark.cu` | kernel + harness + `--selftest`. |
| `Makefile` | cibles `stub`, `all`, `nobase58`, `selftest`. |

Tout sauf la secp256k1 est **validé bit-exact** contre ton vecteur de test
(`be63955…` → `1Dai8FBumerEYMzijW7hfMgD45HowqYzVP`) ; le binaire le revérifie
via `--selftest`.

## Démarrer tout de suite (sans ta lib)

```bash
make selftest            # valide le pipeline de hachage
make stub ARCH=sm_86     # mets ton archi (sm_89 pour RTX 40xx, etc.)
./keybench               # débit du pipeline avec une pubkey factice
./keybench --blocks 2048 --threads 256 --iters 1024
```

Le mode `stub` fabrique une fausse pubkey (pas de vraie courbe elliptique) : il
ne donne pas de vraies adresses, mais il exécute **tout le hachage** derrière.
C'est ton **plafond** : le débit que tu obtiendrais si la multiplication EC était
gratuite. Ça te dit tout de suite si tu seras limité par l'EC ou par le hachage.

## Brancher `nvidia-secp256k1`

Ouvre `secp256k1_hook.cuh` et remplis **une** fonction :

```cpp
__device__ bool secp_pubkey_compressed(const uint8_t priv[32], uint8_t pub33[33]);
```

- `priv` : scalaire 32 o **big-endian** (même ordre que le CPU).
- `pub33` : clé publique **compressée** — `pub33[0] = 0x02|0x03` selon la parité
  de `y`, `pub33[1..32] = x` big-endian.

Deux cas selon ce qu'expose ta lib (exemples complets dans le fichier) :

- **MODE B** — elle renvoie `(x, y)` affines : tu prends la parité de `y` pour le
  préfixe et tu copies `x`.
- **MODE C** — elle sérialise déjà la clé compressée : tu lui passes `pub33`.

Puis :

```bash
make ARCH=sm_86 SECP_INC=/chemin/include SECP_LIB=/chemin/lib
./keybench
```

Si ta lib charge une table de multiples de `G` depuis l'hôte, appelle son init
dans `secp_init_host()` (dans `benchmark.cu`) avant le lancement du kernel.

## Leviers d'optimisation (par ordre d'impact)

1. **Fixed-base / comb sur G.** `pub = priv·G` avec `G` **constant** : la
   multiplication doit utiliser une table précalculée de multiples de `G`
   (méthode comb/fenêtrée), pas un double-and-add générique. C'est le facteur
   dominant (×10–20). Vérifie que ta lib est bien en fixed-base ; sinon c'est le
   premier chantier.
2. **Inversion par lots (astuce de Montgomery).** Le passage Jacobien→affine
   coûte une inversion modulaire par clé. En traitant les clés par batch, on fait
   **une** inversion pour tout le batch (`a⁻¹, b⁻¹ …` via un seul `inv`). Si ta
   lib a une API batch, restructure le kernel pour lui donner N scalaires d'un
   coup au lieu d'appeler `secp_pubkey_compressed` clé par clé.
3. **Lâcher le base58.** Un vrai scanner compare les 20 octets de `hash160`, pas
   la chaîne base58 (habillage pur). `make nobase58` mesure ce mode. Pour
   comparer au CPU, garde le base58 (défaut).
4. **Occupation.** Joue sur `--threads` (128/256) et `--iters` (assez grand pour
   amortir le lancement). Le pipeline consomme pas mal de registres (le `w[64]`
   de SHA-256 surtout) ; si l'occupation est faible, teste
   `-maxrregcount=64` dans le Makefile et compare.
5. **Mémoire.** Les clés vivent en registres, zéro accès global dans la boucle
   (hors `sink` final anti-DCE) : ne réintroduis pas de global/const dans le
   chemin chaud.

## Notes

- Génération des clés : chaque thread balaie un intervalle de compteur disjoint
  (mode séquentiel, comme BitCrack). Pour du « vraiment aléatoire par clé »,
  remplace l'écriture du compteur dans `priv[24..31]` par un PRNG (SplitMix64) ;
  pour un benchmark de débit ça ne change pas le coût du pipeline.
- La validité du scalaire vs l'ordre `n` de la courbe est quasi toujours vraie et
  n'est pas revérifiée dans la boucle chaude (le CPU le faisait par rejet) ;
  l'impact sur le débit est négligeable.
```
