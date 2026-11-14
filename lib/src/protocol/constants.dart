// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: conformance/fixtures/constants.json
// Regenerate with: dart run tool/generate_constants.dart

/// Type byte of each binary control message.
abstract final class ControlMessageType {
  ControlMessageType._();

  /// `INJECT_KEYCODE`.
  static const int injectKeycode = 0;

  /// `INJECT_TEXT`.
  static const int injectText = 1;

  /// `INJECT_TOUCH_EVENT`.
  static const int injectTouchEvent = 2;

  /// `INJECT_SCROLL_EVENT`.
  static const int injectScrollEvent = 3;

  /// `BACK_OR_SCREEN_ON`.
  static const int backOrScreenOn = 4;

  /// `EXPAND_NOTIFICATION_PANEL`.
  static const int expandNotificationPanel = 5;

  /// `EXPAND_SETTINGS_PANEL`.
  static const int expandSettingsPanel = 6;

  /// `COLLAPSE_PANELS`.
  static const int collapsePanels = 7;

  /// `GET_CLIPBOARD`.
  static const int getClipboard = 8;

  /// `SET_CLIPBOARD`.
  static const int setClipboard = 9;

  /// `SET_DISPLAY_POWER`.
  static const int setDisplayPower = 10;

  /// `ROTATE_DEVICE`.
  static const int rotateDevice = 11;

  /// `INJECT_MOUSE_HOVER_EVENT`.
  static const int injectMouseHoverEvent = 21;

  /// Every constant of this class by its wire name.
  static const Map<String, int> values = {
    'INJECT_KEYCODE': injectKeycode,
    'INJECT_TEXT': injectText,
    'INJECT_TOUCH_EVENT': injectTouchEvent,
    'INJECT_SCROLL_EVENT': injectScrollEvent,
    'BACK_OR_SCREEN_ON': backOrScreenOn,
    'EXPAND_NOTIFICATION_PANEL': expandNotificationPanel,
    'EXPAND_SETTINGS_PANEL': expandSettingsPanel,
    'COLLAPSE_PANELS': collapsePanels,
    'GET_CLIPBOARD': getClipboard,
    'SET_CLIPBOARD': setClipboard,
    'SET_DISPLAY_POWER': setDisplayPower,
    'ROTATE_DEVICE': rotateDevice,
    'INJECT_MOUSE_HOVER_EVENT': injectMouseHoverEvent,
  };
}

/// Android `MotionEvent` actions and mouse button flags used by touch messages.
abstract final class AndroidMotionEvent {
  AndroidMotionEvent._();

  /// `ACTION_DOWN`.
  static const int actionDown = 0;

  /// `ACTION_UP`.
  static const int actionUp = 1;

  /// `ACTION_MOVE`.
  static const int actionMove = 2;

  /// `ACTION_CANCEL`.
  static const int actionCancel = 3;

  /// `ACTION_POINTER_DOWN`.
  static const int actionPointerDown = 5;

  /// `ACTION_POINTER_UP`.
  static const int actionPointerUp = 6;

  /// `BUTTON_PRIMARY`.
  static const int buttonPrimary = 1;

  /// `BUTTON_SECONDARY`.
  static const int buttonSecondary = 2;

  /// `BUTTON_TERTIARY`.
  static const int buttonTertiary = 4;

  /// Every constant of this class by its wire name.
  static const Map<String, int> values = {
    'ACTION_DOWN': actionDown,
    'ACTION_UP': actionUp,
    'ACTION_MOVE': actionMove,
    'ACTION_CANCEL': actionCancel,
    'ACTION_POINTER_DOWN': actionPointerDown,
    'ACTION_POINTER_UP': actionPointerUp,
    'BUTTON_PRIMARY': buttonPrimary,
    'BUTTON_SECONDARY': buttonSecondary,
    'BUTTON_TERTIARY': buttonTertiary,
  };
}

/// Android `KeyEvent` actions, meta state flags and key codes used by keycode messages.
abstract final class AndroidKeys {
  AndroidKeys._();

  /// `ACTION_DOWN`.
  static const int actionDown = 0;

  /// `ACTION_UP`.
  static const int actionUp = 1;

  /// `META_NONE`.
  static const int metaNone = 0;

  /// `META_SHIFT_ON`.
  static const int metaShiftOn = 1;

  /// `META_ALT_ON`.
  static const int metaAltOn = 2;

  /// `META_CTRL_ON`.
  static const int metaCtrlOn = 4096;

  /// `META_META_ON`.
  static const int metaMetaOn = 65536;

  /// `KEYCODE_UNKNOWN`.
  static const int keycodeUnknown = 0;

  /// `KEYCODE_SOFT_LEFT`.
  static const int keycodeSoftLeft = 1;

  /// `KEYCODE_SOFT_RIGHT`.
  static const int keycodeSoftRight = 2;

