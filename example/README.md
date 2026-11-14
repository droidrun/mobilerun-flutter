# Mobilerun stream example

Enter a stream URL and token and press Connect: the app opens a
`DeviceStreamSession`, shows its status and renders the device video.

`tool/e2e_android.sh` drives the scripted entry point `lib/e2e_main.dart`
(`flutter build apk --debug -t lib/e2e_main.dart`) on an Android emulator
against a cloud device.
