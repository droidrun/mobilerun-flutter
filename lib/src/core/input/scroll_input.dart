// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:ui';

enum ScrollUnit { pixel, line, page }

/// React's DOM wheel conversion; the S1 encoder applies ticks / 16.
Offset scrollTicks(Offset delta, {ScrollUnit unit = ScrollUnit.pixel}) =>
    delta *
    switch (unit) {
      ScrollUnit.pixel => -0.01,
      ScrollUnit.line => -1.0,
      ScrollUnit.page => -3.0,
    };