  /// `KEYCODE_HOME`.
  static const int keycodeHome = 3;

  /// `KEYCODE_BACK`.
  static const int keycodeBack = 4;

  /// `KEYCODE_CALL`.
  static const int keycodeCall = 5;

  /// `KEYCODE_ENDCALL`.
  static const int keycodeEndcall = 6;

  /// `KEYCODE_0`.
  static const int keycode0 = 7;

  /// `KEYCODE_1`.
  static const int keycode1 = 8;

  /// `KEYCODE_2`.
  static const int keycode2 = 9;

  /// `KEYCODE_3`.
  static const int keycode3 = 10;

  /// `KEYCODE_4`.
  static const int keycode4 = 11;

  /// `KEYCODE_5`.
  static const int keycode5 = 12;

  /// `KEYCODE_6`.
  static const int keycode6 = 13;

  /// `KEYCODE_7`.
  static const int keycode7 = 14;

  /// `KEYCODE_8`.
  static const int keycode8 = 15;

  /// `KEYCODE_9`.
  static const int keycode9 = 16;

  /// `KEYCODE_STAR`.
  static const int keycodeStar = 17;

  /// `KEYCODE_POUND`.
  static const int keycodePound = 18;

  /// `DPAD_UP`.
  static const int dpadUp = 19;

  /// `DPAD_DOWN`.
  static const int dpadDown = 20;

  /// `DPAD_LEFT`.
  static const int dpadLeft = 21;

  /// `DPAD_RIGHT`.
  static const int dpadRight = 22;

  /// `KEYCODE_DPAD_CENTER`.
  static const int keycodeDpadCenter = 23;

  /// `KEYCODE_VOLUME_UP`.
  static const int keycodeVolumeUp = 24;

  /// `KEYCODE_VOLUME_DOWN`.
  static const int keycodeVolumeDown = 25;

  /// `KEYCODE_POWER`.
  static const int keycodePower = 26;

  /// `KEYCODE_CAMERA`.
  static const int keycodeCamera = 27;

  /// `KEYCODE_CLEAR`.
  static const int keycodeClear = 28;

  /// `KEYCODE_A`.
  static const int keycodeA = 29;

  /// `KEYCODE_B`.
  static const int keycodeB = 30;

  /// `KEYCODE_C`.
  static const int keycodeC = 31;

  /// `KEYCODE_D`.
  static const int keycodeD = 32;

  /// `KEYCODE_E`.
  static const int keycodeE = 33;

  /// `KEYCODE_F`.
  static const int keycodeF = 34;

  /// `KEYCODE_G`.
  static const int keycodeG = 35;

  /// `KEYCODE_H`.
  static const int keycodeH = 36;

  /// `KEYCODE_I`.
  static const int keycodeI = 37;

  /// `KEYCODE_J`.
  static const int keycodeJ = 38;

  /// `KEYCODE_K`.
  static const int keycodeK = 39;

  /// `KEYCODE_L`.
  static const int keycodeL = 40;

  /// `KEYCODE_M`.
  static const int keycodeM = 41;

  /// `KEYCODE_N`.
  static const int keycodeN = 42;

  /// `KEYCODE_O`.
  static const int keycodeO = 43;

  /// `KEYCODE_P`.
  static const int keycodeP = 44;

  /// `KEYCODE_Q`.
  static const int keycodeQ = 45;

  /// `KEYCODE_R`.
  static const int keycodeR = 46;

  /// `KEYCODE_S`.
  static const int keycodeS = 47;

  /// `KEYCODE_T`.
  static const int keycodeT = 48;

  /// `KEYCODE_U`.
  static const int keycodeU = 49;

  /// `KEYCODE_V`.
  static const int keycodeV = 50;

  /// `KEYCODE_W`.
  static const int keycodeW = 51;

  /// `KEYCODE_X`.
  static const int keycodeX = 52;

  /// `KEYCODE_Y`.
  static const int keycodeY = 53;

  /// `KEYCODE_Z`.
  static const int keycodeZ = 54;

  /// `KEYCODE_COMMA`.
  static const int keycodeComma = 55;

  /// `KEYCODE_PERIOD`.
  static const int keycodePeriod = 56;

  /// `KEYCODE_ALT_LEFT`.
  static const int keycodeAltLeft = 57;

  /// `KEYCODE_ALT_RIGHT`.
  static const int keycodeAltRight = 58;

  /// `KEYCODE_SHIFT_LEFT`.
  static const int keycodeShiftLeft = 59;

  /// `KEYCODE_SHIFT_RIGHT`.
  static const int keycodeShiftRight = 60;

  /// `KEYCODE_TAB`.
  static const int keycodeTab = 61;

  /// `KEYCODE_SPACE`.
  static const int keycodeSpace = 62;

