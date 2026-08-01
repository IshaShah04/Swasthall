# SwasthAll — Nepal's Family Healthcare Super-App 🏥🇳🇵

[![Flutter Build & Release](https://github.com/IshaShah04/Swasthall/actions/workflows/flutter-release.yml/badge.svg)](https://github.com/IshaShah04/Swasthall/actions/workflows/flutter-release.yml)
[![Supabase Migrations](https://github.com/IshaShah04/Swasthall/actions/workflows/supabase-migrate.yml/badge.svg)](https://github.com/IshaShah04/Swasthall/actions/workflows/supabase-migrate.yml)
[![Edge Function Deploy](https://github.com/IshaShah04/Swasthall/actions/workflows/supabase-functions.yml/badge.svg)](https://github.com/IshaShah04/Swasthall/actions/workflows/supabase-functions.yml)
[![GitHub License](https://img.shields.io/github/license/IshaShah04/Swasthall)](https://github.com/IshaShah04/Swasthall/blob/main/LICENSE)

SwasthAll is a comprehensive, family-centric healthcare platform designed to bridge the accessibility gap in Nepal's medical ecosystem. Developed by **IshaShah04**, it connects patients, family members, doctors, nurses, pharmacists, and lab technicians in a unified, secure real-time environment.

---

## 🌟 Key Features

* **👨‍👩‍👧 Family Link Accounts:** Allows primary users (including members of the Nepali diaspora) to manage health logs, book appointments, and pay fees for their rural dependents.
* **📞 Real-Time Teleconsultations:** High-performance, low-latency video and audio doctor calls powered by WebRTC (via ZEGO Cloud), optimized for low-bandwidth networks.
* **🏥 Nurse-Led Queue Triage:** Streamlined clinical queue management where nurses pre-check patient vitals (intake/triage) before routing them to the scheduled doctor.
* **🔒 Private Health Vault:** Secure, encrypted storage bucket for medical records (PDFs/Images) and a personal vitals tracker (blood pressure, blood sugar) protected by database-level Row Level Security (RLS).
* **💳 Local Digital Payments:** Direct checkout integrations with leading Nepalese payment gateways (**eSewa** and **Khalti**) supporting NPR transactions.
* **🌐 Dynamic Localization:** Multi-language interface supporting English, Nepali, and Hindi, along with offline translation capabilities powered by Google ML Kit.

---

## 🛠️ Tech Stack

* **Frontend:** [Flutter](https://flutter.dev/) (Cross-platform Dart client for Android, iOS, and Web)
* **State Management:** [Riverpod](https://riverpod.dev/) (Compile-safe reactive state tracking)
* **Navigation:** [GoRouter](https://pub.dev/packages/go_router) (Declarative URL routing & deep-linking)
* **Backend:** [Supabase](https://supabase.com/) (Serverless PostgreSQL database, Auth, Storage, and Deno Edge Functions)
* **Real-Time Calling:** [ZEGO Cloud SDK](https://www.zegocloud.com/) (P2P audio/video WebRTC engine)
* **Payments:** [eSewa SDK](https://esewa.com.np/) & [Khalti SDK](https://khalti.com/)
* **Translation:** [Google ML Kit](https://developers.google.com/ml-kit)

---

## 📐 System Architecture

```
                  +--------------------------------+
                  |          CLIENT LAYER          |
                  |  Flutter (Android / iOS / Web) |
                  +---------------+----------------+
                                  |
            (HTTPS / WebSocket)   |   (WebRTC)
         +------------------------+------------------------+
         |                                                 |
         v                                                 v
+-------------------------------+               +--------------------+
|         BACKEND LAYER         |               | INTEGRATION LAYER  |
|           Supabase            |               |                    |
|  - Auth (JWT Verification)    |               |  - ZEGO Cloud      |
|  - Storage (Medical Vault)    |               |  - eSewa / Khalti  |
|  - PostgreSQL Database        |               |  - Firebase FCM    |
|  - Row Level Security (RLS)   |               +--------------------+
+-------------------------------+
```

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have the following installed:
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.3.0`)
* Android Studio / Xcode (for mobile emulators)
* A [Supabase Account](https://supabase.com/) and project set up.

### 2. Configuration (Environment Variables)
Create an `env.json` file in the root of the project to securely inject compile-time variables (never commit this file to Git):

```json
{
  "SUPABASE_URL": "https://your-project-ref.supabase.co",
  "SUPABASE_ANON_KEY": "your-supabase-anon-key",
  "ZEGO_APP_ID": "your-zego-app-id",
  "ZEGO_APP_SIGN": "your-zego-app-sign",
  "ESEWA_SDK_CLIENT_ID": "your-esewa-client-id",
  "ESEWA_SDK_SECRET_ID": "your-esewa-secret-id",
  "ESEWA_SDK_ENVIRONMENT": "UAT"
}
```

### 3. Run the App Locally
Download packages and run the client:

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

---

## 🔒 Security & Privacy

* **Row Level Security (RLS):** Policies are enforced at the PostgreSQL level. Users can only query tables (such as `medical_records` or `vitals_log`) if the authenticated user's ID (`auth.uid()`) matches the record owner's ID.
* **Signed Storage URLs:** Medical documents uploaded to the private vault are accessible only via temporary signed URLs with a 1-hour expiration time.
* **Token Verification:** All RPC (Remote Procedure Call) database operations verify the user's JWT signature on the server before executing writes.

---

## 👥 Authors & Contributors

* **Isha Shah** ([IshaShah04](https://github.com/IshaShah04)) — Creator, Lead Architect & Developer

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
