# Employee Permission System (Worker Profiles) — Design

**Date:** 2026-08-26
**Status:** Approved (design sections 1–3 approved verbally in chat)
**Project:** hanotiapp (Flutter POS)

## 1. Overview / Purpose

Add a role-based permission system on top of the single-owner account model:

- One owner account (phone + Firebase Auth password) — unchanged.
- Multiple **worker profiles** created by the owner, each with a 4-digit-style **PIN** and a set of **permissions**.
- Owner can activate/deactivate any worker from the settings/employees screen.
- Workers sign in via profile selection + PIN (POS style), no Auth accounts.
- Every sale records which worker performed it.
- Everything syncs offline-first across store devices (same pattern as products/sales).

## 2. Decisions Made (user-approved)

| Question | Decision |
|---|---|
| Worker sign-in method | Profile + PIN (POS style) |
| Permissions granularity | Proposed split — 8 permissions |
| Multi-device sync | Full sync via existing offline-first pipeline |
| Who manages workers | Owner account only (no worker promotion) |
| Sale attribution | Yes — record worker per sale |

## 3. Data Model

### 3.1 `WorkerModel` (`lib/models/worker_model.dart`)

```
id            String (uuid v4)
user_id       String  // owner account uid — the owner of this profile
name          String
pin_hash      String  // salted SHA-256, never plaintext
is_active     bool    // owner toggles this
permissions   Map<String, bool>  // 8 keys below
created_at    DateTime
updated_at    DateTime
```

JSON + Hive adapter (TypeAdapter) following existing models' conventions
(`product_model.dart` pattern). Tolerant JSON parsing like suppliers/purchases.

### 3.2 Permission keys (constants in `lib/helpers/worker_permissions.dart`)

```
pos_sale               // POS screen & selling
products_inventory     // inventory screen
suppliers_purchases    // suppliers & purchases screens
sales_history          // sales history viewing
reports                // dashboard reports/stats
general_settings       // settings screen
day_open_close         // day open/close operations
employees_manage       // RESERVED: always evaluates false for workers;
                       // the employees tile/screen is visible to the owner
                       // account only. Kept as the 8th key so the data model,
                       // UI switches count (8), and presets stay stable.
```

Pure helper functions in the same file:

```dart
const allPermissions = [...8 keys...];
bool workerHasPermission(WorkerModel? w, String key); // null/false => false
Map<String,bool> defaultPermissions({required bool all}); // all-on for convenience presets
```

Owner bypasses every check at a higher level — helpers only evaluate workers.

### 3.3 PIN hashing (`lib/services/pin_service.dart` or pure helper + service wrapper)

- `hashPin(String pin, {String? salt})` → salted SHA-256, iterations >= 1000 (pure function, unit-tested).
- Salt stored alongside hash: `pin_hash = 'salt$iterations:hashhex'` format (self-describing string).
- No plaintext PIN ever leaves memory/log.

### 3.4 Hive

New box `workers`. Registration in `DatabaseService.init()` alongside others;
deletion uses existing `pending_delete_workers_$id` metadata mechanism already
generically implemented.

### 3.5 Firestore

Collection `workers/{workerId}`:

```
id, user_id (= owner uid), name, pin_hash, is_active,
permissions (map), created_at, updated_at  (serverTimestamp)
```

Rules addition (file `firestore.rules`) reusing existing helpers:

```
match /workers/{id} {
  allow create: if canCreate(request.auth.uid);
  allow read:   if canAccessOwned();
  allow update: if canUpdateOwned();
  allow delete: if canAccessOwned();
}
```

Deploy via `firebase deploy --only firestore:rules`.

### 3.6 Sale attribution

`SaleModel` gains optional fields `worker_id` (String?) and `worker_name`
(String?). Null-safe, ignored when absent; legacy documents parse fine.
Worker name stored as text so deleting a worker never breaks history.

## 4. Authentication Flow

### 4.1 Owner login — unchanged (phone + password → Firebase Auth).

### 4.2 Worker session (after owner is signed in on that device)

App state gains a lightweight notion of "active worker" persisted in memory +
Hive (`metadata.active_worker_id`). Splash decides:

- Not logged in → login screen (owner).
- Logged in as owner, no active worker, ≥1 active profile exists →
  **ProfilePickerScreen**.