  /// `KEYCODE_SYM`.
  static const int keycodeSym = 63;

  /// `KEYCODE_EXPLORER`.
  static const int keycodeExplorer = 64;

  /// `KEYCODE_ENVELOPE`.
  static const int keycodeEnvelope = 65;

  /// `ENTER`.
  static const int enter = 66;

  /// `DEL`.
  static const int del = 67;

  /// `KEYCODE_GRAVE`.
  static const int keycodeGrave = 68;

  /// `KEYCODE_MINUS`.
  static const int keycodeMinus = 69;

  /// `KEYCODE_EQUALS`.
  static const int keycodeEquals = 70;

  /// `KEYCODE_LEFT_BRACKET`.
  static const int keycodeLeftBracket = 71;

  /// `KEYCODE_RIGHT_BRACKET`.
  static const int keycodeRightBracket = 72;

  /// `KEYCODE_BACKSLASH`.
  static const int keycodeBackslash = 73;

  /// `KEYCODE_SEMICOLON`.
  static const int keycodeSemicolon = 74;

  /// `KEYCODE_APOSTROPHE`.
  static const int keycodeApostrophe = 75;

  /// `KEYCODE_SLASH`.
  static const int keycodeSlash = 76;

  /// `KEYCODE_AT`.
  static const int keycodeAt = 77;

  /// `KEYCODE_NUM`.
  static const int keycodeNum = 78;

  /// `KEYCODE_HEADSETHOOK`.
  static const int keycodeHeadsethook = 79;

  /// `KEYCODE_FOCUS`.
  static const int keycodeFocus = 80;

  /// `KEYCODE_PLUS`.
  static const int keycodePlus = 81;

  /// `MENU`.
  static const int menu = 82;

  /// `KEYCODE_NOTIFICATION`.
  static const int keycodeNotification = 83;

  /// `KEYCODE_SEARCH`.
  static const int keycodeSearch = 84;

  /// `KEYCODE_MEDIA_PLAY_PAUSE`.
  static const int keycodeMediaPlayPause = 85;

  /// `KEYCODE_MEDIA_STOP`.
  static const int keycodeMediaStop = 86;

  /// `KEYCODE_MEDIA_NEXT`.
  static const int keycodeMediaNext = 87;

  /// `KEYCODE_MEDIA_PREVIOUS`.
  static const int keycodeMediaPrevious = 88;

  /// `KEYCODE_MEDIA_REWIND`.
  static const int keycodeMediaRewind = 89;

  /// `KEYCODE_MEDIA_FAST_FORWARD`.
  static const int keycodeMediaFastForward = 90;

  /// `KEYCODE_MUTE`.
  static const int keycodeMute = 91;

  /// `KEYCODE_PAGE_UP`.
  static const int keycodePageUp = 92;

  /// `KEYCODE_PAGE_DOWN`.
  static const int keycodePageDown = 93;

  /// `KEYCODE_PICTSYMBOLS`.
  static const int keycodePictsymbols = 94;

  /// `KEYCODE_SWITCH_CHARSET`.
  static const int keycodeSwitchCharset = 95;

  /// `KEYCODE_BUTTON_A`.
  static const int keycodeButtonA = 96;

  /// `KEYCODE_BUTTON_B`.
  static const int keycodeButtonB = 97;

  /// `KEYCODE_BUTTON_C`.
  static const int keycodeButtonC = 98;

  /// `KEYCODE_BUTTON_X`.
  static const int keycodeButtonX = 99;

  /// `KEYCODE_BUTTON_Y`.
  static const int keycodeButtonY = 100;

  /// `KEYCODE_BUTTON_Z`.
  static const int keycodeButtonZ = 101;

  /// `KEYCODE_BUTTON_L1`.
  static const int keycodeButtonL1 = 102;

  /// `KEYCODE_BUTTON_R1`.
  static const int keycodeButtonR1 = 103;

  /// `KEYCODE_BUTTON_L2`.
  static const int keycodeButtonL2 = 104;

  /// `KEYCODE_BUTTON_R2`.
  static const int keycodeButtonR2 = 105;

  /// `KEYCODE_BUTTON_THUMBL`.
  static const int keycodeButtonThumbl = 106;

  /// `KEYCODE_BUTTON_THUMBR`.
  static const int keycodeButtonThumbr = 107;

  /// `KEYCODE_BUTTON_START`.
  static const int keycodeButtonStart = 108;

  /// `KEYCODE_BUTTON_SELECT`.
  static const int keycodeButtonSelect = 109;

  /// `KEYCODE_BUTTON_MODE`.
  static const int keycodeButtonMode = 110;

  /// `KEYCODE_ESCAPE`.
  static const int keycodeEscape = 111;

  /// `FORWARD_DEL`.
  static const int forwardDel = 112;

