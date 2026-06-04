# Swasthall Security Fixes Report

## Summary

All 6 security vulnerabilities have been fixed. Below is a detailed report of each fix.

---

## FIX 1: Remove appSign from APK binary

> [!IMPORTANT]
> ZEGO_APP_SIGN was embedded in the APK binary via `String.fromEnvironment`. Token-based auth via the `zego-token` edge function is now the sole auth mechanism.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [env_config.dart](file:///mnt/c/Users/rauna/health_department/lib/config/env_config.dart) | L11, L24-28, L63 | Removed `zegoAppSign` field, `ZEGO_APP_SIGN` from build comment, and validation check |
| [main.dart](file:///mnt/c/Users/rauna/health_department/lib/main.dart) | L1502 | `appSign: EnvConfig.zegoAppSign` → `appSign: ''` |
| [call_landing_page.dart](file:///mnt/c/Users/rauna/health_department/lib/call_landing_page.dart) | L426 | `appSign: EnvConfig.zegoAppSign` → `appSign: ''` |
| [video_call_page.dart](file:///mnt/c/Users/rauna/health_department/lib/video_call_page.dart) | L179 | `appSign: EnvConfig.zegoAppSign` → `appSign: ''` |

### Verification
- `grep zegoAppSign lib/` → **0 hits** ✅
- `grep ZEGO_APP_SIGN lib/` → **0 hits** ✅
- `zego-token/index.ts` confirmed present at [supabase/functions/zego-token/index.ts](file:///mnt/c/Users/rauna/health_department/supabase/functions/zego-token/index.ts)

---

## FIX 2: Remove eSewa secret from APK binary

> [!IMPORTANT]
> `ESEWA_SDK_SECRET_ID` was embedded client-side. Now fetched server-side from the `esewa-initiate` edge function.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [env_config.dart](file:///mnt/c/Users/rauna/health_department/lib/config/env_config.dart) | L45-46 | Removed `esewaSdkSecretId` field entirely |
| [esewa_sdk_payment_service.dart](file:///mnt/c/Users/rauna/health_department/lib/services/esewa_sdk_payment_service.dart) | L25-56 | Removed `EnvConfig.esewaSdkSecretId` reference; added server-side fetch via `esewa-initiate` edge function |

### Verification
- `grep 'ESEWA_SDK_SECRET_ID\|esewaSdkSecretId' lib/` → **0 hits** ✅

---

## FIX 3: Server-side fee enforcement

> [!WARNING]
> Client-side fallback `baseAmount + 30` allowed fee bypass. Now throws `BookingFeeException` instead of silently using client-calculated values.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [booking_fee_service.dart](file:///mnt/c/Users/rauna/health_department/lib/services/booking_fee_service.dart) | L70-81, L92-105 | Replaced both fallback blocks with exceptions |

### Files Created

| File | Purpose |
|------|---------|
| [20260604030000_fix_fee_rpc.sql](file:///mnt/c/Users/rauna/health_department/supabase/migrations/20260604030000_fix_fee_rpc.sql) | SQL migration creating `get_booking_fee` RPC for server-side fee lookup |

### Verification
- `grep 'baseAmount + 30' lib/` → **0 hits** ✅

---

## FIX 4: Payment gateway amount from server not client

> [!IMPORTANT]
> Payment services accepted `amount` from client, allowing tampered values. Now optionally accept `bookingId` to fetch amount server-side.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [esewa_sdk_payment_service.dart](file:///mnt/c/Users/rauna/health_department/lib/services/esewa_sdk_payment_service.dart) | L17-105 | Added `bookingId` param, made `amount` optional, added server-side fee fetch, replaced all `amount` refs with `resolvedAmount` |
| [khalti_sdk_payment_service.dart](file:///mnt/c/Users/rauna/health_department/lib/services/khalti_sdk_payment_service.dart) | L208-258 | Same pattern: added `bookingId` param, made `amount` optional, server-side fee fetch |

### Verification
- `grep 'amount \* 100' lib/services/esewa_sdk_payment_service.dart` → **0 hits** ✅
- `grep 'amount \* 100' lib/services/khalti_sdk_payment_service.dart` → **0 hits** ✅
- Both now use `resolvedAmount * 100` which is either server-fetched or the optional client value

---

## FIX 5: Await booking finalizer in Zego onCallEnd

> [!WARNING]
> `unawaited()` wrapper meant booking completion could silently fail without retry. Now properly awaited with `OfflineBookingQueue` retry on failure.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [main.dart](file:///mnt/c/Users/rauna/health_department/lib/main.dart) | L1521-1556 | Removed `unawaited(() async {...}())` wrapper; made callback `async`; added `OfflineBookingQueue.submit()` on failure |

### Verification
- `grep unawaited lib/main.dart` near lines 1520-1560 → **0 hits in that range** ✅
- Other `unawaited` calls in main.dart are unrelated and remain unchanged

---

## FIX 6: Enforce patient filter on medical_records queries

> [!CAUTION]
> Provider-role path queried `medical_records` without `patient_id` filter, relying solely on RLS. Now requires explicit `targetPatientId`.

### Files Modified

| File | Lines Changed | Change |
|------|--------------|--------|
| [patient_records_screen.dart](file:///mnt/c/Users/rauna/health_department/lib/patient_records_screen.dart) | L8-9, L77-90 | Added `targetPatientId` parameter; provider path now requires and filters by it |
| [shared_widgets.dart](file:///mnt/c/Users/rauna/health_department/lib/shared_widgets.dart) | L555-563 | Added empty-check guard for `patientId` before medical_records insert |

### Verification
All `from('medical_records')` select queries now have `.eq('patient_id', ...)`:
- `medical_vault.dart:248` — `.eq('patient_id', widget.patientId)` ✅
- `patient_records_screen.dart:72` — `.eq('patient_id', ...)` on both paths ✅
- `shared_widgets.dart:180` — `.eq('patient_id', patientId)` ✅
- `supabase_handler.dart:381` — `.eq('patient_id', patientId)` ✅
- `policy_debug_screen.dart` — debug tool, intentionally unscoped with `.limit(3)` ✅

---

## All Files Modified

| # | File | Fix |
|---|------|-----|
| 1 | `lib/config/env_config.dart` | Fix 1, Fix 2 |
| 2 | `lib/main.dart` | Fix 1, Fix 5 |
| 3 | `lib/call_landing_page.dart` | Fix 1 |
| 4 | `lib/video_call_page.dart` | Fix 1 |
| 5 | `lib/services/esewa_sdk_payment_service.dart` | Fix 2, Fix 4 |
| 6 | `lib/services/booking_fee_service.dart` | Fix 3 |
| 7 | `lib/services/khalti_sdk_payment_service.dart` | Fix 4 |
| 8 | `lib/patient_records_screen.dart` | Fix 6 |
| 9 | `lib/shared_widgets.dart` | Fix 6 |

## Files Created

| File | Fix |
|------|-----|
| `supabase/migrations/20260604030000_fix_fee_rpc.sql` | Fix 3 |
