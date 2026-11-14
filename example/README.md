# Mobilerun stream example

Enter a stream URL and token and press Connect: the app opens a
`DeviceStreamSession`, shows its status and embeds the SDK's `DeviceStream`.
Tap the picture to focus input; the keyboard button opens the local IME.

`tool/e2e_android.sh` drives the scripted entry point `lib/e2e_main.dart`
(`flutter build apk --debug -t lib/e2e_main.dart`) on an Android emulator
against a cloud device. It checks video pixels, touch/swipe, two-finger
packets, rotated-view mapping, IME/hardware input, navigation, hover and scroll.
Credentials are supplied as a private runtime file; they are never bundled.
