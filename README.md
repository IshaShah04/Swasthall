# SwasthAll

SwasthAll is a family healthcare mobile and web application built for the Nepalese market. It connects patients with doctors for virtual consultations, provides nurse-managed intake queues, integrates local payment options (eSewa, Khalti), and offers a secure vault for medical histories.

## Features

- **Virtual Consultations:** Live audio/video calling using WebRTC (ZEGO Cloud).
- **Family Accounts:** Link dependent profiles under a single parent account.
- **Triage Queue:** Structured workflow allowing nurses to record vitals before doctor consultations.
- **Health Vault:** Document uploads (PDFs, images) and vitals logs secured with PostgreSQL Row Level Security (RLS).
- **Payment Gateways:** Local checkouts via eSewa and Khalti.
- **Localization:** English, Nepali, and Hindi support with Google ML Kit offline translation.

## Tech Stack

- **Frontend:** Flutter & Dart
- **State Management:** Riverpod
- **Routing:** GoRouter
- **Backend:** Supabase (Database, Auth, Storage, Edge Functions)
- **Video/Audio:** ZEGO Cloud SDK
- **Payments:** eSewa SDK & Khalti SDK

## Setup & Running

1. **Configure environment variables:**
   Create an `env.json` file in the project root:
   ```json
   {
     "SUPABASE_URL": "https://your-project.supabase.co",
     "SUPABASE_ANON_KEY": "your-anon-key",
     "ZEGO_APP_ID": "your-zego-app-id",
     "ZEGO_APP_SIGN": "your-zego-app-sign",
     "ESEWA_SDK_CLIENT_ID": "your-esewa-client-id",
     "ESEWA_SDK_SECRET_ID": "your-esewa-secret-id",
     "ESEWA_SDK_ENVIRONMENT": "UAT"
   }
   ```

2. **Get packages and run the application:**
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```

## License

This project is licensed under the MIT License.
