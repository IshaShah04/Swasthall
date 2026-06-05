# Swasthall Application Security & Architecture Audit Report (v2 - Post Remediation)

**Date:** 2026-06-05
**Scope:** Full codebase review across 11 architectural layers.
**Objective:** Identify and patch security vulnerabilities, misconfigurations, and architectural bottlenecks.

---

## PRELIMINARY — STACK IDENTIFICATION
- **Frontend:** Flutter
- **Backend / BaaS:** Supabase (Auth, PostgreSQL, Edge Functions)
- **Error Tracking:** Firebase Crashlytics
- **WebRTC / Calling:** Zego Cloud
- **Payment Gateway:** eSewa

---

## 1. CRITICAL FINDINGS (Immediate Action Required)
*All critical code-level vulnerabilities have been patched in this remediation pass. Only operational key rotations remain.*

| Layer | Finding | Location | Status / Action |
|-------|---------|----------|-----------------|
| **Layer 4** | **Key Rotation Required** | Cloud Dashboards | **ACTION REQUIRED BY USER**. All exposed keys (Google Cloud FCM, Supabase, eSewa, Zego, Android Keystore) must be regenerated in their respective dashboards immediately. |
| **Layer 4** | **Force Push Git History** | Git Remote | **ACTION REQUIRED BY USER**. Run `git push origin main --force` to overwrite the remote repository with the newly cleaned history. |

---

## 2. HIGH PRIORITY (Fix within 2 weeks)
*All high-priority issues have been successfully patched.*

| Layer | Finding | Location | Status |
|-------|---------|----------|--------|
| **Layer 2** | RPC Auth Bypass | `get_booking_fee` | **FIXED**. Implemented strict `auth.uid()` checks to prevent horizontal enumeration of booking fees. |
| **Layer 5** | IP Spoofing Rate Limit Bypass | `public-site` Edge Function | **FIXED**. Removed reliance on spoofable `x-forwarded-for` header. Now strictly enforces `cf-connecting-ip`. |
| **Layer 10** | Database Connection Exhaustion | `HomeWidget` Dispatcher | **FIXED**. Replaced direct Supabase DB initialization in the background widget worker with a pooled Edge Function (`widget-action`), preventing connection exhaustion at scale. |

---

## 3. MEDIUM PRIORITY (Fix within 1 month)

| Layer | Finding | Location | Status |
|-------|---------|----------|--------|
| **Layer 2** | Technician ID Injection | `sync_lab_test_assignments_atomic` | **FIXED**. Added validation loops to ensure injected arrays of technicians strictly belong to the authenticating hospital. |
| **Layer 5** | Unhandled Exceptions in Gateway | `esewa-verify` | **FIXED**. Added strict JSON validation guards to prevent malicious malformed payloads from crashing the function. |
| **Layer 11** | Blindspots in Error Tracking | `main.dart` Crashlytics | **FIXED**. Removed filters that were silently discarding `AppLifecycleState` bugs from the Zego SDK. |
| **Layer 6** | No automated CI/CD pipeline | N/A | **OPEN**. Production builds are done manually. |
| **Layer 7** | No PII Encryption at Rest | Database | **OPEN**. Medical history and patient PII are not explicitly encrypted at rest beyond standard Postgres volume encryption. |

---

## 4. MISSING LAYERS
- **Automated CI/CD:** No GitHub Actions or Fastlane pipelines exist. Deployments are manual, increasing the risk of human error and missing obfuscation flags during build.

---

## 5. COVERAGE SCORECARD (Post-Remediation)

| Layer | Status | Previous Score | **New Score** |
|-------|--------|----------------|---------------|
| Frontend Security | Done | 3/10 | **10/10** |
| Database (RLS) | Partial | 4/10 | **8/10** |
| Auth | Partial | 7/10 | **7/10** |
| Version Control | Partial | 1/10 | **9/10** |
| API Security | Done | 5/10 | **8/10** |
| Hosting/Deploy | Missing | 3/10 | **3/10** |
| Security Posture | Partial | 4/10 | **4/10** |
| Rate Limiting | Partial | 4/10 | **6/10** |
| Caching | Done | 8/10 | **8/10** |
| Scaling | Done | 5/10 | **8/10** |
| Error Tracking | Done | 8/10 | **9/10** |
| **TOTAL** | | 52/110 | **80/110** |

---

## 6. TOP 3 IMMEDIATE ACTIONS FOR YOU

1. **Rotate All Keys:** Go to your Supabase, Google Cloud, eSewa, and Zego dashboards and generate brand new keys. Your old ones are permanently compromised.
2. **Generate New Android Keystore:** Create a brand new `swasthall-release.jks` and update your app signing settings in the Google Play Console if you are using Play App Signing.
3. **Force Push to GitHub:** Run `git push origin main --force` on your local machine to overwrite the remote repository with the clean, secret-free git history I just generated for you.
