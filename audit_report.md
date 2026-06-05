# Swasthall Security & Architecture Audit Report
**Date:** June 5, 2026
**Scope:** Full Codebase & Infrastructure Review

---

## PRELIMINARY — STACK IDENTIFICATION
- **Frontend framework + build tool:** Flutter (Dart)
- **Backend / BaaS:** Supabase (Database, Auth, Storage, Edge Functions)
- **Database type and provider:** PostgreSQL (Supabase)
- **Auth provider:** Supabase Auth
- **Hosting/deployment platform:** Supabase (Backend), App Stores / Web (Frontend), GitHub Releases (APK Distribution)
- **Version control platform:** Git / GitHub
- **CDN / Reverse Proxy / API Gateway:** Supabase API Gateway

---

## LAYER 1 — FRONTEND SECURITY (Client-Side Exposure)

**CRITICAL: Hardcoded Secrets Present in Source Directory**
Despite previous security fixes reported, raw secret files are sitting in the project root:
- `secrets.env`: Contains `FCM_SERVICE_ACCOUNT` with a plaintext Google Cloud private key (`-----BEGIN PRIVATE KEY-----`).
- `env.json`: Contains `SUPABASE_ANON_KEY`, `FDA_API_KEY`, `ZEGO_APP_SIGN`, and `ESEWA_SDK_SECRET_ID`. Even if unused in the current build, leaving them in the root is a major exposure risk.
- `android/swasthall-release.jks` and `android/key.properties`: Your production Android signing keystore and its passwords are in the repository. If this repo is ever compromised or made public, anyone can sign and publish malicious updates to your app.
- `.env.public-site`: Contains `PUBLIC_SITE_API_SALT`.

**MEDIUM: Verbose Logging in Production**
- `lib/main.dart` (L204, 223): Contains explicit `debugPrint` statements like `debugPrint('Widget action RPC failed: $primaryError — trying fallback')`. If not stripped in release builds, this exposes internal RPC names (`mark_booking_completed`, `mark_booking_missed`) to anyone observing the device logs via Logcat/Console.

---

## LAYER 2 — DATABASE SECURITY (RLS & Access Control)

**HIGH: `SECURITY DEFINER` RPC without Access Control (`get_booking_fee`)**
- Location: `supabase/migrations/20260604030000_fix_fee_rpc.sql`
- Finding: The function `get_booking_fee(p_booking_id uuid)` is marked `SECURITY DEFINER` but does not check if `auth.uid()` has permission to view the booking. Any authenticated user can pass any `booking_id` and probe fee structures across the entire platform.

**MEDIUM: Incomplete Relationship Validation (`sync_lab_test_assignments_atomic`)**
- Location: `supabase/migrations/20260411090000_sync_lab_test_assignments_atomic.sql`
- Finding: While the function correctly checks `v_auth_uid = p_hospital_id`, it blindly accepts any `technician_id` and `lab_test_id` provided in the JSON array. A malicious hospital could assign technicians that do not belong to them, potentially breaking RLS or hijacking technician queues.

**MISSING: Version Controlled Schema**
- Finding: The `supabase/migrations/` folder only contains 3 files. The vast majority of your schema (`profiles`, `medical_records`, `bookings`, `patient_vitals`) is not explicitly defined in migrations. This makes it impossible to verify the baseline RLS policies for the entire database.

---

## LAYER 3 — AUTHENTICATION & AUTHORIZATION

**HIGH: Missing Backend Role Validation (`public-site` Feedback)**
- Location: `supabase/functions/public-site/index.ts`
- Finding: The `/feedback` endpoint allows users to submit feedback with a `role` (e.g., `hospital_admin`, `doctor`). There is no backend verification that the user actually holds this role, allowing anyone to spoof administrative feedback.

**MEDIUM: Auth State Cleanup Failures**
- Location: `lib/main.dart`
- Finding: During `AuthChangeEvent.signedOut`, the app clears FCM tokens and resets call identity, but falls back to `debugPrint` if it fails. If the device goes offline right as the user logs out, the FCM token remains linked to the device, meaning the next user on that device might receive the previous user's push notifications.

---

## LAYER 4 — VERSION CONTROL (Git Security)

