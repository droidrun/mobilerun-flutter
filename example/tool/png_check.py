#!/usr/bin/env python3
# Copyright 2026 Mobilerun
# SPDX-License-Identifier: Apache-2.0
"""Pixel checks on emulator screenshots, without third-party packages.

  png_check.py IMAGE.png --lit MIN_FRACTION
      Exit 0 when at least MIN_FRACTION of the pixels in the video rectangle
      are not black, i.e. the device picture is on screen.
  png_check.py IMAGE.png --differs-from OTHER.png MIN_FRACTION
      Exit 0 when at least MIN_FRACTION of the pixels in the video rectangle
      differ from the other image (the device screen changed).

The video rectangle is the lower 60 % of the screen, below the status line
of the example app. Prints one line with the measured fraction.
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
    pos, idat, width, height, color = 8, [], 0, 0, 0
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and color in (2, 6) and interlace == 0, 'unsupported PNG'
        elif kind == b'IDAT':
            idat.append(body)
    channels = 4 if color == 6 else 3
    raw = zlib.decompress(b''.join(idat))
    stride = width * channels
    rows, prev = [], bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        rows.append(line)
        prev = line
    return width, height, channels, rows


def rect_rows(height):
    return range(int(height * 0.4), int(height * 0.95))


def lit_fraction(path):
    width, height, ch, rows = read_png(path)
    lit = total = 0
    for y in rect_rows(height):
        row = rows[y]
        for x in range(0, width, 4):
            total += 1
            if max(row[x * ch:x * ch + 3]) > 40:
                lit += 1
    return lit / total


def diff_fraction(path, other):
    width, height, ch, rows = read_png(path)
    _, _, _, rows2 = read_png(other)
    diff = total = 0
    for y in rect_rows(height):
        a, b = rows[y], rows2[y]
        for x in range(0, width, 4):
            total += 1
            o = x * ch
            if sum(abs(a[o + k] - b[o + k]) for k in range(3)) > 60:
                diff += 1
    return diff / total


def main(argv):
    if len(argv) == 4 and argv[2] == '--lit':
        fraction = lit_fraction(argv[1])
        print(f'{argv[1]}: lit fraction {fraction:.3f} (need {argv[3]})')
        return 0 if fraction >= float(argv[3]) else 1
    if len(argv) == 5 and argv[2] == '--differs-from':
        fraction = diff_fraction(argv[1], argv[3])
        print(f'{argv[1]}: differs from {argv[3]} in {fraction:.3f} (need {argv[4]})')
        return 0 if fraction >= float(argv[4]) else 1
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
