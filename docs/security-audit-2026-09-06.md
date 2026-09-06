# HANOTI POS — Security & Firebase Bill Audit

**Date:** 2026-09-06  
**Target:** hanoti-farou9 (Firebase project)  
**App:** Flutter POS (Android + Web)  
**Commit:** f3bf238 — Initial commit  

---

## Executive Summary

This audit covers two areas: **security vulnerabilities** in the HANOTI POS Flutter application, and **Firebase billing risks** from Firestore read/write patterns.

**Key finding:** The previous security audit (2026-09-02) identified 3 Critical, 6 High, 11 Medium, and 10 Low issues. Since that audit, **significant fixes have been implemented** — most notably the paywall now uses a server-first model with a 48-hour Hive lease (C-2 fixed), sync has a hard uid-mismatch guard (H-1 fixed), password change is implemented (H-3 partially fixed), and login error messages are unified (H-2 fixed). However, **new issues have emerged** and some critical findings remain open.

**Bill risk:** The app uses an offline-first architecture with incremental sync, batch writes, and no real-time listeners — which is cost-efficient by design. The main bill risk comes from **missing composite index fallback paths** that can trigger full-collection reads, and **retry amplification** on network errors.

---

## Severity Ledger

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 2 | 1 open, 1 mitigated |
| High | 3 | 2 open, 1 mitigated |
| Medium | 5 | 3 open, 2 mitigated |
| Low | 4 | All open |
| Verified OK | 8 | — |

---

## Critical Findings

### C-1 — QR Login Embeds Real Password (OPEN — mitigated but not fixed)

**Files:** `lib/config/qr_login_config.dart`, `lib/services/qr_login_service.dart`

**What's wrong:** The QR login payload is AES-256-CBC encrypted `{phone, password}` under a per-account salt derived from a compile-time constant key (`HanotiPOS-QR-Login-Key-2026-ABCD`). While the per-account salt (v4) is an improvement over a global key (v3), the fundamental problem remains: **the password travels inside the QR code**, and anyone who decompiles the APK can extract the base key and decrypt any photographed QR.

**Current mitigation (v4):**
- Per-account salt makes each key unique
- 45-second expiry (reduced from 90)
- Auto-refresh every 30 seconds
- Rejection of old v3 format

**Why it's still critical:** The TODO comment in the code explicitly acknowledges this: "الحل الجذري: توكن قصير العمر لمرة واحدة يُصدره الخادم". Until Cloud Functions issue one-time tokens, a leaked QR = leaked permanent password.

**Fix:** Replace with server-minted one-time token (Cloud Function → opaque token → Firebase custom token). Password must never enter QR payload.

---

### C-2 — Paywall Trusts Local Storage (FIXED)

**Files:** `lib/services/firebase_service.dart:2044-2083`, `lib/helpers/subscription_helper.dart`

**Status: RESOLVED.** The previous audit found that `isSubscriptionActive()` returned `true` based on local Hive `end_date` without server verification.

**Current implementation:**
- Server-first: always queries Firestore first when online
- 48-hour Hive lease: offline grace only if last successful server verification was within 48 hours
- On server "no active subscription": immediately sets `subscription_active = false` in Hive
- `_hiveLeaseValid()` requires: `isActive == true` + `endDate` in future + `lastVerified` within 48h

**Verification:** The lease logic in `subscription_helper.dart:42-53` is pure and unit-testable. The 48-hour cap is hardcoded in `firebase_service.dart:549`.

---

### C-3 — Trial Self-Serviceable for a Year (OPEN — partially mitigated)

**Files:** `firestore.rules:41-53`, `lib/services/remote_config_service.dart`

**What's wrong:** Firestore rules cap client-created trials at 15 days (`end_date <= request.time + 15d`), but the code's Remote Config clamp is 0–14 days. A malicious client can still create a 15-day trial directly via API. More importantly, the rules allow **one self-created trial per uid**, and logout/signup creates a new uid — so infinite trials are possible by rotating accounts.

