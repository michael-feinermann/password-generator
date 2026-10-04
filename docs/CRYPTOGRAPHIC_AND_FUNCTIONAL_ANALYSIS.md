# Technische Analyse von Password Generator 2.3.3

Stand: 4. Oktober 2026. Diese Datei beschreibt die Ableitung und Verifikation für Version 2.3.3, Build 10. Den vorigen Release beschreibt [die Analyse zu 2.3.1](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS_2.3.1.md).

## Datenfluss

Der Pool hält die letzten 4.096 tatsächlichen Mausbewegungen. Ein Datensatz umfasst 89 Byte: Versionsbyte 1 und elf 64-Bit-Werte in Little-Endian-Reihenfolge für Ereignisnummer, monotone Nanosekunden, Ereigniszeit, x, y, deltaX, deltaY, Fensterbreite, Fensterhöhe, Modifikatormaske und gedrückte Maustasten. Fließkommazahlen werden über ihr IEEE-754-Bitmuster codiert. Ein voller Pool enthält 364.544 Byte Nutzdaten.

Ein begrenzter Ringpuffer ersetzt die ältesten Datensätze. Eine getrennte Indexpermutation bestimmt die Reihenfolge für das Hashen. Bewegungen über Bedienelementen und Ziehbewegungen werden im gesamten Appfenster erfasst; stationäre Ereignisse und Ereignisse anderer Fenster werden ausgeschlossen.

Fisher-Yates verwendet die lineare Durstenfeld-Variante mit absteigenden Indizes und gleichverteilter Auswahl einschließlich der aktuellen Position. Kandidaten stammen als Little-Endian-UInt32 aus frischen, gepufferten macOS-CSPRNG-Bytes. Rejection Sampling verwirft den unvollständigen letzten Modulo-Bucket. Wiederholt unbrauchbare Kandidaten führen zum Fehler. Ab Appstart läuft ein Poolshuffle etwa alle sechs Sekunden, zusätzlich unmittelbar vor jeder Generierung. Auf dem anfangs leeren Pool ist der Shuffle ein Leerlauf. Suspendierung und Schlaf können den periodischen Termin verschieben.

Alle Poolhashes und die folgende Ableitung erfolgen ausschließlich bei der Generierung:

```text
shuffle(records)
P = serialize(records in shuffled order)
D = Skein-1024-1024(P) || SHA3-512(P) || SHA512(P)  // 128 + 64 + 64 Byte
A = D XOR fresh_macOS_random(256)                  // erster separat angeforderter OS-Beitrag
B = fisher_yates_shuffle_all_2048_bits(A)
M = B XOR fresh_macOS_random(256)                  // 256-Byte-Masterkey
S0 = Skein1024XOF(M[0..<128])
S1 = SHAKE256(M[128..<160])
S2 = SHAKE256(M[160..<192])
S3 = AES256CTR(key: M[192..<224], counter: 0)
S4 = AES256CTR(key: M[224..<256], counter: 0)
X = read(S0,n) XOR read(S1,n) XOR read(S2,n) XOR read(S3,n) XOR read(S4,n)
output_bytes = X XOR fresh_macOS_random(n)
```

Skein-1024-1024 liefert 128 Byte, SHA3-512 und SHA512 jeweils 64 Byte. SHA512 wird über CryptoKit berechnet. Die Reihenfolge der Verkettung ist fest. Zuerst werden die 256 Hashbytes mit einem frischen, gleich langen macOS-CSPRNG-Beitrag XOR-verknüpft. Danach permutiert Fisher-Yates sämtliche 2.048 einzelnen Bits dieses Ergebnisses, nicht nur die 256 Byte. Bitindex null bezeichnet das niederwertigste Bit von Byte null. Erst der zweite XOR mit weiteren frischen 256 macOS-CSPRNG-Bytes ergibt den Masterkey. Beide Masken werden separat angefordert und weder untereinander noch mit den Zufallsbytes für den Shuffle oder den späteren Ausgabe-XOR wiederverwendet.

Skein-XOF folgt Skein v1.3, Abschnitt 4.12: Das Ausgabelängenfeld ist `N_o = 2^64 - 1`. Das erste Masterkey-Fragment wird als ungeschlüsselte Nachricht absorbiert. Die Ausgabe besteht aus UBI-Blöcken vom Typ 63 mit fortlaufenden Little-Endian-64-Bit-Ausgabezählern. Diese XOF-Konfiguration unterscheidet sich vom Poolhash mit fester 1.024-Bit-Ausgabe.

