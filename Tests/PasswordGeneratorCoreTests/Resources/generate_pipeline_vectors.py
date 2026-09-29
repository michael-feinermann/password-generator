#!/usr/bin/env python3
"""Regenerate pipeline KATs using the official Skein C code and Python hashlib.

Usage: python3 generate_pipeline_vectors.py /path/to/Reference_Implementation
No production Swift code is executed or translated by this generator.
"""

import argparse
import hashlib
import json
import pathlib
import struct
import subprocess
import tempfile


C_HARNESS = r"""
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "skein.h"

int main(int argc, char **argv) {
    if (argc != 4 || sizeof(size_t) != 8) return 1;
    const int xof = argv[1][0] == 'x';
    const size_t output_count = (size_t)strtoull(argv[3], NULL, 10);
    if (output_count > 1048576 || (!xof && output_count != 128)) return 2;
    FILE *file = fopen(argv[2], "rb");
    if (!file || fseek(file, 0, SEEK_END)) return 3;
    long input_count = ftell(file);
    if (input_count < 0 || fseek(file, 0, SEEK_SET)) return 4;
    unsigned char *input = malloc((size_t)input_count + 1);
    unsigned char *output = malloc(output_count + 1);
    if (!input || !output || fread(input, 1, (size_t)input_count, file) != (size_t)input_count) return 5;
    fclose(file);
    Skein1024_Ctxt_t context;
    if (Skein1024_Init(&context, xof ? SIZE_MAX : 1024) != SKEIN_SUCCESS) return 6;
    if (Skein1024_Update(&context, input, (size_t)input_count) != SKEIN_SUCCESS) return 7;
    if (xof) {
        unsigned char chaining_state[128];
        if (Skein1024_Final_Pad(&context, chaining_state) != SKEIN_SUCCESS) return 8;
        /* Configuration with UINT64_MAX has already been absorbed. This field
           now only bounds the original C implementation's output loop. */
        context.h.hashBitLen = output_count * 8;
        if (Skein1024_Output(&context, output) != SKEIN_SUCCESS) return 9;
    } else if (Skein1024_Final(&context, output) != SKEIN_SUCCESS) return 10;
    if (fwrite(output, 1, output_count, stdout) != output_count) return 11;
    free(input);
    free(output);
    return 0;
}
"""


class ReferenceRandom:
    """Deterministic test-only OS bytes with a separate output cursor."""

    def __init__(self, style):
        self.style = style
        self.shuffle_buffer_index = 0
        self.requests = []

    def shuffle_buffer(self):
        self.requests.append(4096)
        buffer_index = self.shuffle_buffer_index
        self.shuffle_buffer_index += 1
        if self.style == "zero":
            return bytes(4096)
        words = []
        for index in range(1024):
            if index < 2:
                value = 0xffffffff  # Deliberate rejection candidates.
            elif index == 2:
                value = 0
            else:
                value = ((buffer_index * 1024 + index) * 0x9e3779b9 + 0x7f4a7c15) & 0xffffffff
            words.append(value)
        return struct.pack("<1024I", *words)

    def master_mask(self):
        self.requests.append(192)
        return bytes(0xa5 if self.style == "zero" else (i * 37 + 0xa5) & 255 for i in range(192))

    def output_mask(self, count):
        return bytes(0x5a if self.style == "zero" else (i * 53 + 0x5a) & 255 for i in range(count))


def permute(values, random):
    # A fresh buffer belongs to each shuffle. Unused buffered bytes are discarded.
    buffer = b""
    cursor = 0
    for index in range(len(values) - 1, 0, -1):
        bound = index + 1
        limit = 2**32 - 2**32 % bound
        while True:
            if cursor == len(buffer):
                buffer = random.shuffle_buffer()
                cursor = 0
            candidate = struct.unpack_from("<I", buffer, cursor)[0]
            cursor += 4
            if candidate < limit:
                selected = candidate % bound
                break
        values[index], values[selected] = values[selected], values[index]


def mouse_record(index):
    return struct.pack(
        "<BQQdddddddQQ", 1, index, index + 1, index / 120,
        float(index % 127), float(index % 83), 1.2, -0.8, 800.0, 600.0, 0, 0,
    )


def xor(*inputs):
    assert len({len(value) for value in inputs}) == 1
    result = bytearray(len(inputs[0]))
    for value in inputs:
        for index, byte in enumerate(value):
            result[index] ^= byte
    return bytes(result)