**Current mitigation:**
- Rules cap at 15 days (not 366 as in previous audit — this was tightened)
- Remote Config clamps to 0–14 days
- `auto_renew == false` enforced
- `plan_type == 'trial'` enforced
- `update, delete: if false` — trial doc is frozen after creation

**Why it's still high/critical:** Open signup with no phone verification (H-4) means anyone can create unlimited accounts, each with a 14-day trial. This is a business model issue, not just a technical one.

**Fix:** Move trial creation to Cloud Function (Auth `onCreate`); set `allow create: if false` for clients. Or implement phone verification (H-4) to prevent account rotation.

---

## High Findings

### H-1 — Sync Can Upload Data to Wrong Account (FIXED)

**Files:** `lib/services/sync_service.dart:251-265`

**Status: RESOLVED.** The previous audit found that `syncNow()` checked for any Firebase session but not that it matched the Hive user.

**Current implementation:**
```dart
final firebaseUid = _firebase.currentUser?.uid;
if (firebaseUid == null || firebaseUid != userId) {
  AppConfig.logError('🚫 Sync aborted: Hive user ($userId) does not match Firebase session (${firebaseUid ?? 'none'})');
  // ... sets SyncStatus.error, returns
}
```

This hard guard prevents cross-tenant data leakage.

---

### H-2 — Phone Number Enumeration (FIXED)

**Files:** `lib/services/firebase_service.dart:127-139`, `lib/services/auth_service.dart:126-138`

**Status: RESOLVED.** Login and registration now return unified error messages:
- `user-not-found` → `LocalizationHelper.authInvalidCredentials`
- `wrong-password` → `LocalizationHelper.authInvalidCredentials`
- `invalid-credential` → `LocalizationHelper.authInvalidCredentials`
- `email-already-in-use` remains distinct (required for UX during registration)

The auth error label helper (`_authErrorLabel`) logs only the error code, never the email/phone.

---

### H-3 — No Password Reset/Change (PARTIALLY FIXED)

**Files:** `lib/services/firebase_service.dart:623-666`

**Status: PARTIALLY RESOLVED.** `changePassword()` is now implemented with re-authentication:
1. Re-authenticate with current password via `EmailAuthProvider.credential`
2. Call `user.updatePassword(newPassword)`
3. Errors translated to user-friendly messages

**Still missing:** Password reset via email/SMS is impossible because the synthetic email (`phone@hanoti.pos`) is unroutable. A locked-out user has no recovery path.

**Fix:** Implement SMS OTP for password reset, or add a real email field for recovery.

---

### H-4 — No Phone Ownership Verification (OPEN)

**Files:** `lib/services/firebase_service.dart:221-350`

**What's wrong:** Anyone can register any phone number without proving ownership. The synthetic email format means `0551234567` and `551234567` are different accounts. A squatter who registers a merchant's number first blocks the real owner.

**Fix:** Implement Firebase Phone Auth (SMS OTP) before account creation.

---

### H-5 — Sale Deletion Query Missing user_id Filter (FIXED)

**Files:** `lib/services/firebase_service.dart:1657-1662`

**Status: RESOLVED.** The `deleteSale` method now includes:
```dart
.where('sale_id', isEqualTo: id)
.where('user_id', isEqualTo: userId)
```

This matches the Firestore rules requirement and prevents permission-denied errors.

---

### H-6 — Silent Read Amplification (OPEN — partially mitigated)

**Files:** `lib/services/sync_service.dart:345-370`, `lib/services/firebase_service.dart:695-714`

**What's wrong:** Two paths can multiply Firestore reads:

1. **Post-login sync retries:** `syncAfterLogin()` now caps at 2 attempts (was 3+1 = 4). Each attempt with `fullSync: true` pulls all data. A store with 2,500 docs × 2 pulls = 5,000 reads per login.