**CRITICAL: Secret History Exposure**
- Finding: Git history reveals that `secrets.env` was committed and later "removed from tracking" (commits `b3ab2fd`, `7f938d6`, `3592e08`). Deleting a file or adding it to `.gitignore` does **not** remove it from Git history. The Google Service Account Private Key is permanently exposed in the `.git` folder.
- **Recommended Fix:** You must invalidate and rotate the Google Service Account key immediately. Running BFG Repo-Cleaner or `git filter-repo` is required to scrub the history.

**HIGH: `android/` Keystore Committed**
- Finding: The production signing keys (`swasthall-release.jks`, `key.properties`) are physically present in the repository despite being listed in `.gitignore` (likely added to `.gitignore` after they were already committed).

---

## LAYER 5 — API SECURITY

**HIGH: IP Spoofing for Rate Limit Bypass**
- Location: `supabase/functions/public-site/index.ts` (L55)
- Finding: `getClientIp` trusts the `x-forwarded-for` header blindly.
  ```typescript
  const forwardedFor = req.headers.get("x-forwarded-for");
  if (forwardedFor) return forwardedFor.split(",")[0].trim();
  ```
  A malicious user can easily bypass the feedback/download rate limits by sending a forged `x-forwarded-for` header with a random IP on every request.

**MEDIUM: Lack of Request Payload Validation**
- Location: `supabase/functions/esewa-verify/index.ts`
- Finding: The function parses `req.json()` and extracts base64 data, but does not strictly validate the expected shape of `parsed`. It relies on eSewa's signature to fail later, but an attacker could send malformed data designed to cause unhandled exceptions before the signature check.

---

## LAYER 6 — HOSTING & DEPLOYMENT

**MISSING: CI/CD Pipeline**
- Finding: There is no `.github/workflows/` directory. Deployments, database migrations, and edge function updates appear to be done manually from local machines. This vastly increases the risk of deploying mismatched configurations or deploying with local secrets (like the ones found in the root directory).

**HIGH: APK Hosted on GitHub Releases**
- Finding: `.env.public-site` points `APK_URL` directly to a GitHub release binary. While acceptable for a pilot, there is no checksum verification mechanism provided to the user, making it susceptible to supply-chain tampering if the GitHub account is compromised.

---

## LAYER 7 — GENERAL SECURITY POSTURE

**HIGH: Data Encryption at Rest**
- Finding: There is no indication that PII or medical records (`medical_records`, `patient_vitals`) are encrypted at rest using application-level encryption (e.g., Tink or libsodium) before being written to Supabase. They rely entirely on Supabase's underlying disk encryption, meaning any DBA or unauthorized read access exposes raw health data.

---

## LAYER 8 — RATE LIMITING

**MEDIUM: Insufficient Rate Limit Window**
- Location: `public-site` Feedback
- Finding: Rate limit is 5 requests per hour per IP. However, due to the IP spoofing vulnerability in Layer 5, this rate limit is effectively `0` (bypassed).

**MISSING: Rate Limiting on Supabase RPCs**
- Finding: Critical RPCs like `sync_lab_test_assignments_atomic` and `get_booking_fee` have no application-level rate limiting. A malicious authenticated user can spam these endpoints and exhaust database connection pools or compute quotas.

---

## LAYER 9 — CACHING

**MEDIUM: In-Memory Cache TTL on Sensitive Data**
- Location: `lib/main.dart` (L257)
- Finding: `AppCache` stores `hospitals_list`, `lab_tests_list`, and `insurance_plans_list` for 10 minutes. If a hospital is deactivated or a lab test price is changed for compliance/security reasons, the client will operate on stale data for up to 10 minutes. Prices should be verified immediately before transaction. (The recent `get_booking_fee` RPC partially mitigates this at the checkout phase, but UI will show wrong values).

---

## LAYER 10 — SCALING & LOAD HANDLING

**HIGH: Realtime Subscription Architecture**
- Location: `lib/main.dart` -> `HomeWidget` Background Task
- Finding: The app connects directly to Supabase via `Supabase.initialize` inside background workers (`callbackDispatcher`) and attempts to fire RPCs (`mark_booking_completed`). Every background widget interaction spins up a new client connection. At scale, thousands of phones firing background widget updates will instantly exhaust Supabase connection limits.

