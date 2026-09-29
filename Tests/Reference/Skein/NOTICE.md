# Skein 1.3 reference implementation for release verification

This directory vendors the unmodified, byte-for-byte C reference implementation from the Skein authors. It is used only by `Scripts/skein-reference-checksum.sh` to independently verify release files. It is not linked into, copied into, or executed by the macOS application, and it does not depend on the Swift implementation.

## Provenance

- Project and original download link: https://www.schneier.com/academic/skein/
- Specification, version 1.3 (1 October 2010): https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf
- Original archive: https://www.schneier.com/wp-content/uploads/2015/01/skein.zip
- Archive SHA-256: `121b73a4d5300b4977d3757064a29ba5e11c0fb01786171b2bc729ef099b89ad`
- Upstream directory: `NIST/CD/Reference_Implementation/`
- Retrieved and checked: 29 September 2026.

The five upstream files retain their original contents and line endings:

| File | SHA-256 |
|---|---|
| `skein.c` | `73cff8b3470ba1bf8fef7adc99fc1b78a58682a39debdbdba337e74e2c0899b9` |
| `skein_block.c` | `8a310dce6a17b98fcf061faa9e75a82f70b535c174a1d2ba8c8b0b27804bbce8` |
| `skein.h` | `2988f8efa71095441b31654a51034df50a74f09912c6f9fcb4bd14dece37d30d` |
| `skein_port.h` | `e99efc1a1e09a2307379576fb2096e5ae06ada34f92a60845917dd99f09ad2b8` |
| `brg_types.h` | `240329b4ca4d829ac4d1490e96e83118e161e719e448c7e8dbf15735ab8a8e87` |

`file_checksum.c` is the local file-I/O adapter. It calls the original `Skein1024_Init` with a 1024-bit output length, streams the input through `Skein1024_Update`, and finishes with `Skein1024_Final`. This is the fixed Skein-1024-1024 digest, not the application's separately configured Skein XOF. No upstream cryptographic source was changed.

The shell script compiles with the original error checks enabled (`SKEIN_ERR_CHECK=1`) into a private temporary directory and removes that directory on exit. The verifier works offline after checkout, requires Apple's C compiler through `xcrun`, and writes exactly 256 lowercase hexadecimal characters to standard output, without a trailing newline. Errors and compiler diagnostics go to standard error and return a nonzero exit status. It does not install or cache a binary.

## Licenses and attribution

The headers of `skein.c`, `skein_block.c`, `skein.h` and `skein_port.h` credit Doug Whiting (2008) and release the algorithm and source code to the public domain. `skein_port.h` additionally thanks Brian Gladman for his portable headers.

`brg_types.h` is distributed here under its permissive license option, reproduced below. This is separate from the Skein public-domain dedication; the optional GPL alternative is not selected. The full original notice also remains in the unmodified header.

```text
Copyright (c) 1998-2006, Brian Gladman, Worcester, UK. All rights reserved.

 LICENSE TERMS

 The free distribution and use of this software in both source and binary
 form is allowed (with or without changes) provided that:

   1. distributions of this source code include the above copyright
      notice, this list of conditions and the following disclaimer;

   2. distributions in binary form include the above copyright
      notice, this list of conditions and the following disclaimer
      in the documentation and/or other associated materials;

   3. the copyright holder's name is not used to endorse products
      built using this software without specific written permission.

 ALTERNATIVELY, provided that this notice is retained in full, this product
 may be distributed under the terms of the GNU General Public License (GPL),
 in which case the provisions of the GPL apply INSTEAD OF those given above.

 DISCLAIMER

 This software is provided 'as is' with no explicit or implied warranties
 in respect of its properties, including, but not limited to, correctness
 and/or fitness for purpose.
```

The local adapter `file_checksum.c` and wrapper `Scripts/skein-reference-checksum.sh` are original project code; this notice does not grant or change their license.

## Verification scope

The reference checksum is checked against the repository's 36 official, byte-oriented Skein-1024-1024 golden vectors and 13 additional independent C-reference boundary fixtures. The latter include empty, 128-byte, 129-byte and multi-block inputs. Release verification compares this separate C implementation with the Swift checksum implementation; agreement is an implementation consistency check, not an external security audit or proof of file authenticity.

The file adapter was also checked with 65,535, 65,536, 65,537 and 131,073-byte files against a separately compiled original C-reference driver using 4,096-byte reads. All 49 fixture invocations checked the exact output format, execution from another working directory, paths containing spaces and temporary-directory cleanup. Missing or extra arguments, a missing file and a directory were verified to fail with empty standard output.