  /// `KEYCODE_CTRL_LEFT`.
  static const int keycodeCtrlLeft = 113;

  /// `KEYCODE_CTRL_RIGHT`.
  static const int keycodeCtrlRight = 114;

  /// `KEYCODE_CAPS_LOCK`.
  static const int keycodeCapsLock = 115;

  /// `KEYCODE_SCROLL_LOCK`.
  static const int keycodeScrollLock = 116;

  /// `KEYCODE_META_LEFT`.
  static const int keycodeMetaLeft = 117;

  /// `KEYCODE_META_RIGHT`.
  static const int keycodeMetaRight = 118;

  /// `KEYCODE_FUNCTION`.
  static const int keycodeFunction = 119;

  /// `KEYCODE_SYSRQ`.
  static const int keycodeSysrq = 120;

  /// `KEYCODE_BREAK`.
  static const int keycodeBreak = 121;

  /// `KEYCODE_MOVE_HOME`.
  static const int keycodeMoveHome = 122;

  /// `KEYCODE_MOVE_END`.
  static const int keycodeMoveEnd = 123;

  /// `KEYCODE_INSERT`.
  static const int keycodeInsert = 124;

  /// `KEYCODE_FORWARD`.
  static const int keycodeForward = 125;

  /// `KEYCODE_MEDIA_PLAY`.
  static const int keycodeMediaPlay = 126;

  /// `KEYCODE_MEDIA_PAUSE`.
  static const int keycodeMediaPause = 127;

  /// `KEYCODE_MEDIA_CLOSE`.
  static const int keycodeMediaClose = 128;

  /// `KEYCODE_MEDIA_EJECT`.
  static const int keycodeMediaEject = 129;

  /// `KEYCODE_MEDIA_RECORD`.
  static const int keycodeMediaRecord = 130;

  /// `KEYCODE_F1`.
  static const int keycodeF1 = 131;

  /// `KEYCODE_F2`.
  static const int keycodeF2 = 132;

  /// `KEYCODE_F3`.
  static const int keycodeF3 = 133;

  /// `KEYCODE_F4`.
  static const int keycodeF4 = 134;

  /// `KEYCODE_F5`.
  static const int keycodeF5 = 135;

  /// `KEYCODE_F6`.
  static const int keycodeF6 = 136;

  /// `KEYCODE_F7`.
  static const int keycodeF7 = 137;

  /// `KEYCODE_F8`.
  static const int keycodeF8 = 138;

  /// `KEYCODE_F9`.
  static const int keycodeF9 = 139;

  /// `KEYCODE_F10`.
  static const int keycodeF10 = 140;

  /// `KEYCODE_F11`.
  static const int keycodeF11 = 141;

  /// `KEYCODE_F12`.
  static const int keycodeF12 = 142;

  /// `KEYCODE_NUM_LOCK`.
  static const int keycodeNumLock = 143;

  /// `KEYCODE_NUMPAD_0`.
  static const int keycodeNumpad0 = 144;

  /// `KEYCODE_NUMPAD_1`.
  static const int keycodeNumpad1 = 145;

  /// `KEYCODE_NUMPAD_2`.
  static const int keycodeNumpad2 = 146;

  /// `KEYCODE_NUMPAD_3`.
  static const int keycodeNumpad3 = 147;

  /// `KEYCODE_NUMPAD_4`.
  static const int keycodeNumpad4 = 148;

  /// `KEYCODE_NUMPAD_5`.
  static const int keycodeNumpad5 = 149;

  /// `KEYCODE_NUMPAD_6`.
  static const int keycodeNumpad6 = 150;

  /// `KEYCODE_NUMPAD_7`.
  static const int keycodeNumpad7 = 151;

  /// `KEYCODE_NUMPAD_8`.
  static const int keycodeNumpad8 = 152;

  /// `KEYCODE_NUMPAD_9`.
  static const int keycodeNumpad9 = 153;

  /// `KEYCODE_NUMPAD_DIVIDE`.
  static const int keycodeNumpadDivide = 154;

  /// `KEYCODE_NUMPAD_MULTIPLY`.
  static const int keycodeNumpadMultiply = 155;

  /// `KEYCODE_NUMPAD_SUBTRACT`.
  static const int keycodeNumpadSubtract = 156;

  /// `KEYCODE_NUMPAD_ADD`.
  static const int keycodeNumpadAdd = 157;

  /// `KEYCODE_NUMPAD_DOT`.
  static const int keycodeNumpadDot = 158;

  /// `KEYCODE_NUMPAD_COMMA`.
  static const int keycodeNumpadComma = 159;

  /// `KEYCODE_NUMPAD_ENTER`.
  static const int keycodeNumpadEnter = 160;

  /// `KEYCODE_NUMPAD_EQUALS`.
  static const int keycodeNumpadEquals = 161;