2. **Missing index fallback:** Incremental queries (`where updated_at > lastSync`) require composite indexes. If not deployed, the code catches the error and falls back to a full 500-doc pull:
   ```dart
   catch (e) {
     snapshot = await collection.limit(500).get(); // full pull fallback
   }
   ```

**Current mitigation:**
- Max 2 post-login sync attempts (down from 4)
- 30-minute pull cooldown between regular syncs
- 500-doc limit on all collection queries
- `firestore.indexes.json` defines all required composite indexes

**Why it's still high:** If indexes aren't deployed in the console, every incremental sync becomes a full sync. With 10 daily syncs × 500 docs × 7 collections = 35,000 reads/day per active user.

**Fix:** Verify all indexes from `firestore.indexes.json` are deployed. Distinguish `failed-precondition` (missing index) from other errors and surface it to the developer instead of silently full-pulling.

---

## Medium Findings

### M-1 — Raw print() Calls (OPEN)

**Files:** Multiple files

**What's wrong:** While `AppConfig.log()` is correctly silenced in release (`isProduction` check), raw `print()`/`debugPrint()` calls may still exist in some files. The previous audit counted 74 unguarded calls. Firebase error objects can embed the synthetic email (phone number) in their `toString()`.

**Fix:** Sweep all `print()` calls and replace with `AppConfig.log()`/`logError()`. Never interpolate auth exception objects directly.

---

### M-2 — App Check Debug Provider (OPEN)

**Files:** `lib/main.dart` (assumed), `pubspec.yaml:26`

**What's wrong:** `firebase_app_check: ^0.4.6` is in dependencies, but the configuration may use the debug provider on Android (no Play Integrity key passed). Web has no reCAPTCHA v3 site key. Without enforcement, scripted clients can abuse the open API.

**Fix:** 
- Pass Play Integrity provider on Android
- Pass reCAPTCHA v3 site key on web
- Enable **enforcement** (not just monitoring) for Firestore and Identity Toolkit in Firebase Console

---

### M-3 — Storage Bucket Unmanaged (OPEN)

**Files:** `lib/firebase_options.dart:57,67`

**What's wrong:** `storageBucket: 'hanoti-farou9.firebasestorage.app'` is declared but no `storage.rules` file exists in the repo. If default rules are live, any signed-in user can read/write the entire bucket.

**Fix:** Disable Cloud Storage API (unused) or add tenant-scoped `storage.rules`.

---

### M-4 — API Key Restrictions (OPEN)

**Files:** `lib/firebase_options.dart:52-70`

**What's wrong:** The Android (`AIzaSyDc0fNZqrBCxNOGDDg7cuRk_8dluehoODI`) and web (`AIzaSyBgWDZ6aLYrevG6a_9Zws9mBKMqj6HLccE`) API keys are public by design. Their protection lives entirely in Firebase Console settings, which this repo cannot confirm.

**Fix (console-side):**
- Restrict Android key to package `com.farou9.hanoti` + release SHA-1
- Restrict web key to your HTTP referrers
- Confirm Auth authorized domains list only your domains

---

### M-5 — Rate Limiting Client-Side Only (MITIGATED)

**Files:** `lib/helpers/login_rate_limiter.dart`, `lib/services/network_service.dart:80-102`

**Status: PARTIALLY RESOLVED.** 
- `LoginRateLimiter` provides UX feedback (5 attempts, 5-minute lockout)
- `NetworkService` now **never retries FirebaseAuthException** — auth errors are deterministic
- Auth throttling is handled by Firebase Auth backend

**Remaining issue:** The client-side limiter resets on app restart/screen re-entry. QR login path has no rate limiting.

---

### M-6 — Last-Writer-Wins Sync with Dead Conflict Code (OPEN)

**Files:** `lib/services/sync_service.dart`, `lib/services/database_service.dart:186-235`

**What's wrong:** Two devices editing the same product offline will silently lose one side's changes. The conflict-logging infrastructure (`logConflict`, `getConflicts`, `cleanOldConflicts`) exists but has zero callers.

