# Third-party notices

## BIP39 English word list and specification

The unmodified English BIP39 word list is distributed in `Sources/PasswordGeneratorCore/Resources/english.txt` and in the application bundle.

Source: https://github.com/bitcoin/bips/blob/master/bip-0039/english.txt

Specification and authors: Marek Palatinus, Pavol Rusnak, Aaron Voisine, Sean Bowe. BIP39 is published under the MIT License: https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki

The corresponding python-mnemonic MIT notice is included in `Licenses/python-mnemonic-MIT.txt` and the application bundle.

## EFF Large Wordlist

Copyright Electronic Frontier Foundation. The original list by Joseph Bonneau is included unchanged in `Sources/PasswordGeneratorCore/Resources/eff_large_wordlist.txt` and in the application bundle. The application parses its dice labels and words without modifying the source file.

Source: https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt

Background: https://www.eff.org/dice

License: Creative Commons Attribution 4.0 International, according to EFF's copyright policy: https://www.eff.org/copyright

License text: https://creativecommons.org/licenses/by/4.0/legalcode

No affiliation with or endorsement by EFF is implied.

## BIP39 test vectors

The English test vectors are from Trezor's python-mnemonic project. Copyright (c) 2013-2016 Pavol Rusnak, MIT License. See `Licenses/python-mnemonic-MIT.txt`.

Source: https://github.com/trezor/python-mnemonic/blob/master/vectors.json

## Cryptographic specifications and test data

Skein specification and original reference test vectors: https://www.schneier.com/academic/skein/

NIST FIPS 202 and SHA3/SHAKE validation vectors: https://csrc.nist.gov/Projects/cryptographic-algorithm-validation-program/Secure-Hashing

The Swift primitives are implemented locally from the specifications. No external cryptographic runtime library is bundled. The provenance and processing of reference test data are documented in `Tests/PasswordGeneratorCoreTests/Resources/CRYPTO_VECTORS.md`. Successful reference-vector tests are not an official algorithm certification.
