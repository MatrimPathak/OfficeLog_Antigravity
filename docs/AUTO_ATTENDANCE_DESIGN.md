# Automatic Attendance Detection — Design

This document covers the redesigned automatic check-in/check-out system in
`lib/services/attendance_detection/`. It replaces "geofence event == attendance
event" with a small evidence-driven decision engine that sits between raw
platform signals and the existing `AttendanceService`/Firestore layer, which is
otherwise unchanged.

## 1. Why geofence events alone are not enough

A circular geofence answers "is the phone within N meters of a point?", not
"is the user at their desk?". Two failure modes motivate this redesign:

- **False arrival**: a geofence ENTER fires the instant the user is within
  radius — including while driving past, idling at a nearby light, or sitting
  in the parking lot. Firing a check-in on ENTER cannot distinguish these from
  a real arrival.
- **False departure**: a geofence EXIT fires only once the OS's internal
  hysteresis/GPS fusion finally decides the phone left the region, which can
  lag the user's actual departure from their desk by many minutes (elevator,
  building exit, walk to parking). Using the EXIT timestamp as the check-out
  time is systematically late, and firing a check-out on EXIT at all doesn't
  distinguish "stepped out to another floor" from "actually left."

The fix is not a bigger/smaller radius — it's evaluating a *state machine over
accumulated evidence*, where geofence transitions only ever *initiate*
evaluation, never *conclude* it by themselves.

## 2. State machine

```
UNKNOWN → NEAR_WORKPLACE → POSSIBLE_ARRIVAL → AT_WORKPLACE
                                                    ↓
                                          POSSIBLE_DEPARTURE
                                                    ↓
                                          AWAY_FROM_WORKPLACE → (UNKNOWN/NEAR_WORKPLACE on next signal)
```

Transitions (`DetectionStateMachine._advance` in
`detection_state_machine.dart`):

| From | Trigger | To | Notes |
|---|---|---|---|
| UNKNOWN/AWAY | geofence ENTER, or a foreground/location sample inside radius | NEAR_WORKPLACE | Starts a new "episode" (fresh observation history). No attendance action. |
| NEAR_WORKPLACE | geofence DWELL, or *soft dwell* (still inside radius after `softDwellDuration` with no intervening EXIT), or `arrivalConfidence` crosses `arrivalContinueThreshold` | POSSIBLE_ARRIVAL | Still no attendance action — just means "worth taking a closer look." |
| NEAR_WORKPLACE/POSSIBLE_ARRIVAL | geofence EXIT before any dwell evidence, within `passByGraceDuration` of the first ENTER | UNKNOWN (episode discarded) | This is the "drove past the office" case — the episode is thrown away, nothing is written. |
| POSSIBLE_ARRIVAL | `arrivalConfidence >= arrivalHighThreshold` | AT_WORKPLACE | **This is the only edge that creates a CHECK_IN.** |
| AT_WORKPLACE | geofence EXIT, or a sample clearly outside radius | POSSIBLE_DEPARTURE | No attendance action yet. |
| POSSIBLE_DEPARTURE | re-entry (ENTER/inside sample) within `departureCancelWindow` | AT_WORKPLACE | Handles "walked to another floor / stepped outside briefly", GPS jitter at the boundary. |
| POSSIBLE_DEPARTURE | `departureConfidence >= departureHighThreshold` | AWAY_FROM_WORKPLACE | **This is the only edge that creates a CHECK_OUT.** |
| POSSIBLE_ARRIVAL/POSSIBLE_DEPARTURE | confidence stays below the low threshold for the whole episode with no new corroborating signal | reverts to NEAR_WORKPLACE / AT_WORKPLACE respectively | Evidence collection continues; no negative attendance action is ever taken automatically — we simply never gather enough to conclude. |

State + the current episode's observation history are persisted (see §7) after
every transition, so the machine survives process death and resumes exactly
where it left off on the next OS-delivered event.

## 3. Common event model

`DetectionObservation` (`detection_models.dart`) is the single shape every
platform adapter produces; the engine never sees a raw `Position` or native
geofence callback directly:

```dart
enum DetectionActivity { stationary, walking, running, cycling, vehicle, unknown }

class DetectionObservation {
  final DateTime timestamp;         // device clock at sample time
  final DetectionActivity activity;
  final double? distanceMeters;     // derived, NOT raw lat/lng (see §8 privacy)
  final double? accuracyMeters;
  final bool? workplaceNetworkDetected; // optional (Android-only in practice)
  final bool? workplaceRegionActive;    // geofence "inside" state at sample time
  final GeofenceTransition? transition; // enter/exit/dwell, null for polled samples
  final bool isMocked;
  final String source;              // 'geofence' | 'location_burst' | 'activity' | 'foreground_check'
}
```