  /// `KEYCODE_NUMPAD_LEFT_PAREN`.
  static const int keycodeNumpadLeftParen = 162;

  /// `KEYCODE_NUMPAD_RIGHT_PAREN`.
  static const int keycodeNumpadRightParen = 163;

  /// `KEYCODE_VOLUME_MUTE`.
  static const int keycodeVolumeMute = 164;

  /// `KEYCODE_INFO`.
  static const int keycodeInfo = 165;

  /// `KEYCODE_CHANNEL_UP`.
  static const int keycodeChannelUp = 166;

  /// `KEYCODE_CHANNEL_DOWN`.
  static const int keycodeChannelDown = 167;

  /// `KEYCODE_ZOOM_IN`.
  static const int keycodeZoomIn = 168;

  /// `KEYCODE_ZOOM_OUT`.
  static const int keycodeZoomOut = 169;

  /// `KEYCODE_TV`.
  static const int keycodeTv = 170;

  /// `KEYCODE_WINDOW`.
  static const int keycodeWindow = 171;

  /// `KEYCODE_GUIDE`.
  static const int keycodeGuide = 172;

  /// `KEYCODE_DVR`.
  static const int keycodeDvr = 173;

  /// `KEYCODE_BOOKMARK`.
  static const int keycodeBookmark = 174;

  /// `KEYCODE_CAPTIONS`.
  static const int keycodeCaptions = 175;

  /// `KEYCODE_SETTINGS`.
  static const int keycodeSettings = 176;

  /// `KEYCODE_TV_POWER`.
  static const int keycodeTvPower = 177;

  /// `KEYCODE_TV_INPUT`.
  static const int keycodeTvInput = 178;

  /// `KEYCODE_STB_POWER`.
  static const int keycodeStbPower = 179;

  /// `KEYCODE_STB_INPUT`.
  static const int keycodeStbInput = 180;

  /// `KEYCODE_AVR_POWER`.
  static const int keycodeAvrPower = 181;

  /// `KEYCODE_AVR_INPUT`.
  static const int keycodeAvrInput = 182;

  /// `KEYCODE_PROG_RED`.
  static const int keycodeProgRed = 183;

  /// `KEYCODE_PROG_GREEN`.
  static const int keycodeProgGreen = 184;

  /// `KEYCODE_PROG_YELLOW`.
  static const int keycodeProgYellow = 185;

  /// `KEYCODE_PROG_BLUE`.
  static const int keycodeProgBlue = 186;

  /// `KEYCODE_APP_SWITCH`.
  static const int keycodeAppSwitch = 187;

  /// `KEYCODE_LANGUAGE_SWITCH`.
  static const int keycodeLanguageSwitch = 204;

  /// `KEYCODE_ASSIST`.
  static const int keycodeAssist = 219;

  /// `KEYCODE_BRIGHTNESS_DOWN`.
  static const int keycodeBrightnessDown = 220;

  /// `KEYCODE_BRIGHTNESS_UP`.
  static const int keycodeBrightnessUp = 221;

  /// `KEYCODE_SLEEP`.
  static const int keycodeSleep = 223;

  /// `KEYCODE_WAKEUP`.
  static const int keycodeWakeup = 224;

  /// `KEYCODE_SOFT_SLEEP`.
  static const int keycodeSoftSleep = 276;