Die zwei SHAKE256-Streams erhalten jeweils eigene 32-Byte-Fragmente. Ihre Absorb- und Squeeze-Zustände bleiben über alle Reads erhalten. Die beiden AES-256-CTR-Streams erhalten die letzten zwei separaten 32-Byte-Fragmente als AES-Schlüssel. CommonCrypto übernimmt ausschließlich die AES-Blockverschlüsselung im ECB-Modus ohne Padding; daraus erzeugt die Anwendung den CTR-Strom durch Verschlüsselung des expliziten 128-Bit-Zählers. AES wird nicht im Projekt selbst implementiert.

Jeder AES-Zähler beginnt bei null und wird über alle 128 Bit in Big-Endian-Reihenfolge inkrementiert. Ein teilweise gelesener 16-Byte-Ausgabeblock bleibt für die nächsten Reads erhalten. Nach dem letzten gültigen Zählerblock dürfen nur dessen noch nicht gelesene Bytes ausgegeben werden; eine weitere Blockanforderung bricht ab. Ein Umlauf auf null wird niemals unter demselben Schlüssel verwendet. Die Streams werden pro Generierung neu mit den frischen Masterkey-Fragmenten initialisiert. Dieselbe Kombination aus Schlüssel und Zähler darf nicht wiederverwendet werden.

Alle fünf Streams laufen bei Nachforderungen durch Rejection Sampling von ihrer aktuellen Position weiter. Jede Ausgabeanforderung erhält anschließend einen frischen, gleich langen OS-XOR-Beitrag. Bei einem Ableitungs- oder OS-Fehler wird der betroffene Passwortstream vollständig verworfen; erfolgreich konsumierte Präfixe werden nicht erneut ausgegeben. Der periodische Task mischt nur Mausereignisse und berechnet weder Poolhashes noch Masterkeys.

## Ausgabeformate und Entropieanzeige

| Format | Zulässige Länge | Alphabetgröße | Nominelle Entropie |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21 oder 24 Wörter | 2.048 Wörter | 128, 160, 192, 224 oder 256 Bit |
| EFF | 6 bis 128 Wörter | 7.776 Wörter | Wörter × log₂(7.776) |
| ASCII | 8 bis 256 Zeichen | 94 Zeichen ohne Leerzeichen | Zeichen × log₂(94) |
| PIN | 3 bis 512 Ziffern | 10 Ziffern | Ziffern × log₂(10) |
| Hex | 1 bis 512 Zeichen | 16 Zeichen | Zeichen × 4 Bit |

Die Anzeige beschreibt die Größe des gleichverteilt abgetasteten Auswahlraums. BIP39-Prüfsummenbits zählen nicht als zusätzliche Entropie. Bei maximaler Länge ergeben sich rechnerisch etwa 1.654,376 Bit für EFF und 1.700,827 Bit für PIN sowie 2.048 Bit für Hex. Diese Größen messen weder Mausentropie noch die Sicherheitsstärke der gesamten Konstruktion. Wiederholte Zeichen oder Wörter bleiben zulässig.

Die Hashlänge von 2.048 Bit beweist keine entsprechende unabhängige Eingabeentropie. Alle drei Poolhashes verarbeiten dieselben Ereignisse. Die Bitpermutation erhält die Anzahl der gesetzten Bits. Die Sicherheitsstärken der fünf XOR-verknüpften Streams dürfen nicht addiert werden. Die individuelle Konstruktion ist weder ein standardisiertes DRBG-Verfahren noch extern kryptografisch auditiert. Ihre Sicherheit stützt sich weiterhin auf die Unvorhersagbarkeit der frischen Systemzufallsbytes. Die beiden ergänzten AES-CTR-Streams sind keine Aussage über den internen Aufbau von Apples CSPRNG.

## Vorschläge und farbliche Einordnung

Beim Start und bei jedem Formatwechsel schlägt die App die kleinste unterstützte Länge mit mindestens 256 nominellen Bit vor: 24 BIP39-Wörter (256 Bit), 20 EFF-Wörter (rund 258,50 Bit), 40 ASCII-Zeichen (rund 262,18 Bit) und 64 Hexzeichen (256 Bit). Die gewünschte Ausnahme ist eine PIN mit sechs Ziffern (rund 19,93 Bit). Andere erlaubte Längen bleiben frei wählbar.

Die Einstufung verwendet den ungerundeten Wert, während die Oberfläche eine Dezimalstelle zeigt. Unter 128 Bit erscheint die Anzeige rot, von 128 bis unter 256 Bit gelb, von 256 bis unter 1.024 Bit hellgrün und ab 1.024 Bit dunkelgrün. Text, Symbol und eine vierteilige Legende ergänzen die Farbe. Ungültige Eingaben erhalten eine neutrale Anzeige. Konfiguration und erzeugtes Ergebnis verwenden dieselbe Einordnung.