Deliberately **not included**: raw latitude/longitude. The engine only ever
needs distance-from-workplace, so adapters compute that once and discard the
coordinate (see §8).

## 4. Evidence & confidence engine

`confidence_engine.dart` scores an *episode* (the bounded observation history
since the state machine last left UNKNOWN/AWAY) against named evidence
components, each independently optional:

- **GeofenceEvidence** — did we see DWELL (native, Android) or *soft dwell*
  (elapsed-time-inside-without-exit, computed identically on both platforms)?
- **LocationEvidence** — is distance comfortably inside/outside radius with
  good accuracy (not mocked)? Distance is evaluated with a hysteresis band
  (`radius * departureHysteresisFactor` for leaving) so boundary jitter can't
  flip the verdict.
- **ActivityEvidence** — STATIONARY/WALKING support arrival, VEHICLE opposes
  it; the same activity vocabulary is reused with inverted polarity for
  departure (WALKING/VEHICLE moving away supports departure, STATIONARY
  opposes it). UNKNOWN activity contributes zero (neither help nor hurt).
- **NetworkEvidence** — *optional*. Only Android reliably exposes an app-
  visible Wi-Fi SSID/BSSID without extra location-permission strings; iOS
  effectively never does for a third-party app. When absent, its weight is
  **not** counted as a penalty — the remaining weights are renormalized so
  100% confidence is still reachable from geofence + location + activity
  alone. This directly implements "Wi-Fi must be optional, not required."
- **TemporalEvidence** — small bonus for the same state persisting across
  multiple independent wake-ups (each OS-delivered event is a separate,
  independently-verifying sample; agreement across time is itself evidence).
- **HistoricalEvidence** — small bonus if the transition is happening near the
  user's typical recent arrival/departure time-of-day (computed from the last
  N logged sessions already in `AttendanceService`); a low-weight tie-breaker
  only, never load-bearing.

All weights live in `DetectionConfig` (see §6) — nothing is a scattered magic
number. `computeArrivalConfidence`/`computeDepartureConfidence` return both a
`double` in `[0,1]` and a `Map<String,bool/double>` evidence breakdown that
flows straight into the diagnostic log and the persisted attendance metadata.

Per the "fully automatic" requirement, there is no user-confirmation branch:
confidence in `[low, high)` simply means "keep collecting on the next signal,"
not "ask the user." If confidence never reaches the high threshold, no
attendance event is ever created for that episode — silence, not a prompt.

## 5. Timestamp estimation

Never `geofenceEvent.timestamp`. `timestamp_estimator.dart` walks the
episode's observation history and picks the **earliest observation timestamp
that already satisfied the relevant per-evidence-item threshold**, once a
later observation confirms the transition:

- *Arrival*: among observations recorded while state was NEAR_WORKPLACE or
  POSSIBLE_ARRIVAL, find the earliest one whose *individual* evidence already
  looked arrival-supporting (inside radius AND activity ∈
  {stationary, walking, unknown}) that is followed by no contradicting
  VEHICLE/outside-radius sample before AT_WORKPLACE is reached. That
  observation's timestamp is the estimated arrival time. If no single earlier
  observation qualifies (e.g. only the confirming sample itself has good
  evidence), we fall back to that confirming sample's timestamp rather than
  inventing precision we don't have.
- *Departure*: symmetric — the earliest observation after the last confirmed
  AT_WORKPLACE sample whose evidence already looked departure-supporting
  (outside hysteresis band, or WALKING/VEHICLE activity), that survives to the
  confirming EXIT/departure-confidence sample.

