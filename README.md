# Ancora — Medication Adherence App

A cross-platform mobile application built with Flutter and Firebase that helps patients manage their medication schedules and enables caregivers to monitor adherence in real time.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Problem Statement](#problem-statement)
- [Objectives](#objectives)
- [Key Features](#key-features)
- [System Architecture](#system-architecture)
- [Software Stack](#software-stack)
- [User Workflow](#user-workflow)
- [Sensor Fusion Strategy](#sensor-fusion-strategy)
- [UI/UX Designs](#uiux-designs)
- [Application Screenshots](#application-screenshots)
- [Challenges and Solutions](#challenges-and-solutions)
- [Future Improvements](#future-improvements)
- [Lessons Learnt](#lessons-learnt)
- [My Role](#my-role)
- [Project Structure](#project-structure)
- [Installation and Setup](#installation-and-setup)
- [Resources](#resources)

---

## Project Overview

Ancora is a medication adherence application targeting patients with chronic or ongoing treatment needs and the caregivers who support them. The application provides a structured daily medication schedule, smart cascading reminders, live photo verification of dose intake, and a caregiver portal for remote monitoring.

The app supports two distinct user roles — **Patient** and **Caregiver** — each with a dedicated interface and navigation flow. Patients log and verify their doses; caregivers receive push alerts and view adherence dashboards for all patients they are linked to.

The project was developed as part of the CS4238 Mobile Computing course at Academic City University, targeting Android and Web platforms with a production-ready Firebase backend.

---

## Problem Statement

Medication non-adherence is a widespread public health issue. Patients across all age groups frequently miss or incorrectly take prescribed medications, leading to:

- Disease relapse and deteriorating health outcomes
- Increased emergency hospital admissions
- Antibiotic resistance caused by incomplete treatment courses
- Reduced quality of life for patients and additional burden on caregivers

Existing solutions either lack real-time accountability, do not involve caregivers meaningfully, or are too complex for everyday users. Ancora addresses this gap by combining a simple daily schedule interface, proof-based dose logging, and a caregiver oversight layer — all in one application.

---

## Objectives

1. Provide patients with a clear, real-time view of their daily medication schedule and completion status.
2. Deliver cascading reminders at defined intervals before each scheduled dose to reduce missed medications.
3. Require patients to photograph their medication at the point of intake as verifiable evidence.
4. Give caregivers a live dashboard showing the adherence status of every patient they are linked to.
5. Alert caregivers automatically via push notification when a patient misses a dose or takes one unusually early.
6. Enable a lightweight, privacy-respecting pairing system between patients and caregivers using a unique display code.
7. Automatically detect and record missed doses in the background, even when the app is not open.

---

## Key Features

### Patient Features

- **Daily schedule dashboard** — Displays all medications due today as status-coded cards (Upcoming, Soon, Completed, Missed, Overdue) with a circular progress indicator showing the day's completion percentage.
- **Dose logging with photo verification** — The "Take" button captures a photo of the medication at intake time. The image is uploaded to Firebase Storage as timestamped proof and linked to the dose log entry.
- **Early dose warning** — If a patient takes a dose more than 30 minutes ahead of schedule, a confirmation dialog is shown. The log is marked with an `earlyTake` flag for caregiver visibility.
- **Cascading smart reminders** — Five notifications are scheduled per dose at offsets of 60, 30, 10, and 5 minutes before, and at the exact scheduled time. The final alert uses alarm-level audio to override silent mode.
- **Medication management** — Patients can add, edit, and stop medications. Each medication stores the name, dosage, unit, type, frequency, intake times, and treatment dates.
- **History and statistics** — A monthly calendar view (green for taken, red for missed), a 7-day adherence average, and a consecutive-day streak counter.
- **Patient display code** — Each patient is assigned a unique 4-digit code used to connect with a caregiver.
- **Profile management** — Editable name, phone number, age, and profile photo (uploaded to Firebase Storage).

### Caregiver Features

- **Adherence dashboard** — Shows all linked patients with on-track or needs-attention status, based on 7-day adherence. Summary cards display the total patient count, on-track count, and at-risk count.
- **Patient detail view** — Full monthly calendar and complete dose log history for any linked patient, including proof photo thumbnails.
- **Patient linking** — Caregivers enter a patient's 4-digit code to link accounts. A confirmation dialog shows the patient's name before the link is created.
- **Push notifications** — Caregivers receive an FCM push notification when a linked patient misses a dose or takes one early (delivered via Firebase Cloud Function).
- **Profile management** — Editable caregiver profile with photo upload and sign-out.

### Background Automation

- **Missed dose sweep** — A WorkManager background task runs every 15 minutes on Android. It scans the past 2 days of medication schedules and automatically records a `missed` status dose log for any dose that has passed its 60-minute grace period without being logged.

---

## System Architecture

The system is structured as a client-server application. The Flutter app runs on the patient or caregiver's device and communicates directly with Firebase services. A Firebase Cloud Function handles server-side event processing.

**Architecture Diagram**

![System Architecture](resources/WhatsApp%20Image%202026-04-23%20at%201.58.09%20AM.jpeg)

**Data Flow Diagram**

![Data Flow](resources/WhatsApp%20Image%202026-04-23%20at%201.58.09%20AM%20(1).jpeg)

### Key architectural decisions

- **Dual-portal design** — Patients and caregivers have entirely separate navigation stacks and Firebase Auth role validation. Cross-role login is blocked at the service layer.
- **Deterministic dose log IDs** — Each log document uses the format `{medId}_{YYYYMMDD}_{HHMM}`, preventing duplicate entries for the same dose slot and enabling safe upsert operations.
- **Denormalized caregiver data** — When a caregiver links to a patient, a copy of the patient's name, photo, age, and display code is stored in the caregiver's subcollection. This allows the dashboard to load without cross-collection joins.
- **Soft delete on medications** — Stopping a medication sets `archived: true` rather than deleting the document, preserving historical dose log integrity.
- **Bidirectional caregiver-patient link** — Linking is a single atomic batch write that creates a document in both the patient's `caregivers` subcollection and the caregiver's `patients` subcollection.
- **DisplayId via Firestore transaction** — The 4-digit patient code is allocated using a Firestore transaction with up to five collision-retry attempts, ensuring uniqueness under concurrent sign-ups.

---

## Software Stack

| Layer | Technology |
|---|---|
| UI Framework | Flutter 3.x (Dart) |
| Design System | Material Design 3, custom teal theme |
| Authentication | Firebase Authentication (email/password) |
| Database | Cloud Firestore |
| File Storage | Firebase Storage |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Local Notifications | flutter_local_notifications |
| Background Tasks | WorkManager (Android) |
| Server Logic | Firebase Cloud Functions (TypeScript, Node 24) |
| Timezone | timezone + flutter_timezone |
| Image Picker | image_picker |
| Deep Linking | url_launcher |
| Target Platforms | Android (primary), Web (Chrome) |

---

## User Workflow

The diagram below shows the step-by-step flow for both user roles, from onboarding through daily use.

![User Workflow](resources/WhatsApp%20Image%202026-04-18%20at%202.55.12%20PM.jpeg)

### Patient flow

1. Patient opens the app and registers with their name, email, phone, and password. A unique 4-digit display code is assigned.
2. Patient adds their medications (name, dosage, type, frequency, intake times, and treatment dates).
3. At each scheduled time, cascading notifications alert the patient. The patient opens the app and taps "Take."
4. The camera opens. The patient photographs their medication. The image and a `taken` dose log are saved to Firebase.
5. The home screen updates in real time to reflect the completed dose.
6. At the end of each day, any dose not logged within the grace period is automatically marked as `missed` by the background sweep.

### Caregiver flow

1. Caregiver registers and receives their own display code.
2. Patient shares their 4-digit code with the caregiver out of band (verbally or via message).
3. Caregiver enters the code in the "Add Client" screen. The accounts are linked.
4. The caregiver dashboard populates with the patient's adherence data in real time.
5. When a patient misses a dose or takes one early, the Firebase Cloud Function sends the caregiver a push notification.

---

## Sensor Fusion Strategy

Ancora integrates three device-level hardware components that work together to deliver the full medication verification loop. Rather than relying on a single input, the combination of these components ensures accurate and tamper-resistant dose recording.

### 1. Camera

The device camera is the primary verification input. When a patient logs a dose, the camera is launched immediately. The patient must photograph the medication before the log is saved. The image is timestamped and stored in Firebase Storage linked to the specific dose log entry. This prevents retroactive logging and provides visible evidence for caregivers.

On Android, this uses the `image_picker` package with `ImageSource.camera`. On web, photo capture is skipped and the dose is logged without a proof image.

### 2. System Clock and Timezone

The device's system clock and IANA timezone are used to schedule all notifications and evaluate dose timing. The user's timezone is stored in their Firestore profile (`tzIana`, defaulting to `Africa/Accra`) and applied at scheduling time using the `timezone` package. This ensures that reminders fire at the correct local time regardless of when the medication was first added or when the device was last restarted.

The clock is also used by the background sweep to determine which doses are overdue — any dose more than 60 minutes past its scheduled time with no existing log is auto-marked as missed.

### 3. Notification Subsystem

The notification subsystem delivers cascading alerts at five offsets before each dose: 60, 30, 10, and 5 minutes before, and at the exact scheduled time. Each dose time produces up to five scheduled notifications, covering approximately 75 notifications per patient at any given time.

Two Android notification channels are configured:
- `ancora_reminders` (high importance) — standard pre-dose alerts.
- `ancora_dose_alarm_v2` (maximum importance, alarm audio stream) — fires at the exact dose time and bypasses Do Not Disturb settings.

Together, these three components form a closed loop: the clock determines when, the notification system alerts the patient, and the camera confirms the action.

---

## UI/UX Designs

The Figma design established the visual language used throughout the app — teal primary color, dark navigation bar, and card-based layouts for medication entries.

![Figma Mockup — Landing Page](resources/WhatsApp%20Image%202026-04-18%20at%202.55.12%20PM.jpeg)

**Design system constants**

| Token | Value |
|---|---|
| Primary color | `#2CB9B0` (teal) |
| Feature card background | `#E6F7F6` (light teal) |
| Icon background | `#D0F0EC` |
| Page background | `#F7FAFA` (off-white) |
| Navigation bar | `#1C2525` (dark charcoal) |
| Primary text on buttons | `#14232F` (dark navy) |
| Border radius (cards) | 16 dp |
| Border radius (inputs) | 14 dp |
| Button height | 52 dp |
| Typography | Roboto (Material 3 scale) |

The bottom navigation bar uses a dark background with a teal-highlighted active icon and a text label only for the active tab. This pattern is consistent across both the patient and caregiver portals.

---

## Application Screenshots

### Patient Portal

| Screen | Preview |
|---|---|
| Landing Page | ![Landing Page](resources/Screenshot%202026-06-21%20234313.png) |
| Login | ![Login](resources/Screenshot%202026-06-21%20234322.png) |
| Sign Up | ![Sign Up](resources/Screenshot%202026-06-21%20234330.png) |
| Home — Daily Schedule | ![Home Dashboard](resources/Screenshot%202026-06-21%20234338.png) |
| History and Statistics | ![History](resources/Screenshot%202026-06-21%20234345.png) |
| Add Medication | ![Add Medication](resources/Screenshot%202026-06-21%20234356.png) |
| Profile and Settings | ![Patient Profile](resources/Screenshot%202026-06-21%20234406.png) |

### Caregiver Portal

| Screen | Preview |
|---|---|
| Caregiver Home — Dashboard | ![Caregiver Home](resources/Screenshot%202026-06-21%20234425.png) |
| Client Details — Adherence View | ![Client Details](resources/Screenshot%202026-06-21%20234433.png) |
| Add Client | ![Add Client](resources/Screenshot%202026-06-21%20234442.png) |
| Caregiver Profile and Settings | ![Caregiver Profile](resources/Screenshot%202026-06-21%20234451.png) |

---

## Challenges and Solutions

### 1. Exact alarm reliability on Android (especially Samsung devices)

Android's exact alarm APIs behave inconsistently across manufacturers. On many Samsung devices, `BroadcastReceiver`-based exact alarms silently fail, meaning scheduled medication reminders never fire.

**Solution:** A WorkManager periodic task runs every 15 minutes in the background. It checks whether any dose is due within a 16-minute window and calls `FlutterLocalNotificationsPlugin.show()` directly, bypassing the `BroadcastReceiver` entirely. This provides a reliable fallback on devices where the standard scheduling path fails.

### 2. Preventing duplicate dose log entries

With a background sweep running every 15 minutes and the patient also able to log manually, it is possible for two writes to target the same dose slot simultaneously, creating duplicate records.

**Solution:** Dose log document IDs are deterministic: `{medId}_{YYYYMMDD}_{HHMM}`. A write to the same slot always targets the same document. Firestore's document set operation makes this idempotent — the second write overwrites the first with identical data rather than creating a duplicate.

### 3. Race conditions during display code allocation

When multiple users sign up simultaneously, two accounts could be assigned the same 4-digit code if the uniqueness check and write are not atomic.

**Solution:** Display code allocation uses a Firestore transaction. The transaction reads the `displayIdIndex` document, confirms it is unclaimed, and writes the new entry atomically. Up to five random codes are attempted per sign-up, with each retry generating a new random value.

### 4. Role separation between patients and caregivers

Both user types share the same Firebase Authentication project. Without explicit role checking, a patient could log in through the caregiver interface.

**Solution:** A `role` field is written to the user's Firestore document at sign-up and is validated at sign-in. The `AuthService.signIn()` method checks that the authenticated user's role matches the expected role for the login screen. A mismatch returns a descriptive error and blocks access.

### 5. Keeping caregiver data current when a patient updates their profile

When a patient changes their name or profile photo, the caregiver's `patients` subcollection holds a stale denormalized copy of that data.

**Solution:** The `ProfilePhotoService` updates the photoURL not only in the patient's own profile but also in every linked caregiver's `patients/{patientUid}` document in a single batch operation. The same approach applies to name changes in the profile editor.

### 6. Notification window expiry

`flutter_local_notifications` can only hold a finite number of scheduled notifications. Scheduling for more than 48 hours ahead would exceed device limits and is also unnecessary.

**Solution:** The app schedules the next 48 hours of notifications on every medication save and on app launch. WorkManager's `rescheduleAll` task refreshes this window every 15 minutes to ensure the rolling schedule never expires while the app is installed.

---

## Future Improvements

- **Machine learning for photo verification** — Integrate a trained model that validates the captured photo against the expected medication type and visual appearance. The model would use the medication's type (tablet, capsule, syrup, etc.) and, where possible, the patient's profile to flag images that do not match the expected drug form. This would prevent patients from submitting unrelated photos as proof of intake.
- **iOS support** — Complete the Firebase configuration for iOS (`GoogleService-Info.plist`, APNs setup) and address platform-specific notification handling to bring the app to full feature parity on iPhone.
- **Server-side notification scheduling** — Move the rolling notification window from on-device scheduling to Firebase Cloud Functions. This would eliminate the 48-hour limit and remove the dependency on WorkManager for notification delivery.
- **Biometric authentication** — Add fingerprint or face unlock as an optional second factor on supported devices to prevent unauthorized dose logging on behalf of another person.
- **Medication refill reminders** — Track remaining pill/dose counts and notify the patient when a refill is approaching, based on dosage quantity and frequency.
- **Adherence report export** — Allow patients and caregivers to export a PDF or CSV summary of adherence history for sharing with a healthcare provider.
- **Drug database integration** — Connect to a verified drug reference API so patients can search for medications by brand or generic name, auto-fill dosage guidance, and receive interaction warnings.
- **Multi-language support** — Add localization to serve patients who are not comfortable in English.

---

## Lessons Learnt

- **Real-time UI with Firestore streams** — Using `StreamBuilder` to listen to Firestore collections means the UI always reflects the latest data without manual refresh logic. The trade-off is that every screen independently manages its own stream subscriptions and rebuild cycles, which requires careful attention to avoid redundant reads.
- **Platform-specific behavior must be tested on real hardware** — Notification behavior differences between Android manufacturers (particularly Samsung) are not visible in emulators. The WorkManager fallback was only identified and implemented after testing on a physical Samsung device.
- **Denormalization improves read performance but adds write complexity** — Caching patient data in the caregiver's subcollection makes the dashboard fast and cheap to load, but it means every patient profile update must also propagate to linked caregivers. This tradeoff should be planned before the data model is finalized.
- **Firestore security rules are part of the data model** — Rules are not simply an access gate; they encode invariants (such as role immutability and status fields that cannot be updated after creation). Writing rules alongside the data model rather than afterward prevents security gaps.
- **Deterministic document IDs simplify concurrent writes** — Choosing a meaningful, predictable document ID eliminates entire categories of race conditions and makes logs easier to debug and query without additional indexes.
- **Role-based authentication requires discipline at every layer** — Separating patient and caregiver flows at the routing layer, service layer, and Firestore rules level is redundant by design. Any single layer alone is insufficient.

---

## My Role

My primary contributions to this project were in design and user interface implementation.

**Figma Design** — I was responsible for creating the visual design of the application in Figma. This included defining the color system (primary teal `#2CB9B0`, background tones, navigation bar), establishing the component library (cards, buttons, input fields, bottom navigation bar), and designing the screen layouts for both the patient and caregiver portals.

**UI Implementation** — I contributed to translating the Figma designs into Flutter widgets. This involved implementing the AppTheme, building screen layouts to match the design specifications, and ensuring consistency in spacing, typography, and color application across the application.

---

## Project Structure

```
Ancora/
├── lib/
│   ├── main.dart                        # App entry point, Firebase initialization, AuthWrapper, named routes
│   ├── firebase_options.dart            # Firebase configuration (not committed — see setup)
│   ├── theme/
│   │   └── app_theme.dart              # Centralized Material 3 theme, colors, text styles, button styles
│   ├── services/
│   │   ├── auth_service.dart           # Sign up, sign in, sign out, role validation, displayId allocation
│   │   ├── notification_service.dart   # FCM token management, local notification scheduling, WorkManager init
│   │   ├── profile_photo_service.dart  # Profile image upload to Firebase Storage, Firestore sync
│   │   ├── _workmanager_io.dart        # Android background task: missed dose sweep and notification refresh
│   │   └── _workmanager_web.dart       # Web stub (no-ops) for WorkManager calls
│   └── screens/
│       ├── landing_page.dart           # Onboarding screen with feature highlights
│       ├── signup_page.dart            # Patient registration
│       ├── login_page.dart             # Patient login
│       ├── home_page.dart              # Patient dashboard — daily schedule, dose logging, photo capture
│       ├── add_medication_page.dart    # Add and edit medication form
│       ├── history_page.dart           # Adherence calendar, 7-day average, streak
│       ├── more_page.dart              # Patient profile, display code, sign out
│       ├── caregiver_auth_page.dart    # Caregiver login/signup choice
│       ├── caregiver_signup_page.dart  # Caregiver registration
│       ├── caregiver_login_page.dart   # Caregiver login
│       ├── caregiver_home_page.dart    # Caregiver dashboard — linked patients, adherence summary
│       ├── caregiver_clients_page.dart # Patient list view and individual patient detail
│       ├── caregiver_add_user_page.dart # Link a patient by their display code
│       ├── caregiver_more_page.dart    # Caregiver profile and sign out
│       ├── agreement_policy_page.dart  # Terms of use and data policy
│       └── help_feedback_page.dart     # Help documentation and support contact
├── functions/
│   └── src/
│       └── index.ts                   # Cloud Function: onDoseLogCreate — notifies caregivers on missed/early doses
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml        # Android permissions, broadcast receivers, exact alarm declarations
├── ios/
│   └── Runner/
│       └── Info.plist                 # iOS permissions (camera, photo library)
├── web/
│   ├── index.html                     # Flutter web entry point
│   └── firebase-messaging-sw.js       # FCM service worker for web push (not committed — see setup)
├── firestore.rules                    # Firestore security rules (role-based read/write enforcement)
├── storage.rules                      # Firebase Storage access rules (proof images, profile photos)
├── firestore.indexes.json             # Firestore composite index definitions
├── firebase.json                      # Firebase CLI project configuration
├── BACKEND.md                         # Full Firestore data model and architecture specification
├── pubspec.yaml                       # Flutter dependencies and project metadata
└── resources/                         # Project documentation, thesis report, app screenshots, mockups
```

---

## Installation and Setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, 3.10.0 or later)
- [Firebase CLI](https://firebase.google.com/docs/cli) — `npm install -g firebase-tools`
- A connected Android device or emulator, or Chrome for web

### 1. Clone the repository

```bash
git clone https://github.com/Oswald4422/Ancora.git
cd Ancora
```

### 2. Add Firebase configuration files

These files contain project credentials and are not committed to the repository. Obtain them from the project owner or configure your own Firebase project.

| File | Location |
|---|---|
| `google-services.json` | `android/app/google-services.json` |
| `firebase_options.dart` | `lib/firebase_options.dart` |
| `firebase-messaging-sw.js` | `web/firebase-messaging-sw.js` |

To generate `firebase_options.dart` for your own Firebase project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

For the web service worker, copy the example file and fill in your Firebase web configuration:

```bash
cp web/firebase-messaging-sw.js.example web/firebase-messaging-sw.js
```

### 3. Install dependencies

```bash
flutter pub get
```

### 4. (Optional) Deploy Cloud Functions

Caregiver push notifications require the Firebase project to be on the Blaze (pay-as-you-go) plan.

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

### 5. Run the app

**Android (connected device or emulator):**

```bash
flutter run
```

**Chrome (web):**

```bash
flutter run -d chrome
```

---

## Resources

| Resource | Link |
|---|---|
| GitHub Repository | [https://github.com/Oswald4422/Ancora.git](https://github.com/Oswald4422/Ancora.git) |
| Thesis Report | [resources/ANCORA REPORT FINAL.pdf](resources/ANCORA%20REPORT%20FINAL.pdf) |
| Backend Architecture Spec | [BACKEND.md](BACKEND.md) |

---

*Ancora — Academic City University, CS4238 Mobile Computing*