Die deutschen Stufentexte lauten auf Nutzerwunsch unverändert „knackbar“, „nicht quantensicher“, „praktisch nicht angreifbar“ und „thermodynamisch nicht angreifbar“. Direkt unter dem Bitwert stehen die beiden Modelllaufzeiten „Exascale-Computer“ und „Petahertz-Quantencomputer“, einschließlich klassischer mittlerer Trefferzeit sowie getrennten Energie- und Zeitbudgetanzeigen. Ausgewählte Konfiguration und erzeugtes Ergebnis verwenden denselben Anzeigebaustein. Ein fokussierbarer Info-Button unmittelbar hinter jeder Bezeichnung öffnet eine scrollbare, stufenspezifische Erklärung mit Modellannahmen und Primärquellen. Aktive Stufeninfos zeigen zusätzlich die aktuelle Auswahl; nicht aktive Legendeninfos erfinden keinen Entropiewert. Der Tooltip bleibt ein kompakter gemeinsamer Geltungshinweis. Die Farbstufen beschreiben den nominellen Suchraum und sind keine NIST-Sicherheitsklassifizierung. Quelle und Gesamtverfahren werden dadurch nicht auditiert.

Version 2.3.3 verwendet mindestens 14 Punkt für Apptexte. Potenzen erscheinen als regulär große Zeichen mit `^`, einschließlich `2^(n/2)` und `10^-120`; kleine Unicode-Exponenten entfallen. Das normale Fenster von 1.060 × 840 Punkten ist mit `contentMinSize` als Mindestgröße festgelegt. Die bisherige Inhaltsobergrenze von 980 Punkten entfällt. Viewportgröße, Schrift, Logo, wesentliche Abstände, Ergebnisbereiche und Infofenster wachsen gemeinsam; Karten und Legende passen ihre Spaltenanzahl an die nutzbare Breite an.

<a id="attack-cost-models"></a>

## Attack-cost models / Modelle für den Angriffsaufwand

### English

The following calculations supplement the four interface labels; they do not change the generator or establish its source entropy. Let `n` denote the displayed nominal bits and `N = 2^n` the number of equally likely candidates. The model assumes one valid target, unstructured search, and an oracle that checks each complete candidate. It excludes shortcuts against a cipher, derivation, or implementation. The assumed rates already count complete candidate checks or Grover iterations, not individual machine instructions.