- Active worker set → app runs with worker permissions banner context.

ProfilePickerScreen:
- Lists ACTIVE profiles only (deactivated ones invisible).
- Tap profile → PinPadScreen (numeric POS keypad, dots feedback).
- PIN is numeric, length 4–6 digits (chosen at profile creation).
- Verify locally against synced Hive copy (works fully offline).
- Wrong PIN ×5 → lock that profile for 30s (reuse `login_rate_limiter.dart`
  pattern with its own instance).
- Success → main app as worker. Logout button returns to picker (owner stays
  logged in).

### 4.3 Permission enforcement

`PermGate` widget (`lib/widgets/perm_gate.dart`):

```dart
PermGate(
  permission: WorkerPermissions.posSale,
  child: ...,
  // hides child when denied; owner always passes
)
```

A small inherited/state holder (`SessionScope` or Provider) exposes:

```dart
bool can(String permissionKey);   // owner => true; worker => map lookup
bool get isWorker;                // active worker present
WorkerModel? get currentWorker;
void exitWorkerSession();
```

Dashboard menu tiles and each top-level screen entry check through `can()`.
Direct deep-links to denied screens are blocked by the same gate at screen root.

## 5. Employees Management Screen (owner only)

`lib/screens/employees_screen.dart`, reachable from dashboard menu
(gated: owner sees it regardless; it maps to `employees_manage`).

List view:
- Each row: name, active toggle switch (immediate effect, persists to Hive +
  queues sync), permissions summary chips, edit, delete.

Add/Edit dialog:
- Name, PIN + confirm PIN (numeric, 4–6 digits), permission switches (8).
- Owner-only access enforced.
- Deactivate = soft disable: hidden from picker, session ends at next screen
  navigation after sync.

Delete: confirm dialog; keeps historical sales (name snapshot).

## 6. Sync Integration

Follows existing SyncService patterns exactly (see sync_policy.dart /
products flow):

- Push local dirty workers → Firestore upserts.
- Pull remote changes → overwrite Hive by `updated_at` last-write-wins.
- Deletions: pending_delete tombstone push then cleanup.
- Conflicts: LWW acceptable (rare concurrent edits of same profile).

No auth changes; workers never touch Firebase Auth.

## 7. Edge Cases

| Case | Behavior |
|---|---|
| 5 wrong PINs | Profile locked 30s (per-profile limiter) |
| Worker deactivated mid-session | Denied on next gated navigation post-sync |
| Deleted worker with past sales | Sales intact (name text snapshot) |
| Fully offline | Management works locally; worker login always works from Hive |
| No active profiles | Picker skipped entirely |
| Owner-only self-lockout | Impossible — owner bypasses everything |

## 8. Testing Plan (TDD — tests first, watched failing)

Unit:
1. `WorkerModel`: JSON roundtrip incl. tolerating null optionals; Hive roundtrip.
2. PIN hash: deterministic verify, wrong-PIN fails, unique salts across calls.
3. `workerHasPermission`: true/false/null-worker/owner handled upstream.
4. Per-profile PIN rate limiter: locks after 5, unlocks after duration.

Widget:
5. ProfilePickerScreen: lists only active; inactive absent; tap → PIN pad.
6. PinPadScreen: correct PIN enters; wrong increments attempts; locked shows
   countdown/disable.
7. EmployeesScreen: add worker; toggle activation updates row + persists;
   delete confirms.
8. PermGate: denies hidden; allowed visible; owner passes all.
9. Main menu respects `can()` for each tile (worker view reduced).

Model:
10. SaleModel gains optional worker fields without breaking old JSON.

## 9. Out of Scope (explicit YAGNI)

Shifts/schedules, salaries, work-hours tracking, worker self-service PIN reset
(owner resets instead), granular sub-permissions inside inventory.

## 10. Implementation Order (high level, detailed plan comes separately)

1. Models + permissions helper + PIN hashing + rate limiter (unit tests first).
2. DatabaseService box + repository CRUD.
3. SessionScope/can() + PermGate integration points.
4. Auth flow additions (picker + PIN pad).
5. Employees management screen.
6. Sale attribution fields + recording.
7. Firestore rules update + deploy.
8. SyncService worker channel.
9. Translations (ar/en/fr keys) + final analysis/tests run.
