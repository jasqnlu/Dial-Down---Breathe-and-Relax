# Uploading Dial Down 2.0 to the App Store

Dial Down – Breathe and Relax · App Store ID 6818409674 · bundle ID `com.jasonlu.Dial--Down--Breath--Stretch`
Release: **version 2.0, build 2**, archived from the **`seperate-main`** branch (commit `e5f8f2b` or later).

> `main` is frozen for the Congressional App Challenge. Never merge `seperate-main` into it. Archive straight from `seperate-main`.

---

## 0. Before you archive

| Check | How | Done |
|---|---|---|
| On the right branch | `git checkout seperate-main && git pull` and confirm `git log -1` is `e5f8f2b` or newer | ☐ |
| Version 2.0, build 2 | Xcode → project → target **BreathRelaxStretch** → General → Identity | ☐ |
| Website legal pages live | https://www.getdialdown.com/privacy says "Last updated: November 6, 2026" and has section 6, **Ask Dial Down and Voice Input**. Apple's reviewer opens this URL. | ☐ |
| Ask works on a real iPhone | The on-device model doesn't run in the simulator. On an iPhone with Apple Intelligence, try: "my lower back is tight, 5 minutes", "add a calf stretch", "remove the last one", "I have chest pain". Then hold the Ask button and speak. | ☐ |
| Ask works **without** Apple Intelligence | On a device or setting without it, the same typed requests should still give routines (keyword fallback) | ☐ |
| Account deletion works on the live server | Make a test account → Profile → Account → Delete Account → it's gone and you're signed out | ☐ |
| Streak Saver purchase (points) | Profile → Settings → buy a saver with points; restore from the streak-lost alert | ☐ |

If a build is already in App Store Connect with build number 2 for version 2.0, raise the build number by 1 in Xcode before archiving.

## 1. Archive in Xcode

1. Open `Breath - Relax & Stretch.xcodeproj`.
2. Scheme: **BreathRelaxStretch**. Destination: **Any iOS Device (arm64)**. Archive is greyed out if a simulator is selected.
3. Signing: target **BreathRelaxStretch** → Signing & Capabilities → **Automatically manage signing**, team **F4NF2ZRZS9**.
4. **Product → Archive.** This uses the Release configuration and takes a few minutes.
5. The **Organizer** window opens with the new archive. Check that it shows **2.0 (2)**.

## 2. Upload

1. In Organizer, select the archive → **Distribute App**.
2. Choose **App Store Connect** → **Upload**.
3. Keep the defaults (upload symbols, automatic signing) → **Upload**.
4. Export compliance: the app declares `ITSAppUsesNonExemptEncryption = NO` in `BreathRelaxStretch-Info.plist`, so App Store Connect shouldn't ask.
5. Wait for the "has completed processing" email (usually 10–30 minutes). Until then, the build shows as *Processing* under the TestFlight tab.

> Optional but recommended: install the build from **TestFlight** on your own iPhone and repeat the Ask checks from step 0 on that exact build.

## 3. Create version 2.0 in App Store Connect

App Store Connect → **Apps → Dial Down** → **App Store** tab → the **+** next to *iOS App* → enter **2.0**.

### 3a. What's New in This Version

```
A fresh new look, and a new way to find your stretch.
• Ask Dial Down: type or say what you need ("my neck is stiff", "5 minutes for tight hips") and get a routine made for you. It runs entirely on your iPhone.
• Hold the Ask button to speak; your voice is turned into text on your device and never leaves it.
• Built-in safety check: if you describe pain that sounds serious, Dial Down suggests seeing a doctor instead.
• Redesigned app with a calmer black-and-pastel style.
• Better Spanish, French, and Chinese translations, including permission prompts.
```

If you also show the app in Spanish, French or Chinese on the store, add a translated What's New for each language.

### 3b. Screenshots

The app was fully redesigned, so the 1.0 screenshots no longer match the app. Replace them with screenshots of the new design. At minimum, upload the **6.9"** iPhone size; Apple scales it down for the smaller ones. Include one screenshot of Ask Dial Down.

### 3c. URLs (App Information / version page)

| Field | Value |
|---|---|
| Privacy Policy URL | https://www.getdialdown.com/privacy |
| Support URL | https://www.getdialdown.com/support |
| Marketing URL | https://www.getdialdown.com |

### 3d. Build

Under **Build**, click **+** and pick **2.0 (2)**.

### 3e. Age rating

Open the age rating questionnaire and answer the questions again, since Apple adds new ones from time to time. Ask isn't a chat with other people and doesn't generate open-ended content. It only picks exercises from the app's own catalog.

## 4. App Privacy ("nutrition label")

App Store Connect → **App Privacy** → **Edit**. Data is only sent off the iPhone when someone signs in. **Nothing is used for tracking.**

| Data type | Collected | Linked to user | Purpose |
|---|---|---|---|
| Contact Info → **Name** | Yes | Yes | App Functionality |
| Contact Info → **Email Address** | Yes (through Supabase sign-in) | Yes | App Functionality |
| Identifiers → **User ID** | Yes | Yes | App Functionality |
| Health & Fitness → **Fitness** (session history) | Yes | Yes | App Functionality |
| User Content → **Other User Content** (routine names and exercises) | Yes | Yes | App Functionality |

**Not collected:**
- Audio, Ask requests and voice: these are processed on the iPhone only.
- Apple Health data: stays on the iPhone.
- Location, contacts, purchases, browsing history, diagnostics: none of these are collected.

There are no analytics or crash-reporting SDKs in the app.

Push token for streak reminders: most apps don't declare this. If you want to be extra cautious, add *Identifiers → Device ID* (linked, App Functionality).

## 5. App Review Information

- **Sign-in required:** No. Uncheck it, so you don't need a demo account.
- **Contact:** your name, phone, and dialdownn@gmail.com.
- **Notes:**

```
No login is required. On first launch, go through onboarding and tap "Start breathing" to use the app without an account.

To try Ask Dial Down: tap the Ask button and type "my lower back is tight, 5 minutes", then send. A routine appears in the chat. Follow-ups such as "add a calf stretch" or "remove the last one" edit that routine.

Voice: press and hold the Ask button, speak, then release. The microphone and speech recognition are used only while holding (or after tapping the mic inside the Ask chat). Recognition is forced on-device (requiresOnDeviceRecognition = true), so no audio leaves the device.

Safety check: typing "I have chest pain" shows a safety card that suggests seeing a doctor and has a button that opens the Phone app with the local emergency number. Nothing is reported or sent anywhere.

Ask uses Apple's on-device Foundation Models when Apple Intelligence is available, and the app's built-in keyword matching otherwise. No server is involved; Ask requests are never uploaded.
```

## 6. Submit

1. **Version Release:** choose *Manually release this version*, so you control when 2.0 goes live, or *Automatically*.
2. Click **Add for Review** → **Submit to App Review**.
3. Review usually takes 1–2 days. If it's rejected, reply in Resolution Center. The most likely questions are about the microphone/speech use (answered in the notes) and the medical wording (the app always says it's not medical advice).

## 7. After it's approved

- If you chose manual release: **Release This Version**.
- The App Store will then run 2.0 while the Congressional App Challenge reviews the version on `main`. That's expected. Just don't change `main`.
- Tag the release: `git tag v2.0 e5f8f2b && git push origin v2.0` (use the commit you actually archived).