The classical estimate exhausts the entire space at `r_C = 10^18` checks per second: `t_C = 2^n / r_C`. For a uniformly positioned target, the mean discovery time is approximately half of this. The idealized Petahertz quantum computer serially performs `r_Q = 10^15` Grover iterations per second: `q_Q ≈ (π/4) × 2^(n/2)` and `t_Q = q_Q / r_Q`, a continuous approximation for near-certain success, without rounding to whole iterations. The oracle-search result does not provide a quantum processor implementation. [Grover (1996)](https://arxiv.org/abs/quant-ph/9605043), [Zalka (1999)](https://arxiv.org/abs/quant-ph/9711070).

These rates are illustrative assumptions. DOE's exascale measure is FLOPS, not password checks. The 1-PHz optoelectronics study concerns electronic signal control in solids, not a universal bound on all optical computation or complete quantum search iterations. Parallel resources, error correction, oracle circuits, memory and communication would require an explicit additional model. [DOE](https://www.energy.gov/topics/supercomputing), [Ossiander et al. (2022)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8956609/).

The energy comparison fixes a reservoir temperature `T = 2.7 K`, [Boltzmann constant](https://www.nist.gov/si-redefinition/kelvin/kelvin-present-realization) `k_B = 1.380649 × 10^-23 J/K`, and the additional assumption `b = 1` irreversibly erased information bit per classical check or Grover iteration. Thus `e = b × k_B × T × ln(2) ≈ 2.58388099657 × 10^-23 J` and the compared minimum heat is `Q_C = e × 2^n` or `Q_Q = e × (π/4) × 2^(n/2)`. Landauer constrains discarded information; reversible computation does not entail `b = 1` at every step. In particular, unitary Grover iterations do not establish this erasure premise. Nor is 2.7 K a timeless lower bound on an attacker's reservoir temperature. [Landauer (1961)](https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf), [Bennett (1973)](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html).

The chosen budget `E = 3 × 10^71 J` is an upward-rounded cosmological comparison, not extractable work. In a spatially flat critical-density model, `ρ_c = 3H_0²/(8πG)` and `E_comparison = (4π/3)R³ρ_c c²`. Using `H_0 ≈ 67.4 km/s/Mpc` and `R ≈ 46.5 billion light-years` gives approximately `2.735 × 10^71 J`, including dark energy in the total density. This construction neither asserts accessible global energy nor a conserved universal work supply. [Planck 2018, VI](https://arxiv.org/abs/1807.06209), [NASA/Geithner, slide 5](https://nepp.nasa.gov/docs/etw/2022/13-JUN-MON/1055-Geithner-v3-20220009134.pdf).

Independently of the energy comparison, the time model grants `H = 10^106` years, with `31,557,600` seconds per year, hence `H_s = 3.15576 × 10^113 s`. This is an assumed comparison horizon. Hawking's evaporation model and its mass-dependent extrapolation motivate very long time scales; Adams and Laughlin do not establish maximum universal entropy at exactly `10^106` years. Their section VI.D leaves cosmological heat death dependent on the future cosmology. The application does not predict the lifetime of the universe. [Hawking (1975)](https://doi.org/10.1007/BF02345020), [Adams and Laughlin (1997), IV.G and VI.D](https://sites.astro.caltech.edu/ay1/RevModPhys.69.337.pdf).

The thresholds below follow algebraically from these assumptions. Equality uses the whole budget; the displayed exceedance applies only above the threshold.

| Comparison | Threshold in nominal bits | First whole-bit value exceeding it |
|---|---|---|
| Classical energy: `n > log₂(E/e)` | 312.476664 | 313 |
| Grover energy: `n > 2 log₂(4E/(πe))` | 625.650335 | 626 |
| Classical time: `n > log₂(r_C H_s)` | 436.830568 | 437 |
| Grover time: `n > 2 log₂(4r_Q H_s/π)` | 854.426575 | 855 |

Exceeding the near-certain-search budget is not the same as negligible success. With one target, Grover's probability after `q` iterations is `sin²((2q + 1) × asin(1/√N))`. At the assumed energy-limited `q = floor(E/e)`, it is still about 96.8% for 626 nominal bits, but about `3 × 10^-120` for 1024 bits. These values inherit the same extra erasure premise and idealized search model. [Boyer et al.: Tight bounds on quantum searching](https://arxiv.org/abs/quant-ph/9605034).

At `n = 1024`, `t_Q ≈ 3.3369038594 × 10^131 years`, approximately `3.3369038594 × 10^25` comparison horizons. Thus even without assigning Landauer heat to reversible iterations, this particular rate-and-time model cannot complete the modeled near-certain search. Changing its premises changes that conclusion. A lucky earlier guess or smaller nonzero success probability is not ruled out. Exhaustive search remains a known algorithm; the comparison concerns resources for the modeled success criterion.

The fixed color thresholds remain 128, 256 and 1024. The dark-green boundary is a coarse presentation choice: 1024 is the next power of two above both 626 and 855, not an exact physical transition. Red does not imply practical crackability throughout its range; yellow does not declare all corresponding encryption quantum-broken; light green does not cover other attack paths; dark green expresses only the stated conditional comparisons. These are not NIST security categories. [NIST PQC FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs).

Threefish-1024 has a 1024-bit key input. Neither that length nor a password's nominal selection space proves 1024 bits of unpredictable source information. A suitable derivation must retain the required uncertainty; it cannot create missing entropy. Expanding one password into multiple keys does not make their entropy additive. Overall cipher and cascade security requires separate analysis of the algorithms, modes, authentication and implementation. [Skein v1.3, sections 3.3 and 6.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf).

### Deutsch

Diese Rechnungen ergänzen die vier Oberflächenbezeichnungen. Sie verändern den Generator nicht und weisen seine Quellenentropie nicht nach. `n` bezeichnet die angezeigten nominellen Bits und `N = 2^n` die Anzahl gleich wahrscheinlicher Kandidaten. Das Modell setzt ein gültiges Ziel, unstrukturierte Suche und eine vollständige Kandidatenprüfung durch ein Orakel voraus. Abkürzungen gegen Verschlüsselung, Ableitung oder Implementierung sind nicht erfasst. Die angenommenen Raten zählen vollständige Prüfungen beziehungsweise Grover-Iterationen, keine einzelnen Maschinenbefehle.

Die klassische Schätzung durchsucht den gesamten Raum mit `r_C = 10^18` Prüfungen pro Sekunde: `t_C = 2^n / r_C`. Bei gleichverteilter Zielposition ist die mittlere Fundzeit ungefähr halb so groß. Der idealisierte Petahertz-Quantencomputer führt seriell `r_Q = 10^15` Grover-Iterationen pro Sekunde aus: `q_Q ≈ (π/4) × 2^(n/2)` und `t_Q = q_Q / r_Q`. Das ist eine kontinuierliche Näherung für nahezu sicheren Erfolg ohne Rundung auf ganze Iterationen. Das Ergebnis zur Orakelsuche liefert keine Implementierung eines Quantenprozessors. [Grover (1996)](https://arxiv.org/abs/quant-ph/9605043), [Zalka (1999)](https://arxiv.org/abs/quant-ph/9711070).

Beide Raten sind illustrative Annahmen. DOE misst Exascale in FLOPS, nicht in Passwortprüfungen. Die 1-PHz-Studie betrifft elektronische Signalsteuerung in Festkörpern und keine universelle Grenze für sämtliche optischen Berechnungen oder vollständige Quanten-Suchiterationen. Parallelressourcen, Fehlerkorrektur, Orakelschaltungen, Speicher und Kommunikation benötigen ein eigenes erweitertes Modell. [DOE](https://www.energy.gov/topics/supercomputing), [Ossiander et al. (2022)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8956609/).

Der Energievergleich setzt eine Reservoirtemperatur `T = 2,7 K`, die [Boltzmann-Konstante](https://www.nist.gov/si-redefinition/kelvin/kelvin-present-realization) `k_B = 1,380649 × 10^-23 J/K` und zusätzlich `b = 1` irreversibel gelöschtes Informationsbit pro klassischer Prüfung beziehungsweise Grover-Iteration an. Damit gilt `e = b × k_B × T × ln(2) ≈ 2,58388099657 × 10^-23 J`; verglichen wird die minimale Wärme `Q_C = e × 2^n` beziehungsweise `Q_Q = e × (π/4) × 2^(n/2)`. Landauer betrifft verworfene Information; reversible Berechnung erfordert nicht bei jedem Schritt `b = 1`. Insbesondere begründen unitäre Grover-Iterationen diese Löschannahme nicht. Auch 2,7 K sind keine zeitlich unbegrenzte Untergrenze der Reservoirtemperatur eines Angreifers. [Landauer (1961)](https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf), [Bennett (1973)](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html).

Das gewählte Budget `E = 3 × 10^71 J` ist ein aufgerundeter kosmologischer Vergleich, keine gewinnbare Arbeit. Im räumlich flachen Modell mit kritischer Dichte gelten `ρ_c = 3H_0²/(8πG)` und `E_Vergleich = (4π/3)R³ρ_c c²`. Mit `H_0 ≈ 67,4 km/s/Mpc` und `R ≈ 46,5 Milliarden Lichtjahren` ergeben sich etwa `2,735 × 10^71 J`, einschließlich Dunkler Energie in der Gesamtdichte. Daraus folgen weder global zugängliche Energie noch ein erhaltener universeller Arbeitsvorrat. [Planck 2018, VI](https://arxiv.org/abs/1807.06209), [NASA/Geithner, Folie 5](https://nepp.nasa.gov/docs/etw/2022/13-JUN-MON/1055-Geithner-v3-20220009134.pdf).

Unabhängig vom Energievergleich erlaubt das Zeitmodell `H = 10^106` Jahre zu jeweils `31.557.600` Sekunden, also `H_s = 3,15576 × 10^113 s`. Das ist ein angenommener Vergleichshorizont. Hawkings Verdampfungsmodell und seine massenabhängige Extrapolation motivieren sehr lange Zeitskalen; Adams und Laughlin beweisen keine maximale Entropie des Universums bei genau `10^106` Jahren. Ihr Abschnitt VI.D lässt den kosmologischen Wärmetod von der zukünftigen Kosmologie abhängen. Die Anwendung prognostiziert keine Lebensdauer des Universums. [Hawking (1975)](https://doi.org/10.1007/BF02345020), [Adams und Laughlin (1997), IV.G und VI.D](https://sites.astro.caltech.edu/ay1/RevModPhys.69.337.pdf).

Die folgenden Schwellen ergeben sich algebraisch aus diesen Annahmen. Bei Gleichheit wird das Budget vollständig ausgeschöpft; eine Überschreitung wird erst oberhalb der Schwelle angezeigt.

| Vergleich | Schwelle in nominellen Bits | Erster überschreitender ganzzahliger Bitwert |
|---|---|---|
| Klassische Energie: `n > log₂(E/e)` | 312,476664 | 313 |
| Grover-Energie: `n > 2 log₂(4E/(πe))` | 625,650335 | 626 |
| Klassische Zeit: `n > log₂(r_C H_s)` | 436,830568 | 437 |
| Grover-Zeit: `n > 2 log₂(4r_Q H_s/π)` | 854,426575 | 855 |

Ein überschrittenes Budget für nahezu sichere Suche bedeutet nicht automatisch vernachlässigbare Erfolgschancen. Bei einem Ziel beträgt Grovers Wahrscheinlichkeit nach `q` Iterationen `sin²((2q + 1) × asin(1/√N))`. Mit der angenommenen Energiebegrenzung `q = floor(E/e)` ergeben sich bei 626 nominellen Bits noch etwa 96,8%, bei 1024 Bits dagegen etwa `3 × 10^-120`. Auch diese Werte setzen die zusätzliche Löschannahme und das idealisierte Suchmodell voraus. [Boyer et al.: Tight bounds on quantum searching](https://arxiv.org/abs/quant-ph/9605034).

Bei `n = 1024` beträgt `t_Q ≈ 3,3369038594 × 10^131 Jahre`, etwa `3,3369038594 × 10^25` Vergleichshorizonte. Auch ohne Landauer-Wärme pro reversibler Iteration lässt dieses konkrete Raten- und Zeitmodell die modellierte nahezu sichere Suche daher nicht zu. Geänderte Annahmen verändern die Schlussfolgerung. Ein früher Glückstreffer oder eine kleinere, von null verschiedene Erfolgswahrscheinlichkeit bleiben möglich. Vollständiges Durchprobieren bleibt ein bekannter Algorithmus; verglichen werden die Ressourcen für das angesetzte Erfolgskriterium.

Die festen Farbgrenzen bleiben 128, 256 und 1024. Die dunkelgrüne Grenze ist eine grobe Darstellungsentscheidung: 1024 ist die nächste Zweierpotenz sowohl oberhalb von 626 als auch von 855, kein exakter physikalischer Übergang. Rot beweist keine praktische Knackbarkeit im gesamten Bereich; Gelb erklärt nicht sämtliche zugehörigen Verschlüsselungen für quantengebrochen; Hellgrün erfasst keine anderen Angriffswege; Dunkelgrün bezeichnet ausschließlich die genannten bedingten Vergleiche. Es handelt sich nicht um NIST-Sicherheitskategorien. [NIST PQC FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs).

Threefish-1024 besitzt einen 1024-Bit-Schlüsseleingang. Weder diese Länge noch der nominelle Auswahlraum eines Passworts beweisen 1024 Bit unvorhersagbare Quelleninformation. Eine geeignete Ableitung muss die benötigte Ungewissheit erhalten; sie kann fehlende Entropie nicht erzeugen. Die Erweiterung eines Passworts zu mehreren Schlüsseln macht deren Entropie nicht additiv. Die Sicherheit einer Verschlüsselung oder Kaskade erfordert eine gesonderte Analyse von Verfahren, Betriebsart, Authentisierung und Implementierung. [Skein v1.3, Abschnitte 3.3 und 6.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf).

## Export und Laufzeitschutz

BIP39 verwendet standardmäßig ein Leerzeichen, EFF einen Bindestrich. Beide Trennzeichen bleiben unabhängig und frei wählbar, einschließlich leerer oder mehrstelliger Texte. Hex lässt sich mit kleinen oder großen Buchstaben exportieren. Eine Formatänderung erhält die ursprünglichen Komponenten und zieht keine neuen Zufallswerte.

BIP39 ohne Trenner ist nicht immer eindeutig rekonstruierbar: `leg alarm` und `legal arm`, jeweils gefolgt von neunmal `abandon` und `accuse`, ergeben zwei verschiedene prüfsummengültige 12-Wort-Mnemonics mit demselben zusammengefügten Text. Die Entropieanzeige gilt deshalb für die ursprüngliche Auswahl. Für den üblichen BIP39-Import sind Leerzeichen zu verwenden.

Die App benötigt vor Generierung, Anzeige und Kopieren eine gültige laufende Code-Signatur, Hardened Runtime, minimale Sandbox und keinen erkannten Debugger. POSIX-Core-Dumps sind deaktiviert. Die Ausgabe bleibt zunächst verdeckt; Anzeigen erfordert Bestätigung und wird bestmöglich nach 60 Sekunden beziehungsweise bei Kontextwechsel beendet. Die auf ausdrücklichen Klick befüllte Zwischenablage verwendet `currentHostOnly` und wird bestmöglich nach etwa 45 Sekunden geleert, wenn der Inhalt unverändert ist.

Mauspool und temporäre Kryptopuffer werden beim Verwerfen bestmöglich überschrieben, CommonCrypto-Kontexte freigegeben. Swift-Kopien, Register und Betriebssystempuffer verhindern eine garantierte vollständige Löschung. Screenshots, externe Kameras oder ein kompromittiertes Betriebssystem lassen sich damit nicht zuverlässig abwehren. Die App speichert erzeugte Passwörter nicht in Dateien oder Preferences und besitzt keine Netzwerkberechtigung.

## Verifikation

Am 4. Oktober 2026 bestanden jeweils 103 XCTest-Tests im Debug- und Release-Build: 74 Core-Tests und 29 App-Tests, ohne Fehler oder Compilerwarnungen. Verwendet wurden `swift test -Xswiftc -warnings-as-errors` und `swift test -c release -Xswiftc -warnings-as-errors`. Die weiterhin vorhandenen Tests umfassen die vollständige kryptografische Ableitung, die Passwortformate, Fehlerverhalten und exakte Schwellen. Der SHA256-Wert der unveränderten Pipeline-Fixtures lautet `50541a981bb2fca83307cbfb86aec2643533a2675efc21301630e0d3afdfee0b`.

Die zusätzlichen Tests prüfen die minimalen Vorschlagslängen einschließlich der PIN-Ausnahme, den initialen Appzustand und jeden Formatwechsel, die ungerundeten Schwellen direkt darunter, darauf und darüber sowie die Einordnung ungültiger Zahlen. Reale Hex-Konfigurationen an allen vier Grenzen prüfen die Verbindung zwischen Format und Stufe. Die vorhandenen Tests für Kryptografie, vollständige Ableitung, Passworterzeugung und Fehlerverhalten bleiben enthalten.

Die neuen Modelltests vergleichen logarithmische Laufzeiten und sämtliche Energie- und Zeitschwellen mit unabhängig in hoher Dezimalpräzision berechneten Zahlen. Sie prüfen Werte unmittelbar unter, auf und über den ungerundeten Schwellen, ihre ganzzahligen Übergänge, den exakten klassischen Mittelwert für eine einzelne Hexposition und eine sechsstellige PIN, sämtliche Formatmaxima sowie ungültige und extrem große Fließkommazahlen. Die Darstellungsprüfungen kontrollieren lokalisierte Einheiten einschließlich Singular, Dezimaltrennzeichen, Mantissenübertrag und wissenschaftliche Exponenten bis zur maximalen Hexlänge.

Drei zusätzliche Darstellungstests kontrollieren die Mindestschriftgröße, die Mindestfenstergröße, die Vergrößerung der Typografie bei größeren Fenstern und innerhalb unterstützter Fenster liegende Infofenster. Eine unabhängige Codegegenprüfung bestätigt die korrekte Bedeutung der `^`-Potenzen, insbesondere die Klammerung bei `2^(n/2)` und negative Exponenten. Die native Oberfläche von 2.3.3 wurde geöffnet und ihre Werte per Accessibility geprüft: BIP39 mit 256 Bit, die beiden richtigen Computerbezeichnungen und reguläre Potenzziffern. Wegen des erhaltenen Fensterschutzes liefert die Bildschirmaufnahme eine leere Fläche; diese Prüfung belegt daher keine pixelbasierte Designkontrolle.

Die vollständigen Referenzen werden mit der unveränderten offiziellen Skein-C-Referenz, Python `hashlib` für SHA3/SHA512/SHAKE sowie einer unabhängigen AES-Referenz berechnet. Der reproduzierbare Generator und die Zwischenwerte stehen unter `Tests/PasswordGeneratorCoreTests/Resources/`; die Herkunft dokumentiert `CRYPTO_VECTORS.md`. Sie prüfen Null-Shuffle-Kandidaten, variierte Kandidaten mit gezielten Rejections und einen mehrfach überschreibenden Ringpuffer mit zwischenzeitlichen Shuffles. Die erwarteten Werte werden nicht aus dem Swift-Produktionscode erzeugt. Fixture-Version 4 enthält zusätzlich die erste OS-Maske, den bereits maskierten Digest und die zweite OS-Maske als getrennte Zwischenwerte. Die Tests prüfen die Reihenfolge beider 256-Byte-Anforderungen relativ zu den Shuffle-Bytes. Sie prüfen außerdem für jede Maske sowohl eine zu kurze Rückgabe als auch einen geworfenen Fehler und stellen sicher, dass danach keine späteren Zufallsanforderungen erfolgen.

Die AES-Prüfungen enthalten den AES-256-CTR-Testvektor aus NIST SP 800-38A, getrennte und zusammenhängende Reads, Zählerüberträge, das Ende des 128-Bit-Zählerraums, Clear und Fehlerbehandlung. Die vollständige Ableitung wird über die Blockgrenzen von AES, Skein-XOF und SHAKE hinweg verglichen. Alle fünf Ausgabeformate sowie ihre gültigen und ungültigen Grenzlängen und Exportoptionen werden geprüft.

Das Release-ZIP erhält weiterhin separate SHA256-, SHA3-512- und Skein-1024-1024-Prüfsummendateien und ein Integritätsmanifest. `Scripts/verify-release.sh` vergleicht jedes Verfahren mit ZIP, Sidecar und Manifest. Python kontrolliert beide SHA-Werte unabhängig; `Scripts/skein-reference-checksum.sh` verwendet die offizielle C-Referenz. Das entpackte App-Bundle wird zusätzlich auf Code-Signatur und minimale Sandbox geprüft. Für notarisierte Pakete folgen Ticket- und Gatekeeper-Prüfung. Hashwerte allein beweisen keine Herkunft.

## Release-Nachweis

Version 2.3.3, Build 10, wurde am 4. Oktober 2026 über Xcodes Direct Distribution notarisiert. Das Release-Paket stammt unmittelbar aus dem von Xcode exportierten App-Bundle. Nach diesem Export wurde die App weder neu gebaut noch erneut signiert. Sämtliche Ressourcen und der um seine Signatur bereinigte Mach-O-Code stimmen mit dem getesteten Build überein.

| Nachweis | Ergebnis |
|---|---|
| App-Bundle | `Password Generator 2.3.3.app`, Version `2.3.3`, Build `10`, arm64, macOS 14 oder neuer |
| Signierung | Developer ID Application: Michael Feinermann, Team `2T6K9PGS55`, Hardened Runtime und minimale App Sandbox |
| Xcode-Notarisierung | freigegeben; Submission-ID `83FE4A37-E6EC-4341-8136-291BABAB5552` |
| CDHash des notarisierten Exports | `da5bfa1f803c1d57ec96e143500a069f778fc3b2` |
| SHA256 des um die Signatur bereinigten ausführbaren Codes | `964d47471363fbafbb2fb8ee4867ba481fcf53ecabb5ce0fb1b28a0613a643cd` |
| Code-Signatur | `codesign --verify --deep --strict` bestanden |
| Ticket | `xcrun stapler validate` bestanden |
| Gatekeeper | `spctl --assess --type execute` akzeptiert, Quelle `Notarized Developer ID` |
| Installation | `/Applications/Password Generator 2.3.3.app`; alle Dateien einschließlich Signatur byteidentisch zum Xcode-Export |

`Scripts/verify-release.sh` prüfte das finale ZIP erfolgreich einschließlich ZIP-Struktur, aller drei Sidecars, Integritätsmanifest, unabhängiger Python-Implementierungen für SHA256/SHA3-512, offizieller Skein-C-Referenz, entpackter Code-Signatur, Sandbox, Ticket und Gatekeeper.

```text
Password.Generator-2.3.3.zip
SHA256:
f03847d0c731a032941833c2cc8bf59bfbf7e15d06833334a1690538b3e0bdbb
SHA3-512:
0f4086ace34700bc607f5696bec3556cf5f0a2186bc244ce93b3abd5eadcba4f3215c6bc3afaea3c058dd4a85e546054bbe1fb805a940eee4668d12af486300a
Skein-1024-1024:
968ebaf0084f27dafdfdd07320d793e37b3e25ee8764760889ec59dd3141df8f831db2775146220cfccca7771a97ed1ce16b3ffac997d4b76bd48e3316fb8238cce775e2320349286cc2a499bd82d0bae84c5237f0c2d2ab4ecc4b996f50656f80a3c8386856d23c9a5fc926e430e9843b28a5e52e55711e19a87b187c325731
```

Die installierte und notarisierte Fassung wurde nach Beenden des Testprozesses geöffnet. Die vorherigen Installationen von 2.3.1 und 2.3.2 sowie ihre App-Kopien unter `build` wurden aus LaunchServices abgemeldet und in wiederherstellbare Papierkorbordner verschoben. Aktuell ist ausschließlich Version 2.3.3 installiert. Xcode-Archive und Quellhistorie bleiben als Nachweise erhalten. Das aktuelle öffentliche Paket ist unter [Release v2.3.3](https://github.com/michael-feinermann/password-generator/releases/tag/v2.3.3) verfügbar.

## Quellen

- [BIP39-Spezifikation](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Originalwortliste](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [Skein v1.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
- [NIST FIPS 202: SHA3 und SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [NIST FIPS 180-4: SHA512](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [NIST SP 800-38A: CTR und AES-256-CTR-Testvektor](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [Apple CommonCrypto](https://github.com/apple-oss-distributions/CommonCrypto)
- [Apple SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
- [Durstenfeld, Algorithm 235](https://doi.org/10.1145/364520.364540)
