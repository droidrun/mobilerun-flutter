# Third-party notices

Mobilerun Flutter is licensed under [Apache-2.0](LICENSE). Its dependencies keep
their own licenses. This inventory covers the WebRTC integration used by the
Android and iOS SDK; it is not a complete license inventory of a consuming app.
No precompiled native WebRTC library is checked into this repository. Dependency
tools fetch native libraries when building the host app.

## WebRTC dependency inventory

The versions below describe `flutter_webrtc` 1.6.3, allowed by this SDK's
`^1.6.3` constraint. Check the app's resolved versions when upgrading:

| Component | Selected through | License and upstream sources |
| --- | --- | --- |
| `flutter_webrtc` 1.6.3 | `pubspec.yaml` | MIT; additional notices in the package's `NOTICE`, reproduced below. [Source and license](https://pub.dev/packages/flutter_webrtc/versions/1.6.3). |
| Android native WebRTC `io.github.webrtc-sdk:android:150.7871.04` | `flutter_webrtc/android/build.gradle` | BSD-3-Clause for WebRTC; the artifact POM declares this license. [Artifact metadata](https://repo.maven.apache.org/maven2/io/github/webrtc-sdk/android/150.7871.04/android-150.7871.04.pom), [upstream](https://github.com/webrtc-sdk/android/tree/v150.7871.04). |
| iOS native `WebRTC-SDK` 150.7871.04 | `flutter_webrtc/ios/flutter_webrtc.podspec` | The [upstream podspec](https://github.com/webrtc-sdk/Specs/blob/150.7871.04/WebRTC-SDK.podspec) declares BSD and points to `WebRTC.xcframework/LICENSE` in the downloaded framework. |

WebRTC's BSD license is reproduced below from the
[upstream M150 source](https://github.com/webrtc-sdk/webrtc/blob/m150_release/LICENSE).
Native builds also incorporate third-party code with its own licenses; the
WebRTC license alone is not the full notice set for a native binary.

## Redistributing an app

- Retain the `flutter_webrtc` MIT copyright and permission notice and its
  additional `NOTICE` text, reproduced below, in your app's third-party notices.
- For each resolved native WebRTC artifact, inspect and retain its license,
  copyright and third-party notices. Include applicable notices in documentation
  or other materials supplied with the app, including an accessible licenses
  screen or bundled notice file. Preserve any applicable patent notices too.
- Inspect the actual Android artifacts and iOS `WebRTC.xcframework` used by your
  build, including `LICENSE` and any `NOTICE`/third-party license files. If an
  archive omits notices, obtain the matching build's notice bundle from its
  distributor before shipping. This file does not replace that bundle.
- Include the rest of your app's dependency notices. Flutter's `LicenseRegistry`
  and `showLicensePage` can expose package notices, but verify that the generated
  output also contains native binary notices; do not assume it collects them.

## flutter_webrtc LICENSE (1.6.3)

```text
MIT License

Copyright (c) 2018 湖北捷智云技术有限公司

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## flutter_webrtc NOTICE (1.6.3)

```text
###################################################################################

The following modifications follow Apache License 2.0 from shiguredo.

SimulcastVideoEncoderFactoryWrapper.kt

Apache License 2.0

Copyright 2017, Lyo Kato <lyo.kato at gmail.com> (Original Author)
Copyright 2017-2021, Shiguredo Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

#####################################################################################

react-native-webrtc
https://github.com/react-native-webrtc/react-native-webrtc

The MIT License (MIT)

Copyright (c) 2015 Howard Yang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

#####################################################################################
```

## WebRTC LICENSE (M150)

```text
Copyright (c) 2011, The WebRTC project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
