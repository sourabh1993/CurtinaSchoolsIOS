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

Each school uses the **same Firebase project as its Android app**, so the server needs no changes.
The app connects to that project when the user picks the school:

| Firebase project          | Schools                                                         |
|---------------------------|-----------------------------------------------------------------|
| `push-notification-bcd33` | GDGPSK, HPS, MASD, MGPS, MKK, SDVMCITY, SOE, SPSKSP, SSPS, STMR, SWWS, DSPSKC |
| `magnus-8c2d1`            | GGS, GPSMKG, RIS, DSPSPN                                        |

Setup, done once per project:
1. Firebase console → Project settings → **Add app → iOS**. Bundle id `com.magnus.curtinaschools`.
2. Download that project's `GoogleService-Info.plist`.
3. Project settings → **Cloud Messaging → Apple app configuration** → upload the APNs Auth Key (.p8).
   You can use the same key for both projects.
4. Copy `PROJECT_ID`, `GCM_SENDER_ID`, `GOOGLE_APP_ID` and `API_KEY` from the plist into the `firebase`
   field of each school that uses that project in `schools.json`:

```json
"firebase": { "projectId": "...", "gcmSenderId": "...", "googleAppId": "1:...:ios:...", "apiKey": "..." }
```

A school with no `firebase` entry works normally, just without notifications. iPhones only show
notifications that include a `notification` title/body. Data-only messages are not displayed.

## 4. Real iPhone / App Store (needs a Mac + Apple Developer account, $99/yr)

```
brew install xcodegen
xcodegen generate
open CurtinaSchools.xcodeproj
```

In Xcode: Signing & Capabilities → choose your Team, then press Run with an iPhone plugged in.
For TestFlight or the App Store: Product → Archive → Distribute. Before submitting, add an app icon
(Assets → AppIcon, 1024×1024).
