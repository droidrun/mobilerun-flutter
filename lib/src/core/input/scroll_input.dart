// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:ui';

/// Flutter scroll deltas are pixels; the S1 encoder applies ticks / 16.
Offset scrollTicks(Offset delta) => delta * -0.01;