Every decision the engine emits carries a short human-readable
`timestampRationale` string (e.g. *"backdated 6m from confirmation to first
WALKING+outside-radius sample at 17:34; no contradicting sample in between"*)
so "why did OfficeLog check me in/out at this time?" always has a concrete
answer in the logs — see §9.

**Honesty about precision**: because Android/iOS only wake the app at
discrete OS-chosen moments (geofence transitions, app foreground, occasional
opportunistic samples — see §6.2), the engine cannot reconstruct a continuous
trajectory like the illustrative 08:45/08:50/08:54/... example in the spec. It
picks the best *available* sample, not a synthesized one, and the rationale
string always names which sample was used and why.

## 6. Confidence/timing configuration (`detection_config.dart`)

All tunables are documented, named fields on one `DetectionConfig` class
(`DetectionConfig.defaultConfig`), not inline magic numbers:

| Field | Default | Why |
|---|---|---|
| `arrivalHighThreshold` | 0.72 | Confidence at/above this → automatic CHECK_IN. |
| `arrivalContinueThreshold` | 0.30 | Below this, discard episode back toward NEAR_WORKPLACE instead of lingering in POSSIBLE_ARRIVAL. |
| `departureHighThreshold` | 0.68 | Confidence at/above this → automatic CHECK_OUT. Slightly lower than arrival because false departures are self-correcting (a subsequent re-entry within `departureCancelWindow` reopens the session) while false arrivals are not. |
| `departureContinueThreshold` | 0.28 | Symmetric to arrival. |
| `softDwellDuration` | 3 min | Elapsed inside-radius time (no intervening EXIT) that counts as dwell evidence even without a native DWELL event — this is what makes iOS behave like Android despite no native dwell trigger. |
| `passByGraceDuration` | 2 min | If EXIT arrives within this of the first ENTER with no dwell evidence at all, the whole episode is discarded — the "drove past" case. |
| `departureCancelWindow` | 10 min | Re-entry within this window while still in POSSIBLE_DEPARTURE cancels the departure and returns to AT_WORKPLACE — the "went to another floor" case. |
| `departureHysteresisFactor` | 1.15× radius | Distance must clear radius by this margin to count as strong departure evidence; damps boundary jitter. |
| `maxEpisodeObservations` / `maxEpisodeAge` | 40 / 20h | Bounds on the retained per-episode history (battery + storage + privacy). |
| Evidence weights (`geofenceWeight`, `locationWeight`, `activityWeight`, `networkWeight`, `temporalWeight`, `historicalWeight`) | 0.30 / 0.25 / 0.25 / 0.10 / 0.05 / 0.05 | Sum to 1.0; renormalized over whatever evidence is actually available for a given episode (see §4). |

These are deliberately conservative starting points meant to be tuned from
real diagnostic logs, not claimed as empirically optimal.

### 6.2 Deferred confirmation: getting a second sample without the user's help

Everything above assumes the episode eventually receives a *second*,
corroborating observation — that's what promotes NEAR_WORKPLACE to
POSSIBLE_ARRIVAL, and what lets soft-dwell/sustained-absence evidence become
true. But a bare geofence ENTER/EXIT only invokes the handler **once**. If
the user never reopens the app and no further OS-delivered geofence event
happens to arrive on its own, nothing would ever supply that second sample —
the episode would sit in NEAR_WORKPLACE/POSSIBLE_ARRIVAL/POSSIBLE_DEPARTURE
forever, and automatic detection would silently never resolve. This isn't
hypothetical: it's the normal case for a user who arrives, locks their phone,
and puts it in a pocket.

`AttendanceDetectionEngine` closes this gap itself: whenever a processed
observation leaves the episode in one of those three in-progress states, it
schedules a **single deferred re-check** (`confirmation_scheduler.dart`) that
re-runs the exact same foreground-check code path a user opening the app
already triggers (`AutoCheckInService.checkAndLogAttendance`) — supplying the
missing second sample without the user doing anything. Once the episode
resolves (a decision commits, or it's discarded as a pass-by/etc.), the
pending re-check is cancelled so it doesn't keep firing uselessly.

The two platforms are honestly different here (`workmanager`, wrapping each
platform's real background-task API — see §10):

- **Android**: a real WorkManager one-off task with a precise `initialDelay`
  (`softDwellDuration` for an arrival episode, half of that for a departure
  episode, matching the elapsed-time evidence those states are waiting on).
  WorkManager itself survives process death and reboot, and already handles
  Doze deferral — nothing extra was needed here.
- **iOS**: this plugin's own `registerOneOffTask` turned out **not** to be a
  real deferred wake on iOS — it's a short `beginBackgroundTask` extension
  that only helps while the app is already alive, not a mechanism that wakes
  a suspended/terminated app later. The actual Apple API for that is
  `BGTaskScheduler`, exposed here as `registerPeriodicTask`
  (`BGAppRefreshTask`). iOS decides *opportunistically* when to actually run
  it — there is no precise-delay guarantee — so the requested delay is
  honored as a minimum only, and the task recurs (at most every 15 minutes,
  the platform floor) until cancelled. This is the correct, real mechanism
  for the job; it is simply not as prompt as Android's, which is an honest
  platform limitation being surfaced, not papered over.

## 7. Persistence & resilience

`detection_persistence.dart` stores one small JSON-ish record per user in a
dedicated Hive box (`attendance_detection_state`, consistent with the existing
`attendance_logs`/`app_logs` boxes): current `AttendanceDetectionState`, the
current episode's bounded observation list (distances/activity only, see §8),
and the timestamp of the most recently processed observation. Idempotency
falls directly out of the state machine's own structure rather than a
separate dedupe-key system: once a decision commits, the state transitions to
AT_WORKPLACE/AWAY_FROM_WORKPLACE, and further matching events (a replayed
ENTER, a duplicate DWELL) hit that state's "still inside / still outside, no
action" branch — see §11 (duplicate prevention) for the full argument. Every
entry point (`geofenceTriggered` background isolate, the existing foreground
check on app resume, and the new deferred confirmation re-check in §6.2)
loads this record fresh — the engine never assumes in-memory continuity,
matching the existing codebase's own pattern in `background_service.dart`.

A local-day rollover resets a stale state back to UNKNOWN rather than letting
yesterday bleed into today — checked against the in-progress episode's anchor
timestamp when there is one, and otherwise against the last-processed-
observation timestamp, so a *committed* AT_WORKPLACE with no episode of its
own (e.g. a missed EXIT callback left a check-in never followed by a
check-out) still resets instead of silently blocking next-day auto check-in,
consistent with the existing `isLoggedToday`-per-date design in
`AttendanceService`.

## 8. Battery & privacy strategy

Normal operation is **OS-native low-power region monitoring only**
(`native_geofence`, already in place — Android `GeofencingClient` / iOS
`CLCircularRegion`, both hardware-assisted, no continuous GPS polling from
this app). A "burst" — one bounded on-demand location fetch
(`LocationAccuracy.medium`, few-second timeout, unchanged from the existing
code) plus one activity read — runs only inside the handler for an
OS-delivered geofence transition, an explicit app-foreground check, or the
deferred confirmation re-check from §6.2. There is no continuous polling
loop anywhere in this design: the confirmation re-check is a *single*
bounded task (Android: one-off; iOS: recurring at the 15-minute platform
floor only, and only) that self-cancels the moment the episode it exists for
resolves — it never runs indefinitely, and never runs at all while every
episode is already resolved (UNKNOWN/AT_WORKPLACE/AWAY_FROM_WORKPLACE).

Privacy: raw latitude/longitude is used only transiently in memory to compute
`distanceMeters`, which is what's persisted — coordinates themselves are never
written to Hive, Firestore, or the diagnostic log. Episode history is capped
(`maxEpisodeObservations`/`maxEpisodeAge`) and cleared once a decision is
emitted or an episode is discarded, so no long-lived location trail
accumulates on-device.

## 9. Diagnostics

`detection_diagnostics.dart` writes one structured line per state transition
and per decision through the existing `LoggerService` (new `LogType.detection`,
same 500-entry rolling cap already implemented there — nothing new to build
for retention), e.g.:

```
[AttendanceDetection] state=POSSIBLE_ARRIVAL distance=42m accuracy=15m
activity=walking network=workplace confidence=0.86 -> continuing
[AttendanceDetection] DECISION check_in confidence=0.91 estimatedTime=09:58
rationale="first WALKING+inside-radius sample at 09:58, confirmed by soft
dwell at 10:01" evidence={geofence:true, activity:true, network:false,
location:true}
```

This is the concrete answer to "why did OfficeLog check me in/out at this
time" — surfaced today only via the existing in-app log viewer path that
already reads `LoggerService`'s Hive box; no new UI surface was added since
none exists to extend cleanly without a larger UI change out of scope here.

## 10. Android / iOS adapters

`MainActivity.kt` and `AppDelegate.swift` were already thin Flutter/plugin-
registration shells with no custom background logic. Every required native
capability (region monitoring, activity recognition, deferred background
work) is provided by an already correctly implemented, maintained, native-
API-backed Flutter plugin — no bespoke geofencing/activity-recognition/
scheduling logic was hand-written in Kotlin or Swift:

- **Region monitoring** — `native_geofence` (already used): Android
  `GeofencingClient`, iOS `CLLocationManager` region monitoring. Kept as-is;
  the engine now treats its callbacks as *signals*, not commands.
- **Activity recognition** — `flutter_activity_recognition` (newly added):
  Android `ActivityRecognitionClient`, iOS `CMMotionActivityManager`. Isolated
  entirely behind `ActivitySignalSource` (`signal_sources/activity_signal_source.dart`)
  — if the permission is denied, missing, or the plugin throws, the source
  reports itself unavailable and the engine simply drops `ActivityEvidence`
  from the confidence calculation (see §4) rather than failing. iOS's own
  restriction — no Wi-Fi/network signal available to third-party apps — is
  handled the same way (`NetworkEvidence` is Android-only in practice; the
  code path is platform-agnostic, it just never returns a positive signal on
  iOS).
- **On-demand location** — `geolocator` (already used), unchanged accuracy/
  timeout settings.
- **Deferred confirmation re-check** (§6.2) — `workmanager` (newly added):
  Android `WorkManager`, iOS `BGTaskScheduler`. This is the one place a small
  amount of platform-specific *configuration* (not custom logic) was
  required, because `BGTaskScheduler` is enforced by Apple at the OS level:
  - `ios/Runner/Info.plist` declares `BGTaskSchedulerPermittedIdentifiers`
    with the single task identifier this app schedules (`UIBackgroundModes`
    already included `fetch`, which `BGAppRefreshTask` also needs — no
    change there).
  - `ios/Runner/AppDelegate.swift` calls `WorkmanagerPlugin.registerLaunchHandlers()`
    in `didFinishLaunchingWithOptions`, per the plugin's own documented
    requirement for apps using the UIScene lifecycle (this app does — Flutter
    registers plugins during scene connection, which is too late for
    `BGTaskScheduler`'s registration deadline otherwise). This call could not
    be verified against a real Xcode build in this environment (no macOS
    available) — see the PR's validation notes.
  - No equivalent Android manifest changes were needed: `workmanager`'s
    Android implementation merges its own manifest entries automatically,
    same as `native_geofence` already does.

All platform signal sources are wrapped by narrow interfaces in
`signal_sources/` (plus `ConfirmationScheduler` for the §6.2 mechanism), so
the shared engine (`attendance_detection_engine.dart`,
`detection_state_machine.dart`, `confidence_engine.dart`,
`timestamp_estimator.dart`) imports zero platform-specific or plugin-specific
types — swapping any one plugin later touches exactly one adapter file.

## 11. What was preserved unchanged

- `AttendanceRulesConfig` (working days/holidays/requirements) — untouched.
- `AttendanceLog`/`AttendanceSession` shape and Firestore/Hive persistence —
  only additive: `AttendanceSession.autoMetadata` (nullable
  `Map<String,dynamic>`) carries the debug metadata from §9 for automatic
  sessions; manual entries and old records simply have `autoMetadata == null`,
  no migration needed.
- The working-day gate (6am–6pm window, `workingWeekdays` check) and the
  "capture check-in/out times" toggle behavior — preserved verbatim in
  `AutoCheckInService`, now applied to the engine's decision rather than to a
  raw distance check.
- All three UI call sites (`initGeofence`, `stopGeofence`,
  `checkAndLogAttendance`) — unchanged method signatures, so
  `home_screen.dart`, `settings_screen.dart`, `config_onboarding_screen.dart`
  needed no changes beyond the new activity-recognition permission request.

## 12. Testing strategy

The engine (`detection_state_machine.dart`, `confidence_engine.dart`,
`timestamp_estimator.dart`) is pure Dart with no platform channels, so it is
unit-testable without a device — see `test/attendance_detection/`. Tests
cover every scenario enumerated in the task's arrival/departure/reliability
lists that doesn't require an actual OS (drive-past producing no check-in,
walk-in producing a check-in backdated to the walking sample, GPS jitter
in/out/in/out producing neither a duplicate check-in nor check-out, missing
activity/network signals still reaching HIGH confidence, out-of-order/
duplicate/replayed events being idempotent, process-restart resumption via
re-hydrating persisted state, and day-rollover resetting stale state —
including the committed-AT_WORKPLACE-with-a-missed-EXIT case from §7).

`attendance_detection_engine_test.dart` additionally exercises the full
engine (fake signal sources + a fake `ConfirmationScheduler` + a real,
temp-directory-backed Hive instance for persistence, with an injectable
clock so elapsed-time-dependent evidence — soft dwell, sustained absence —
can be tested deterministically) to verify the §6.2 scheduling contract
itself: an in-progress episode schedules a confirmation, and a resolved
decision (or a discarded pass-by episode) cancels it.

Scenarios that require real OS behavior (actual Doze deferral, actual
`BGTaskScheduler`/`ActivityRecognitionClient` delivery latency and timing,
real device reboot) are **not** testable in this environment and are called
out explicitly in the PR description rather than claimed as verified.
