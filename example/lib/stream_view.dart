// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Example status line and the SDK video/input view.
class StreamView extends StatelessWidget {
  const StreamView({super.key, required this.session, this.controller});

  final DeviceStreamSession session;
  final DeviceStreamController? controller;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListenableBuilder(
        listenable: Listenable.merge([session.status, session.videoSize]),
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${session.status.value}  ${session.videoSize.value ?? ""}',
            key: const Key('status'),
          ),
        ),
      ),
      Expanded(
        child: ColoredBox(
          color: Colors.black,
          child: DeviceStream(
            session: session,
            hasControl: true,
            controller: controller,
            autofocus: true,
          ),
        ),
      ),
    ],
  );
}