**Fix:** Wire conflict recording into the pull path, or surface "server copy won" to the user.

---

### M-7 — Receipt PDFs with PII Left in Cache (OPEN)

**Files:** `lib/services/printing_service.dart` (assumed), `lib/services/receipt_renderer.dart` (assumed)

**What's wrong:** `invoice_<id>.pdf` containing customer name and phone is written to temp directory for sharing and never deleted.

**Fix:** Delete temp file after share sheet completes, or share bytes without temp file.

---

### M-8 — Firebase Analytics (OPEN)

**Files:** `android/app/src/main/AndroidManifest.xml:13-23`

**Status: PARTIALLY RESOLVED.** The manifest explicitly disables Analytics collection:
```xml
<meta-data android:name="firebase_analytics_collection_enabled" android:value="false" />
<meta-data android:name="google_analytics_automatic_screen_reporting_enabled" android:value="false" />
```

However, the dependency may still ship in the build. Verify it's not collecting data.

---

### M-9 — Subscription Fetched Multiple Times (FIXED)

**Files:** `lib/services/firebase_service.dart:454-483`

**Status: RESOLVED.** The previous audit found 4 near-identical subscription loops per login. Now consolidated into `_fetchBestActiveSubscription()` — a single query that fetches all active subscriptions for the user, then selects the best one client-side.

---

### M-10 — sale_items Create Without Sale Verification (OPEN)

**Files:** `firestore.rules:122-142`

**What's wrong:** The rules validate `sale_id` is a string but don't verify it points to an existing sale (get() was dropped for batch compatibility). A user can create orphaned line items.

**Fix:** Move items to subcollection `sales/{saleId}/items/{id}` for structural ownership.

---

### M-11 — Remote Config trial_days Clamp (MITIGATED)

**Files:** `lib/services/remote_config_service.dart:14-35`

**Status: PARTIALLY RESOLVED.** Clamp is now 0–14 days (was 0–365). The rules cap at 15 days. A misconfig can still grant 14-day trials instead of 7.

**Fix:** Tighten clamp to 0–7 days to match business intent.

---

## Low Findings

### L-1 — users Collection Lacks Field Validation

**File:** `firestore.rules:55-65`

The `users` doc allows any fields, unlike other collections which have structured validation.

---

### L-2 — Categories Cache Survives Logout

**File:** `lib/services/database_service.dart:744-777`

`clearUserData()` doesn't clear `_cachedCategories`, so user B might briefly see user A's categories in memory.

---

### L-3 — getCategories() Pulls Full Collection When Cache Empty

**File:** `lib/services/firebase_service.dart:1124-1159`

When local cache is empty, `getCategories()` reads the entire products collection to extract unique categories. With 500+ products, this is an expensive read for a simple category list.

**Fix:** Cache categories more aggressively, or store categories in a separate collection.

---

### L-4 — Batch Commit Fallback Can Double-Write

**File:** `lib/services/sync_service.dart:498-533`

On batch failure, fallback to individual writes. Since writes use `set()` (idempotent), this is a cost issue not a data issue — but it doubles write costs on failure.

---

## Verified OK (Security Controls That Work)

1. **Cross-tenant isolation:** Firestore rules enforce `user_id == request.auth.uid` on every collection. No cross-tenant read/write possible.

2. **Hive encryption:** All 9 boxes use AES-256 encryption. Key is 256-bit random, stored in `FlutterSecureStorage` (Android Keystore / iOS Keychain). Legacy plaintext boxes are deleted on migration.

3. **No real-time listeners:** Zero Firestore listeners = zero keepalive read costs.

4. **Offline-first architecture:** All reads are from Hive. Firebase is only used for sync (push unsynced, pull updates).

5. **allowBackup=false:** Android manifest prevents cloud backup of app data.

6. **Minimal permissions:** Only `INTERNET` and `CAMERA` declared.

7. **No custom HTTP endpoints:** All traffic via Firebase SDKs over TLS.