  /// Every constant of this class by its wire name.
  static const Map<String, int> values = {
    'ACTION_DOWN': actionDown,
    'ACTION_UP': actionUp,
    'META_NONE': metaNone,
    'META_SHIFT_ON': metaShiftOn,
    'META_ALT_ON': metaAltOn,
    'META_CTRL_ON': metaCtrlOn,
    'META_META_ON': metaMetaOn,
    'KEYCODE_UNKNOWN': keycodeUnknown,
    'KEYCODE_SOFT_LEFT': keycodeSoftLeft,
    'KEYCODE_SOFT_RIGHT': keycodeSoftRight,
    'KEYCODE_HOME': keycodeHome,
    'KEYCODE_BACK': keycodeBack,
    'KEYCODE_CALL': keycodeCall,
    'KEYCODE_ENDCALL': keycodeEndcall,
    'KEYCODE_0': keycode0,
    'KEYCODE_1': keycode1,
    'KEYCODE_2': keycode2,
    'KEYCODE_3': keycode3,
    'KEYCODE_4': keycode4,
    'KEYCODE_5': keycode5,
    'KEYCODE_6': keycode6,
    'KEYCODE_7': keycode7,
    'KEYCODE_8': keycode8,
    'KEYCODE_9': keycode9,
    'KEYCODE_STAR': keycodeStar,
    'KEYCODE_POUND': keycodePound,
    'DPAD_UP': dpadUp,
    'DPAD_DOWN': dpadDown,
    'DPAD_LEFT': dpadLeft,
    'DPAD_RIGHT': dpadRight,
    'KEYCODE_DPAD_CENTER': keycodeDpadCenter,
    'KEYCODE_VOLUME_UP': keycodeVolumeUp,
    'KEYCODE_VOLUME_DOWN': keycodeVolumeDown,
    'KEYCODE_POWER': keycodePower,
    'KEYCODE_CAMERA': keycodeCamera,
    'KEYCODE_CLEAR': keycodeClear,
    'KEYCODE_A': keycodeA,
    'KEYCODE_B': keycodeB,
    'KEYCODE_C': keycodeC,
    'KEYCODE_D': keycodeD,
    'KEYCODE_E': keycodeE,
    'KEYCODE_F': keycodeF,
    'KEYCODE_G': keycodeG,
    'KEYCODE_H': keycodeH,
    'KEYCODE_I': keycodeI,
    'KEYCODE_J': keycodeJ,
    'KEYCODE_K': keycodeK,
    'KEYCODE_L': keycodeL,
    'KEYCODE_M': keycodeM,
    'KEYCODE_N': keycodeN,
    'KEYCODE_O': keycodeO,
    'KEYCODE_P': keycodeP,
    'KEYCODE_Q': keycodeQ,
    'KEYCODE_R': keycodeR,
    'KEYCODE_S': keycodeS,
    'KEYCODE_T': keycodeT,
    'KEYCODE_U': keycodeU,
    'KEYCODE_V': keycodeV,
    'KEYCODE_W': keycodeW,
    'KEYCODE_X': keycodeX,
    'KEYCODE_Y': keycodeY,
    'KEYCODE_Z': keycodeZ,
    'KEYCODE_COMMA': keycodeComma,
    'KEYCODE_PERIOD': keycodePeriod,
    'KEYCODE_ALT_LEFT': keycodeAltLeft,
    'KEYCODE_ALT_RIGHT': keycodeAltRight,
    'KEYCODE_SHIFT_LEFT': keycodeShiftLeft,
    'KEYCODE_SHIFT_RIGHT': keycodeShiftRight,
    'KEYCODE_TAB': keycodeTab,
    'KEYCODE_SPACE': keycodeSpace,
    'KEYCODE_SYM': keycodeSym,
    'KEYCODE_EXPLORER': keycodeExplorer,
    'KEYCODE_ENVELOPE': keycodeEnvelope,
    'ENTER': enter,
    'DEL': del,
    'KEYCODE_GRAVE': keycodeGrave,
    'KEYCODE_MINUS': keycodeMinus,
    'KEYCODE_EQUALS': keycodeEquals,
    'KEYCODE_LEFT_BRACKET': keycodeLeftBracket,
    'KEYCODE_RIGHT_BRACKET': keycodeRightBracket,
    'KEYCODE_BACKSLASH': keycodeBackslash,
    'KEYCODE_SEMICOLON': keycodeSemicolon,
    'KEYCODE_APOSTROPHE': keycodeApostrophe,
    'KEYCODE_SLASH': keycodeSlash,
    'KEYCODE_AT': keycodeAt,
    'KEYCODE_NUM': keycodeNum,
    'KEYCODE_HEADSETHOOK': keycodeHeadsethook,
    'KEYCODE_FOCUS': keycodeFocus,
    'KEYCODE_PLUS': keycodePlus,
    'MENU': menu,
    'KEYCODE_NOTIFICATION': keycodeNotification,
    'KEYCODE_SEARCH': keycodeSearch,
    'KEYCODE_MEDIA_PLAY_PAUSE': keycodeMediaPlayPause,
    'KEYCODE_MEDIA_STOP': keycodeMediaStop,
    'KEYCODE_MEDIA_NEXT': keycodeMediaNext,
    'KEYCODE_MEDIA_PREVIOUS': keycodeMediaPrevious,
    'KEYCODE_MEDIA_REWIND': keycodeMediaRewind,
    'KEYCODE_MEDIA_FAST_FORWARD': keycodeMediaFastForward,
    'KEYCODE_MUTE': keycodeMute,
    'KEYCODE_PAGE_UP': keycodePageUp,
    'KEYCODE_PAGE_DOWN': keycodePageDown,
    'KEYCODE_PICTSYMBOLS': keycodePictsymbols,
    'KEYCODE_SWITCH_CHARSET': keycodeSwitchCharset,
    'KEYCODE_BUTTON_A': keycodeButtonA,
    'KEYCODE_BUTTON_B': keycodeButtonB,
    'KEYCODE_BUTTON_C': keycodeButtonC,
    'KEYCODE_BUTTON_X': keycodeButtonX,
    'KEYCODE_BUTTON_Y': keycodeButtonY,
    'KEYCODE_BUTTON_Z': keycodeButtonZ,
    'KEYCODE_BUTTON_L1': keycodeButtonL1,
    'KEYCODE_BUTTON_R1': keycodeButtonR1,
    'KEYCODE_BUTTON_L2': keycodeButtonL2,
    'KEYCODE_BUTTON_R2': keycodeButtonR2,
    'KEYCODE_BUTTON_THUMBL': keycodeButtonThumbl,
    'KEYCODE_BUTTON_THUMBR': keycodeButtonThumbr,
    'KEYCODE_BUTTON_START': keycodeButtonStart,
    'KEYCODE_BUTTON_SELECT': keycodeButtonSelect,
    'KEYCODE_BUTTON_MODE': keycodeButtonMode,
    'KEYCODE_ESCAPE': keycodeEscape,
    'FORWARD_DEL': forwardDel,
    'KEYCODE_CTRL_LEFT': keycodeCtrlLeft,
    'KEYCODE_CTRL_RIGHT': keycodeCtrlRight,
    'KEYCODE_CAPS_LOCK': keycodeCapsLock,
    'KEYCODE_SCROLL_LOCK': keycodeScrollLock,
    'KEYCODE_META_LEFT': keycodeMetaLeft,
    'KEYCODE_META_RIGHT': keycodeMetaRight,
    'KEYCODE_FUNCTION': keycodeFunction,
    'KEYCODE_SYSRQ': keycodeSysrq,
    'KEYCODE_BREAK': keycodeBreak,
    'KEYCODE_MOVE_HOME': keycodeMoveHome,
    'KEYCODE_MOVE_END': keycodeMoveEnd,
    'KEYCODE_INSERT': keycodeInsert,
    'KEYCODE_FORWARD': keycodeForward,
    'KEYCODE_MEDIA_PLAY': keycodeMediaPlay,
    'KEYCODE_MEDIA_PAUSE': keycodeMediaPause,
    'KEYCODE_MEDIA_CLOSE': keycodeMediaClose,
    'KEYCODE_MEDIA_EJECT': keycodeMediaEject,
    'KEYCODE_MEDIA_RECORD': keycodeMediaRecord,
    'KEYCODE_F1': keycodeF1,
    'KEYCODE_F2': keycodeF2,
    'KEYCODE_F3': keycodeF3,
    'KEYCODE_F4': keycodeF4,
    'KEYCODE_F5': keycodeF5,
    'KEYCODE_F6': keycodeF6,
    'KEYCODE_F7': keycodeF7,
    'KEYCODE_F8': keycodeF8,
    'KEYCODE_F9': keycodeF9,
    'KEYCODE_F10': keycodeF10,
    'KEYCODE_F11': keycodeF11,
    'KEYCODE_F12': keycodeF12,
    'KEYCODE_NUM_LOCK': keycodeNumLock,
    'KEYCODE_NUMPAD_0': keycodeNumpad0,
    'KEYCODE_NUMPAD_1': keycodeNumpad1,
    'KEYCODE_NUMPAD_2': keycodeNumpad2,
    'KEYCODE_NUMPAD_3': keycodeNumpad3,
    'KEYCODE_NUMPAD_4': keycodeNumpad4,
    'KEYCODE_NUMPAD_5': keycodeNumpad5,
    'KEYCODE_NUMPAD_6': keycodeNumpad6,
    'KEYCODE_NUMPAD_7': keycodeNumpad7,
    'KEYCODE_NUMPAD_8': keycodeNumpad8,
    'KEYCODE_NUMPAD_9': keycodeNumpad9,
    'KEYCODE_NUMPAD_DIVIDE': keycodeNumpadDivide,
    'KEYCODE_NUMPAD_MULTIPLY': keycodeNumpadMultiply,
    'KEYCODE_NUMPAD_SUBTRACT': keycodeNumpadSubtract,
    'KEYCODE_NUMPAD_ADD': keycodeNumpadAdd,
    'KEYCODE_NUMPAD_DOT': keycodeNumpadDot,
    'KEYCODE_NUMPAD_COMMA': keycodeNumpadComma,
    'KEYCODE_NUMPAD_ENTER': keycodeNumpadEnter,
    'KEYCODE_NUMPAD_EQUALS': keycodeNumpadEquals,
    'KEYCODE_NUMPAD_LEFT_PAREN': keycodeNumpadLeftParen,
    'KEYCODE_NUMPAD_RIGHT_PAREN': keycodeNumpadRightParen,
    'KEYCODE_VOLUME_MUTE': keycodeVolumeMute,
    'KEYCODE_INFO': keycodeInfo,
    'KEYCODE_CHANNEL_UP': keycodeChannelUp,
    'KEYCODE_CHANNEL_DOWN': keycodeChannelDown,
    'KEYCODE_ZOOM_IN': keycodeZoomIn,
    'KEYCODE_ZOOM_OUT': keycodeZoomOut,
    'KEYCODE_TV': keycodeTv,
    'KEYCODE_WINDOW': keycodeWindow,
    'KEYCODE_GUIDE': keycodeGuide,
    'KEYCODE_DVR': keycodeDvr,
    'KEYCODE_BOOKMARK': keycodeBookmark,
    'KEYCODE_CAPTIONS': keycodeCaptions,
    'KEYCODE_SETTINGS': keycodeSettings,
    'KEYCODE_TV_POWER': keycodeTvPower,
    'KEYCODE_TV_INPUT': keycodeTvInput,
    'KEYCODE_STB_POWER': keycodeStbPower,
    'KEYCODE_STB_INPUT': keycodeStbInput,
    'KEYCODE_AVR_POWER': keycodeAvrPower,
    'KEYCODE_AVR_INPUT': keycodeAvrInput,
    'KEYCODE_PROG_RED': keycodeProgRed,
    'KEYCODE_PROG_GREEN': keycodeProgGreen,
    'KEYCODE_PROG_YELLOW': keycodeProgYellow,
    'KEYCODE_PROG_BLUE': keycodeProgBlue,
    'KEYCODE_APP_SWITCH': keycodeAppSwitch,
    'KEYCODE_LANGUAGE_SWITCH': keycodeLanguageSwitch,
    'KEYCODE_ASSIST': keycodeAssist,
    'KEYCODE_BRIGHTNESS_DOWN': keycodeBrightnessDown,
    'KEYCODE_BRIGHTNESS_UP': keycodeBrightnessUp,
    'KEYCODE_SLEEP': keycodeSleep,
    'KEYCODE_WAKEUP': keycodeWakeup,
    'KEYCODE_SOFT_SLEEP': keycodeSoftSleep,
  };
}

