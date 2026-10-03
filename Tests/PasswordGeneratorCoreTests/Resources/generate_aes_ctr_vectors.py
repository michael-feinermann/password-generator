#!/usr/bin/env python3
"""Regenerate public AES-256-CTR KATs with LibreSSL/OpenSSL, independently of CommonCrypto."""
import json
import pathlib
import subprocess


def encrypt(key, counter, plaintext):
    result = subprocess.run([
        "openssl", "enc", "-aes-256-ctr", "-nosalt", "-nopad",
        "-K", key.hex(), "-iv", counter.hex(),
    ], input=plaintext, check=True, capture_output=True).stdout
    assert len(result) == len(plaintext)
    return result


def main():
    key = bytes.fromhex("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4")
    counter = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
    plaintext = bytes.fromhex(
        "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51"
        "30c81c46a35ce411e5fbc1191a0a52eff69f2445df4f9b17ad2b417be66c3710")
    ciphertext = bytes.fromhex(
        "601ec313775789a5b7a7f504bbf3d228f443e3ca4d62b59aca84e990cacaf5c5"
        "2b0930daa23de94ce87017ba2d84988ddfc9c58db67aada613c2dd08457941a6")
    assert encrypt(key, counter, plaintext) == ciphertext, "NIST SP 800-38A F.5.5 mismatch"
    vectors = [{"name": "NIST-SP800-38A-F5.5", "key": key.hex(), "counter": counter.hex(),
                "plaintext": plaintext.hex(), "ciphertext": ciphertext.hex()}]
    for name, key, initial_counter, count in [
        ("zero-key-zero-counter", bytes(32), 0, 257),
        ("ascending-key-zero-counter", bytes(range(32)), 0, 4097),
        ("carry-from-low-to-high-64-bits", bytes(range(32)), 2**64 - 1, 33),
        ("final-two-counters", bytes(range(32)), 2**128 - 2, 32),
    ]:
        counter = initial_counter.to_bytes(16, "big")
        plaintext = bytes(count)
        vectors.append({"name": name, "key": key.hex(), "counter": counter.hex(),
                        "plaintext": plaintext.hex(), "ciphertext": encrypt(key, counter, plaintext).hex()})
    pathlib.Path(__file__).with_name("aes256ctr_vectors.json").write_text(json.dumps(vectors, indent=2) + "\n")
    print(f"Generated {len(vectors)} independently checked AES-256-CTR fixtures")


if __name__ == "__main__":
    main()