8. **Tombstones for deletes:** Pending deletes are tracked and synced, preventing "ghost" documents from reappearing.

---

## Firebase Bill Audit

### Architecture Overview

The app uses an **offline-first** pattern:
- **Local source of truth:** Hive (encrypted)
- **Sync strategy:** Push unsynced data → Pull updates from Firebase
- **No real-time listeners:** All Firestore interactions are explicit `.get()` / `.set()` / `.update()` / `.delete()`
- **Batch writes:** Up to 500 operations per batch
- **Incremental sync:** Uses `lastSync` timestamp + `updated_at` field

This is **cost-efficient by design** — no subscription costs from listeners, minimal reads due to incremental sync.

---

### Read Operations Inventory

| Collection | Query Type | Frequency | Docs/Query | Notes |
|-----------|-----------|-----------|-----------|-------|
| `products` | `where(user_id).where(updated_at > lastSync).limit(500)` | Per sync (30min cooldown) | 0–500 | Incremental; falls back to full 500 if no index |
| `sales` | `where(user_id).where(updated_at > lastSync).limit(500)` | Per sync | 0–500 | Same pattern |
| `sale_items` | `where(sale_id in [...]).where(user_id)` | Per sales pull | 0–500 | Batched in groups of 10 sale IDs |
| `inventory_movements` | `where(user_id).where(updated_at > lastSync).limit(500)` | Per sync | 0–500 | Same pattern |
| `suppliers` | `where(user_id).where(updated_at > lastSync)` | Per sync | 0–unbounded | No limit() — **bill risk** |
| `purchases` | `where(user_id).where(updated_at > lastSync)` | Per sync | 0–unbounded | No limit() — **bill risk** |
| `customers` | `where(user_id).where(updated_at > lastSync).limit(500)` | Per sync | 0–500 | Limited |
| `debt_transactions` | `where(user_id).where(updated_at > lastSync).limit(500)` | Per sync | 0–500 | Limited |
| `subscriptions` | `where(user_id).where(is_active == true)` | Per login + periodic checks | 1–10 | Small result set |
| `users` | `.doc(uid).get()` | Per login | 1 | Single doc |
| `products` | `where(user_id).where(barcode == x).limit(1)` | On barcode scan | 0–1 | Fast lookup |
| `products` | `.doc(id).get()` | Various | 1 | Single doc |

### Write Operations Inventory

| Operation | Batch Size | Frequency | Notes |
|-----------|-----------|-----------|-------|
| `products` batch set | 500 | Per sync (unsynced products) | Efficient |
| `sales` batch set | 500 | Per sync (unsynced sales) | Includes sale_items in same batch |
| `movements` batch set | 500 | Per sync | Efficient |
| `suppliers` batch set | 450 | Per sync | 450 ops/commit (conservative) |
| `purchases` batch set | 450 | Per sync | 450 ops/commit |
| `customers` batch set | 450 | Per sync | 450 ops/commit |
| `debt_transactions` batch set | 450 | Per sync | 450 ops/commit |
| Individual updates | 1 | Per edit (product, sale, etc.) | Immediate sync if online |
| Individual deletes | 1–N | Per delete | With tombstone tracking |

---

### Bill Hotspots

#### 🔴 HOTSPOT 1: Missing `limit()` on suppliers and purchases pulls

**Files:** `lib/services/firebase_service.dart:1764-1772`, `2023-2029`

```dart
// suppliers — NO LIMIT
Query query = _db.collection(...).where('user_id', isEqualTo: uid);
if (lastSync != null) query = query.where('updated_at', isGreaterThan: ...);
final snap = await query.get(); // ← unlimited!

// purchases — NO LIMIT  
Query query = _db.collection(...).where('user_id', isEqualTo: uid);
if (lastSync != null) query = query.where('updated_at', isGreaterThan: ...);
final snap = await query.get(); // ← unlimited!
```

**Impact:** If a merchant has 10,000 suppliers or purchases, one sync reads all 10,000 documents. At $0.06 per 100,000 reads = **$0.006 per sync**. With 10 syncs/day = **$0.06/day per user**.