/// Maps a W3C `KeyboardEvent.code` value to its Android key code.
const Map<String, int> keyboardCodeMap = {
  'KeyA': 29,
  'KeyB': 30,
  'KeyC': 31,
  'KeyD': 32,
  'KeyE': 33,
  'KeyF': 34,
  'KeyG': 35,
  'KeyH': 36,
  'KeyI': 37,
  'KeyJ': 38,
  'KeyK': 39,
  'KeyL': 40,
  'KeyM': 41,
  'KeyN': 42,
  'KeyO': 43,
  'KeyP': 44,
  'KeyQ': 45,
  'KeyR': 46,
  'KeyS': 47,
  'KeyT': 48,
  'KeyU': 49,
  'KeyV': 50,
  'KeyW': 51,
  'KeyX': 52,
  'KeyY': 53,
  'KeyZ': 54,
  'Digit0': 7,
  'Digit1': 8,
  'Digit2': 9,
  'Digit3': 10,
  'Digit4': 11,
  'Digit5': 12,
  'Digit6': 13,
  'Digit7': 14,
  'Digit8': 15,
  'Digit9': 16,
  'Backquote': 68,
  'Minus': 69,
  'Equal': 70,
  'BracketLeft': 71,
  'BracketRight': 72,
  'Backslash': 73,
  'Semicolon': 74,
  'Quote': 75,
  'Comma': 55,
  'Period': 56,
  'Slash': 76,
  'Space': 62,
  'Tab': 61,
  'Escape': 111,
  'ArrowUp': 19,
  'ArrowDown': 20,
  'ArrowLeft': 21,
  'ArrowRight': 22,
  'Enter': 66,
  'Backspace': 67,
  'Delete': 112,
  'Home': 122,
  'End': 123,
  'PageUp': 92,
  'PageDown': 93,
  'Insert': 124,
  'F1': 131,
  'F2': 132,
  'F3': 133,
  'F4': 134,
  'F5': 135,
  'F6': 136,
  'F7': 137,
  'F8': 138,
  'F9': 139,
  'F10': 140,
  'F11': 141,
  'F12': 142,
  'ShiftLeft': 59,
  'ShiftRight': 60,
  'ControlLeft': 113,
  'ControlRight': 114,
  'AltLeft': 57,
  'AltRight': 58,
  'MetaLeft': 117,
  'MetaRight': 118,
  'ContextMenu': 82,
  'Numpad0': 144,
  'Numpad1': 145,
  'Numpad2': 146,
  'Numpad3': 147,
  'Numpad4': 148,
  'Numpad5': 149,
  'Numpad6': 150,
  'Numpad7': 151,
  'Numpad8': 152,
  'Numpad9': 153,
  'NumpadDivide': 154,
  'NumpadMultiply': 155,
  'NumpadSubtract': 156,
  'NumpadAdd': 157,
  'NumpadDecimal': 158,
  'NumpadComma': 159,
  'NumpadEnter': 160,
  'NumpadEqual': 161,
};
