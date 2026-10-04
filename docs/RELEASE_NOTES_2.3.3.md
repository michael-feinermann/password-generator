# Password Generator 2.3.3

## English

Version 2.3.3, build 10, adds two estimated search durations immediately below the entropy value, for both the selected configuration and generated results: “Exascale computer” and “Petahertz quantum computer”. The existing four color bands and their exact German labels remain unchanged, with light green starting at 256 bits and dark green at 1,024 bits.

All app text uses at least 14-point type. Powers, including negative exponents, use full-size caret notation such as `10^106`, `10^-120`, and `2^(n/2)`. The regular 1,060 × 840-point window is the minimum; content and typography grow with larger windows and full-screen mode. The German quantum-computer label is “Petahertz-Quantencomputer”.

The classical model assumes 10^18 complete password checks per second and displays the exhaustive-search duration; its average time to find a uniformly selected target is approximately half that value. The quantum model assumes 10^15 complete Grover iterations per second, including the target check, and uses approximately (π/4) × 2^(n/2) iterations for near-unit success with one target. These are idealized model rates, not measured hardware performance.

The interface separately marks two conditional limits. The Landauer comparison assumes one irreversibly erased information bit per check or Grover iteration at 2.7 K, with a cosmological comparison budget of 3 × 10^71 J. Its continuous thresholds are approximately 312.476664 bits for exhaustive classical search and 625.650335 bits for the chosen Grover search. A separate, explicitly assumed horizon of 10^106 years is exceeded at approximately 436.830568 and 854.426575 bits, respectively. The horizon is not an established date for maximum entropy throughout the universe, and Landauer does not require irreversible erasure at each reversible Grover step.

Both calculated durations remain visible after a comparison limit is crossed. The info buttons explain the four levels, their assumptions, partial-success caveats, and the scope of claims about Threefish-1024 and encryption cascades. Logarithmic calculations support every allowed format length without overflow. The password-generation pipeline and its cryptographic functions are unchanged.

The visible app name and release artifacts include version 2.3.3. The latest release is provided with SHA256, SHA3-512, and Skein-1024-1024 checksums and an integrity manifest. Only the current public release and installed version are retained; source history and historical release notes remain available.

103 tests passed in each of the Debug and Release builds, with compiler warnings treated as errors. The app is Developer ID signed and was notarized through Xcode on October 4, 2026. The stapled ticket, Gatekeeper assessment, all three independent checksum comparisons, and the installed copy were verified. Detailed evidence is recorded in the [technical analysis](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#release-nachweis).

## Deutsch

Version 2.3.3, Build 10, ergänzt direkt unter dem Entropiewert zwei berechnete Suchlaufzeiten: „Exascale-Computer“ und „Petahertz-Quantencomputer“. Sie erscheinen sowohl für die ausgewählte Konfiguration als auch für erzeugte Ergebnisse. Die vier Farbstufen und ihre exakten Bezeichnungen bleiben unverändert: „knackbar“, „nicht quantensicher“, „praktisch nicht angreifbar“ und „thermodynamisch nicht angreifbar“. Hellgrün beginnt bei 256 Bit, dunkelgrün bei 1.024 Bit.

Alle Apptexte verwenden mindestens Schriftgröße 14. Potenzen einschließlich negativer Exponenten erscheinen mit regulär großen Ziffern als `10^106`, `10^-120` oder `2^(n/2)`. Die normale Fenstergröße von 1.060 × 840 Punkten ist die Mindestgröße; Inhalt und Typografie wachsen mit größeren Fenstern und im Vollbild. Die korrigierte Bezeichnung lautet „Petahertz-Quantencomputer“.

Das klassische Modell setzt 10^18 vollständige Passwortprüfungen pro Sekunde an und zeigt die Vollsuchzeit. Die mittlere Trefferzeit bei gleichverteiltem Ziel beträgt ungefähr die Hälfte. Das Quantenmodell setzt 10^15 vollständige Grover-Iterationen einschließlich Zielprüfung pro Sekunde an. Für nahezu vollständige Trefferwahrscheinlichkeit bei genau einem Ziel verwendet es ungefähr (π/4) × 2^(n/2) Iterationen. Die Raten sind idealisierte Modellannahmen und keine gemessene Hardwareleistung.

Zwei bedingte Grenzen werden getrennt angezeigt. Der Landauer-Vergleich nimmt eine irreversible Informationsbitlöschung pro Prüfung oder Grover-Iteration bei 2,7 K und ein kosmologisches Vergleichsbudget von 3 × 10^71 J an. Seine kontinuierlichen Schwellen liegen bei ungefähr 312,476664 Bit für die vollständige klassische Suche und 625,650335 Bit für die gewählte Grover-Suche. Der zusätzlich angenommene Zeithorizont von 10^106 Jahren wird bei ungefähr 436,830568 beziehungsweise 854,426575 Bit überschritten. Er ist kein gesichert datierter Zustand maximaler Entropie des gesamten Universums. Landauer erzwingt außerdem keine irreversible Löschung bei jedem reversiblen Grover-Schritt.

Beide errechneten Laufzeiten bleiben bei Überschreitungen sichtbar. Die Info-Buttons erklären die vier Stufen, die Annahmen, verbleibende Erfolgsmöglichkeiten und den Geltungsbereich der Aussagen zu Threefish-1024 und Verschlüsselungskaskaden. Die logarithmische Rechnung unterstützt alle erlaubten Formatlängen ohne Zahlenüberlauf. Passworterzeugung und kryptografische Funktionen bleiben unverändert.

Appname und Release-Dateien enthalten Version 2.3.3. Das aktuelle Release wird mit SHA256-, SHA3-512- und Skein-1024-1024-Prüfsummen sowie einem Integritätsmanifest angeboten. Nur die aktuelle öffentliche Releaseversion und Installation bleiben erhalten; Quellhistorie und historische Release Notes bleiben verfügbar.

Jeweils 103 Tests bestanden in Debug und Release; Compilerwarnungen wurden als Fehler behandelt. Die App ist mit Developer ID signiert und wurde am 4. Oktober 2026 über Xcode notarisiert. Angeheftetes Ticket, Gatekeeper-Bewertung, alle drei unabhängigen Prüfsummenvergleiche und die installierte Kopie wurden geprüft. Der ausführliche Nachweis steht in der [technischen Analyse](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#release-nachweis).

## Primary sources / Primärquellen

- [Zalka: Grover's quantum searching algorithm is optimal](https://arxiv.org/abs/quant-ph/9711070)
- [Landauer: Irreversibility and Heat Generation in the Computing Process](https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf)
- [Bennett: Logical Reversibility of Computation](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html)
- [NIST: SI defining constants](https://www.nist.gov/pml/special-publication-330/sp-330-section-2)
- [Adams and Laughlin: A Dying Universe](https://doi.org/10.1103/RevModPhys.69.337)
- [Skein specification 1.3, including Threefish](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