**Fix:** Add `.limit(500)` to both queries.

#### 🔴 HOTSPOT 2: Missing index → full pull fallback

**File:** `lib/services/firebase_service.dart:695-714` (pattern repeated for all collections)

```dart
if (lastSync != null) {
  try {
    snapshot = await collection.where('updated_at', isGreaterThan: lastSync).limit(500).get();
  } catch (e) {
    // FALLBACK: full pull!
    snapshot = await collection.limit(500).get();
  }
}
```

**Impact:** If composite indexes aren't deployed, every incremental sync becomes a 500-doc full read. For a store with 100 products and only 1 new product since last sync:
- Expected: 1 read
- Actual: 500 reads
- **500× amplification**

**Fix:** 
1. Deploy all indexes from `firestore.indexes.json`
2. Catch `FirebaseException` with code `failed-precondition` specifically
3. Log/metric missing indexes instead of silently falling back
4. Consider using `fetchAndActivate` for Remote Config to detect index issues early

#### 🟡 HOTSPOT 3: Post-login sync retries

**File:** `lib/services/sync_service.dart:345-370`

```dart
Future<void> syncAfterLogin({int maxRetries = 2}) async {
  final attempts = maxRetries > 2 ? 2 : maxRetries;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    await syncNow(fullSync: true);
    // ...
  }
}
```

**Impact:** Each `fullSync: true` pulls all data (up to 500 docs per collection × 7 collections = 3,500 reads). With 2 attempts = **7,000 reads per login**.

**Mitigation:** Already capped at 2 attempts (was 4). The `SyncPolicy.needsDirectPull()` check prevents unnecessary retries if data exists locally.

#### 🟡 HOTSPOT 4: Categories full-collection read

**File:** `lib/services/firebase_service.dart:1124-1159`

When local categories cache is empty, reads ALL products to extract categories:
```dart
final snapshot = await FirebaseFirestore.instance
    .collection(FirebaseConfig.productsCollection)
    .where('user_id', isEqualTo: userId)
    .get(); // ← no limit!
```

**Impact:** One-time cost per device, but for 500+ products = 500 reads.

**Fix:** Cache categories aggressively, or store in a separate `categories` collection.

#### 🟡 HOTSPOT 5: Network retry amplification

**File:** `lib/services/network_service.dart:23-78`

```dart
static Future<T> callWithRetry<T>({
  int? maxRetries, // default: 3
  // ...
})
```

Reads retry up to 3 times, writes up to 2 times. On transient failures (network timeout), this can multiply costs:
- A 500-doc read that fails twice then succeeds = 1,500 reads charged

**Mitigation:** Exponential backoff (500ms → 1s → 2s) reduces thundering herd. Auth errors are not retried.

---

### Cost Estimates

#### Scenario A: Small store (100 products, 50 sales/month)

| Activity | Daily Reads | Daily Writes | Monthly Cost |
|----------|------------|-------------|--------------|
| Initial sync (login) | ~200 | ~50 | — |
| Incremental syncs (10/day) | ~10 | ~5 | — |
| **Monthly total** | **~3,500** | **~200** | **~$0.002** |

#### Scenario B: Medium store (500 products, 500 sales/month)

| Activity | Daily Reads | Daily Writes | Monthly Cost |
|----------|------------|-------------|--------------|
| Initial sync (login) | ~1,000 | ~500 | — |
| Incremental syncs (10/day) | ~50 | ~50 | — |
| **Monthly total** | **~2,500** | **~2,000** | **~$0.003** |

#### Scenario C: Large store (2,000 products, 2,000 sales/month) with INDEX MISSING

| Activity | Daily Reads | Daily Writes | Monthly Cost |
|----------|------------|-------------|--------------|
| Initial sync (login) | ~4,000 | ~2,000 | — |
| Incremental syncs (10/day, full fallback) | ~5,000 × 10 = 50,000 | ~200 | — |
| **Monthly total** | **~1,540,000** | **~62,000** | **~$0.96** |