---

## LAYER 11 — ERROR TRACKING & OBSERVABILITY

**MEDIUM: Fatal Error Masking**
- Location: `lib/main.dart`
- Finding: The crashlytics configuration deliberately drops/masks errors related to `AppLifecycleState` ("Invalid state transition"). While marked as non-fatal to avoid noise, this suppresses actual bugs in the Zego UIKit lifecycle that could lead to dropped telehealth calls without the engineering team knowing.

---

## FINAL OUTPUT — AUDIT SUMMARY

### 1. CRITICAL FINDINGS (Fix before any production launch)
| Layer | Finding | File/Location | Recommended Fix |
|-------|---------|---------------|-----------------|
| 1 | Hardcoded Secrets in Repo | `secrets.env`, `env.json` | Delete files. Rotate the Google FCM Private Key, eSewa secret, and Zego App Sign immediately. |
| 4 | Git History Secret Exposure | `.git` history | Use BFG Repo-Cleaner to purge `secrets.env` and `env.json` from git history. |
| 4 | Android Keystore Exposed | `android/swasthall-release.jks` | Remove from repo, purge from history, generate a NEW production signing key. |

### 2. HIGH PRIORITY (Fix within 2 weeks)
| Layer | Finding | File/Location | Recommended Fix |
|-------|---------|---------------|-----------------|
| 2 | RPC Auth Bypass | `supabase/migrations/...fix_fee_rpc.sql` | Add `AND b.user_id = auth.uid()` to the `get_booking_fee` query. |
| 5 | Rate Limit IP Spoofing | `supabase/functions/public-site/index.ts` | Remove reliance on `x-forwarded-for`. Use Cloudflare/Supabase native rate limiting instead. |
| 10 | Background Connection Exhaustion | `lib/main.dart` | Replace direct Supabase client initialization in `callbackDispatcher` with a lightweight edge function call via standard HTTP. |

### 3. MEDIUM PRIORITY (Fix within 1 month)
| Layer | Finding | File/Location | Recommended Fix |
|-------|---------|---------------|-----------------|
| 2 | Technician ID Validation | `...sync_lab_test_assignments_atomic.sql` | Validate that the `technician_id` belongs to `p_hospital_id` before inserting. |
| 11 | Silencing Crashlytics | `lib/main.dart` | Stop filtering `AppLifecycleState` exceptions; fix the underlying Zego state management issue. |

### 4. MISSING LAYERS
- **Layer 2 (Partial):** Missing centralized version-controlled schema migrations for baseline tables.
- **Layer 6 (Complete):** Missing automated CI/CD pipeline for safe, secret-free deployments.
- **Layer 7 (Partial):** Missing application-level encryption at rest for PII/Health data.

### 5. COVERAGE SCORECARD

| Layer             | Status         | Score |
|-------------------|----------------|-------|
| Frontend Security | Partial        | 3/10  |
| Database (RLS)    | Partial        | 4/10  |
| Auth              | Partial        | 7/10  |
| Version Control   | Failed         | 1/10  |
| API Security      | Partial        | 5/10  |
| Hosting/Deploy    | Missing CI/CD  | 3/10  |
| Security Posture  | Partial        | 4/10  |
| Rate Limiting     | Weak           | 4/10  |
| Caching           | Done           | 8/10  |
| Scaling           | Partial        | 5/10  |
| Error Tracking    | Done           | 8/10  |
| **TOTAL**         |                | **52/110** |

### 6. TOP 3 IMMEDIATE ACTIONS
1. **Rotate Exposed Keys:** Your Firebase Admin SDK private key, Android Keystore, and eSewa secrets are compromised in Git history. Rotate them and force-push a sanitized history using BFG Repo-Cleaner.
2. **Secure the `get_booking_fee` RPC:** Currently, anyone can query fee configs for any booking ID. Lock it down to the booking owner.
3. **Fix IP Spoofing in Edge Functions:** Stop trusting `x-forwarded-for` blindly in the public site Edge Function, as it renders your rate limits completely useless.