def password(mode, length, random_bytes, word_lists):
    if mode == "bip39":
        entropy_bits = length * 11 * 32 // 33
        entropy = random_bytes[:entropy_bits // 8]
        bits = "".join(f"{byte:08b}" for byte in entropy)
        bits += f"{hashlib.sha256(entropy).digest()[0]:08b}"[:entropy_bits // 32]
        return " ".join(word_lists[mode][int(bits[i:i+11], 2)] for i in range(0, len(bits), 11))
    alphabet = {
        "eff": word_lists["eff"],
        "ascii": [chr(value) for value in range(33, 127)],
        "pin": list("0123456789"),
        "hex": list("0123456789abcdef"),
    }[mode]
    width = 2 if len(alphabet) > 256 else 1
    source_range = 256**width
    acceptance_limit = source_range - source_range % len(alphabet)
    cursor = 0
    components = []
    while len(components) < length:
        assert cursor + width <= len(random_bytes)
        candidate = int.from_bytes(random_bytes[cursor:cursor+width], "big")
        cursor += width
        if candidate < acceptance_limit:
            components.append(alphabet[candidate % len(alphabet)])
    return (" " if mode == "eff" else "").join(components)


def make_fixture(name, record_count, shuffle_after_records, style, skein, word_lists):
    random = ReferenceRandom(style)
    records = []
    order = []
    for index in range(record_count):
        if len(records) < 4096:
            order.append(len(records))
            records.append(mouse_record(index))
        else:
            records[index % 4096] = mouse_record(index)
        if index + 1 in shuffle_after_records:
            permute(order, random)
    permute(order, random)
    pool = b"".join(records[index] for index in order)
    record_shuffle_requests = random.shuffle_buffer_index
    digest = skein("hash", pool, 128) + hashlib.sha3_512(pool).digest()
    digest_bits = [(byte >> bit) & 1 for byte in digest for bit in range(8)]
    permute(digest_bits, random)
    shuffled_digest = bytes(sum(digest_bits[index * 8 + bit] << bit for bit in range(8)) for index in range(192))
    master = xor(shuffled_digest, random.master_mask())
    output_count = 1024
    material = xor(
        skein("xof", master[:128], output_count),
        hashlib.shake_256(master[128:160]).digest(output_count),
        hashlib.shake_256(master[160:192]).digest(output_count),
    )
    output = xor(material, random.output_mask(output_count))
    configurations = (
        [("bip39", count) for count in [12, 15, 18, 21, 24]]
        + [("eff", 6), ("eff", 60), ("ascii", 8), ("ascii", 256)]
        + [("pin", 3), ("pin", 256), ("hex", 1), ("hex", 3), ("hex", 447), ("hex", 448)]
    )
    return {
        "name": name,
        "recordCount": record_count,
        "shuffleAfterRecords": shuffle_after_records,
        "randomStyle": style,
        "recordShuffleRandomRequests": record_shuffle_requests,
        "randomRequestByteCounts": random.requests,
        "poolByteCount": len(pool),
        "poolSHA256": hashlib.sha256(pool).hexdigest(),
        "digest": digest.hex(),
        "shuffledDigest": shuffled_digest.hex(),
        "master": master.hex(),
        "output": output.hex(),
        "passwords": [
            {"mode": mode, "length": length, "text": password(mode, length, output, word_lists)}
            for mode, length in configurations
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_directory", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path(__file__).with_name("pipeline_expected.json"))
    args = parser.parse_args()
    reference = args.reference_directory.resolve()
    project = pathlib.Path(__file__).resolve().parents[3]
    resources = project / "Sources/PasswordGeneratorCore/Resources"
    word_lists = {
        "bip39": (resources / "english.txt").read_text().splitlines(),
        "eff": [row.split()[1] for row in (resources / "eff_large_wordlist.txt").read_text().splitlines()],
    }
    with tempfile.TemporaryDirectory(prefix="password-generator-pipeline-") as temporary:
        directory = pathlib.Path(temporary)
        harness = directory / "reference.c"
        executable = directory / "reference"
        harness.write_text(C_HARNESS)
        subprocess.run([
            "clang", "-std=c99", "-O2", "-DSKEIN_ERR_CHECK=1", "-I", str(reference),
            str(harness), str(reference / "skein.c"), str(reference / "skein_block.c"), "-o", str(executable),
        ], check=True)

        def skein(mode, input_bytes, count):
            input_file = directory / "input.bin"
            input_file.write_bytes(input_bytes)
            result = subprocess.run([str(executable), mode, str(input_file), str(count)], check=True, capture_output=True).stdout
            assert len(result) == count
            return result

        fixtures = [
            make_fixture("zero_shuffle", 4096, [], "zero", skein, word_lists),
            make_fixture("patterned_shuffle", 4096, [], "patterned", skein, word_lists),
            make_fixture("wrapped_pool_with_intermediate_shuffles", 8193, [2048, 4096, 6144], "patterned", skein, word_lists),
        ]
    args.output.write_text(json.dumps({
        "version": 2,
        "skeinXOFConfigurationOutputBits": str(2**64 - 1),
        "cases": fixtures,
    }, indent=2) + "\n")
    for fixture in fixtures:
        print(f"{fixture['name']}: {fixture['recordCount']} records, {fixture['poolByteCount']} pool bytes, "
              f"{fixture['recordShuffleRandomRequests']} record-shuffle buffers, "
              f"output SHA256 {hashlib.sha256(bytes.fromhex(fixture['output'])).hexdigest()}")


if __name__ == "__main__":
    main()