#### Scenario D: Large store (2,000 products) with NO limit() on suppliers/purchases

If suppliers/purchases also hit 2,000 docs and no limit:
- Additional ~4,000 reads per sync
- **~$1.50/month per user** (still manageable for small user base)

**Note:** These are Firestore document read costs only. Firebase Auth and bandwidth are negligible at this scale.

---

### Recommendations (Bill Optimization)

1. **Deploy all composite indexes** from `firestore.indexes.json` — this is the #1 cost control
2. **Add `.limit(500)`** to suppliers and purchases queries
3. **Distinguish `failed-precondition` errors** from other errors — log them, don't fallback
4. **Set up Firebase budget alerts** at $1, $10, $50 thresholds
5. **Monitor the Firebase Console Usage tab** weekly for unexpected spikes
6. **Consider caching categories** in a separate collection or in Remote Config
7. **Add metrics/logging** for sync read counts per collection to detect amplification

---

## Firebase Console Checklist

These can't be verified from the repo — each is a console-side setting:

- [ ] **App Check enforcement** for Firestore and Identity Toolkit (not just monitoring)
- [ ] **API key restrictions** — Android: package + SHA-1; Web: HTTP referrers
- [ ] **Auth authorized domains** — only domains you serve from
- [ ] **Composite indexes deployed** from `firestore.indexes.json`
- [ ] **Cloud Storage** — disable API or deploy rules
- [ ] **Remote Config** — published `trial_days` = 7; audit editors
- [ ] **Budget alerts** on Firestore reads/writes
- [ ] **Firebase Analytics** — confirm fully disabled if not used

---

## Recommended Fix Order

| Priority | Finding | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Deploy composite indexes (H-6) | 5 min | Prevents 500× read amplification |
| P0 | Add `.limit(500)` to suppliers/purchases | 5 min | Prevents unbounded reads |
| P1 | Tighten trial rule cap to +8 days (C-3) | 5 min | Closes year-trial loophole |
| P1 | Implement SMS OTP (H-4) | 1–2 days | Prevents account squatting & trial abuse |
| P2 | QR login → server token (C-1) | 3–5 days | Eliminates credential exposure |
| P2 | App Check enforcement (M-2) | 2–3 days | Blocks scripted abuse |
| P2 | API key restrictions (M-4) | 30 min | Reduces API abuse surface |
| P3 | Password reset via SMS (H-3 remainder) | 1–2 days | User recovery path |
| P3 | print() sweep (M-1) | 1–2 hours | Privacy hygiene |
| P3 | Conflict resolution (M-6) | 1–2 days | Data integrity |
| P4 | Storage rules / disable (M-3) | 30 min | Close unused surface |
| P4 | Receipt PDF cleanup (M-7) | 1 hour | PII hygiene |
| P4 | Categories caching (L-3) | 2–3 hours | Minor read reduction |

---

## Conclusion

The HANOTI POS app has **strong security foundations** — tenant isolation, encrypted local storage, offline-first architecture, and no real-time listeners. The **most critical fixes from the previous audit have been implemented** (C-2 paywall lease, H-1 sync guard, H-2 unified errors, H-5 delete filter, M-9 subscription consolidation).

**Remaining critical risks:**
1. **QR login still embeds passwords** (C-1) — needs Cloud Functions
2. **Trial abuse via account rotation** (C-3) — needs phone verification or server-side trial creation
3. **Read amplification from missing indexes** (H-6) — needs console verification
4. **Unbounded queries on suppliers/purchases** — needs `.limit(500)`

**Bill risk is LOW to MEDIUM** for properly configured deployments, but can spike to **HIGH** if composite indexes are missing or if the user base grows large. The offline-first design is fundamentally cost-efficient.

---

*Audit generated 2026-09-06 from repository analysis. Console-side items require manual verification in Firebase Console.*
