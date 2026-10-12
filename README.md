# Curtina Schools – iOS

One iPhone app for every Curtina school. It does the same job as the per-school Android apps
(e.g. `D:\F\workspace\GDGPSK`): a full-screen web view of `curtina.in/_mobile/loginm.aspx?AppId=<SCHOOL>&newver=JET&fcm=<token>`.
On first launch the user picks their school. The choice is saved, and "⋯ → Change School" switches to another.

| Android (GDGPSK)                        | iOS (this app)                                                        |
|-----------------------------------------|-----------------------------------------------------------------------|
| `AppId` hard-coded per app              | School list loaded from `https://curtina.in/_mobile/schools.json`     |
| FCM token sent as `&fcm=`               | Same (only if `GoogleService-Info.plist` is added)                    |
| Camera / gallery upload, mic, location  | Same (iOS shows its own permission prompts)                           |
| Downloads → Downloads folder            | Downloads → share sheet (Save to Files, WhatsApp, Print…)             |
| Map / `geo:` links → Google Maps        | Map links open in Maps; `geo:` converted to Apple Maps                |
| Reload when the network comes back      | Same                                                                  |
| Hardware Back button                    | Back button in the top bar + swipe-back gesture                       |

## 1. Put the school list on the server

Upload `server/schools.json` to the `_mobile` folder on curtina.in, so that
`https://curtina.in/_mobile/schools.json` opens in a browser. To add a school later, add one entry
to that file. You don't need to update the app.

```json
{ "appId": "GDGPSK", "name": "G. D. Goenka Public School",
  "loginUrl": "https://curtina.in/_mobile/loginm.aspx?AppId=GDGPSK&newver=JET",
  "logoUrl": "https://curtina.in/GDGPSK/assets/images/printlogo.png?ver=6" }
```

`logoUrl` can be `null`. The app then shows the first two letters of the code instead.

## 2. Test without a Mac (GitHub Actions + Appetize)

1. Create a GitHub repository and push this folder to it.
2. Open **Actions → iOS test build → Run workflow**. The first build takes about 10 minutes, because Firebase has to download.
3. Download the `CurtinaSchools-simulator` artifact. It contains `CurtinaSchools-simulator.zip`.
4. Upload the zip at https://appetize.io (free tier). The app opens in an iPhone simulator in your browser.

The simulator can't receive push notifications and has no camera. Test those on a real iPhone (step 4).

## 3. Push notifications (Firebase)

An iOS app can only belong to **one** Firebase project. Today your schools are split across three:
`push-notification-bcd33`, `magnus-8c2d1` and `jet66-808a0`.

1. In the Firebase project you choose, add an iOS app with bundle id `com.magnus.curtinaschools`.
2. Download `GoogleService-Info.plist` and put it in the `CurtinaSchools/` folder.
3. Upload an APNs Auth Key (.p8) under Project settings → Cloud Messaging. This needs the Apple Developer account.
4. **Server:** when the server sends a notification to an iPhone token, it must use the credentials of
   *that* Firebase project, whichever school the user belongs to.

Without the plist the app runs normally. It just doesn't send `&fcm=`.

## 4. Real iPhone / App Store (needs a Mac + Apple Developer account, $99/yr)

```
brew install xcodegen
xcodegen generate
open CurtinaSchools.xcodeproj
```

In Xcode: Signing & Capabilities → choose your Team, then press Run with an iPhone plugged in.
For TestFlight or the App Store: Product → Archive → Distribute. Before submitting, add an app icon
(Assets → AppIcon, 1024×1024).
