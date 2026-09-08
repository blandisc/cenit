# Cénit — Feature Guide

Cénit is a standalone, fully **offline** health app on **Apple Health** — **no account, no
cloud** — that stores everything on-device in SQLite, imports your Apple Health export, and
computes readiness (preparedness), strain, HRV and sleep locally on your iPhone. There is no
wearable to pair: Cénit reads the samples your **Apple Watch** already saves to Apple Health.
Cénit is the iOS app (`Cenit`); its UI and data layer live under `Cenit/`, on top of the
cross-platform Swift packages.

> **Cénit is not a medical device** — every metric (HR, HRV, readiness, strain, sleep, SpO₂,
> respiration, skin temperature) is an approximation, not a clinical reading, and must not be
> used to diagnose, treat or make health decisions.

Cénit stores its history on-device with [`groue/GRDB.swift`](https://github.com/groue/GRDB.swift)
(SQLite). Older installs may still carry a dormant, legacy data partition from a retired
third-party wearable integration — no longer read, and shown, where visible at all, as
**"On-device"**, never as a band.

---

## At a glance

Cénit is a **four-tab** app, all of it warm-paper **«Instrumento diurno»** (one dominant number,
color only on the datum, hierarchy by space). The tabs are **Hoy** (Today), **Tendencias** (your
body over time), **Entrenar** (Train), and **Ajustes** (Settings):

<!-- GENERATED:ensenanza:at-a-glance START -->
| Tab | What it is |
| --- | --- |
| **Hoy** | The verdict home — today's readiness word (El Ecosistema) and La Matriz of signals. |
| **Tendencias** | Your body over time — the trend of every signal, plus sleep, stress, vitals, body composition and longevity. |
| **Entrenar** | The training planner — plan, routines, a guided live strength session, plus Breathe and Intervals. |
| **Ajustes** | Profile, units, data & backup, illness watch, reminders, support. |
<!-- GENERATED:ensenanza:at-a-glance END -->

There is **no live-connection chrome, no battery indicator, no "pairing" state** anywhere:
everything is computed from Apple Health samples and on-device math. The one place a live heart
rate appears is *inside a guided strength session*, mirrored from a paired **Apple Watch** — not a
band. Most of Cénit works the moment you connect (or import) Apple Health; a few surfaces sharpen
over your first couple of weeks and always say so while they calibrate.

Every metric is an approximation computed locally. Nothing is uploaded.

---

## Hoy — Today

<!-- GENERATED:ensenanza:hoy START -->
The verdict home — today's readiness word (El Ecosistema) and La Matriz of signals.

- **The word of the day** — A reading of how you woke up: in range, go light today, or recover.
  _(Today, at the top, over the orb.)_ · Needs Apple Watch
- **The acta: what your word is made of** — Who votes, how much each vote weighs, and what doesn't
  count. _(Today: tap the ⓘ next to the word.)_ · Needs Apple Watch
- **Night N of 4 and Confidence N of 14** — How many nights until your first word, and until your
  baseline is firm. _(Today, under the word, while it calibrates.)_ · Needs Apple Watch
- **Your first reading (night 4)** — The morning your first word appears, and where it came from.
  _(Today, a one-time card under the hero.)_ · Needs Apple Watch
- **Your baseline is firm (night 14)** — From then on you're compared against 14 of your own nights,
  and the confidence line retires. _(Today, a one-time card under the hero.)_ · Needs Apple Watch
- **The Ecosystem: the orb and its signals** — The orb takes the day's color; tap the background to
  split your signals and see them one by one. _(Today, the hero.)_ · Needs Apple Watch
- **The autonomic axis sheet** — Your resting heart rate against your own baseline; HRV is shown but
  doesn't vote. _(Today: tap the small resting orb.)_ · Needs Apple Watch
- **The guardian: it watches over you** — Skin temperature and respiration against your own pattern.
  They only count when both drift together. _(Today, the «Te vigila» shelf and its orb.)_ · Needs
  Apple Watch
- **The manuals: What decides your day? and Your context** — The full model: who votes, the four
  words, and why context doesn't vote. _(Today: the «?» on each shelf of the Matrix.)_
- **The Matrix: your signals in cells** — Sleep, resting HR, guardian, load, strain, HRV, stress and
  steps, each with its chart. _(Today, below the hero.)_
- **Reading night by night** — Drag across a chart to read each night; the value jumps up to the
  numeral. _(Today, on any chart of the Matrix.)_ · Needs Apple Watch
- **Each signal's sheet** — What it is, how it's computed (with its citation), and where the data
  comes from. _(Today: tap a cell of the Matrix.)_
- **Your pattern: what moves a signal** — A documented tendency, no cause and no coefficient, for
  sleep, strain, efficiency, steps and resting HR. _(Inside the sleep, strain, efficiency, steps or
  resting HR sheet.)_ · Needs Apple Watch
- **A signal's full detail** — Hypnogram, zones, the 90-day calendar and the method. _(Signal sheet
  → «See more».)_
- **The illness notice** — When your body looks strained, a banner names the signals. Optional.
  _(Today, at the very top; enabled in Settings → Watch for illness signals.)_ · Needs Apple Watch
- **The status strips** — Reading your night, sync pending, night not recorded: they always say
  what's going on. _(Today, under the date.)_
- **Pull to sync** — A pull from the top fetches what's new from Apple Health right away. _(Today:
  pull down from the top.)_
- **Today without permission or without a watch** — It says what's missing and how to get it, never
  a made-up number. _(Today, the hero, when there is no reading.)_
<!-- GENERATED:ensenanza:hoy END -->

---

## Tendencias — your body over time

<!-- GENERATED:ensenanza:tendencias START -->
Your body over time — the trend of every signal, plus sleep, stress, vitals, body composition and
longevity.

- **Trends: your body over time** — Every signal across weeks and months, with sleep, stress, vitals
  and longevity. _(The second tab.)_
- **The period selector** — Week, month, three, six, a year or all: every chart re-windows.
  _(Trends, under the title.)_
- **Your 30 mornings** — How you woke up each day of the last month, and how often each signal
  drifted. _(Trends: tap the hero's word.)_ · Needs Apple Watch
- **Rest and load** — Sleep, day strain and stress, each with its own detail. _(Trends, first
  module; tap a column.)_
- **The day map** — Your day's stress crossed with your calendar: which peak matches which event.
  _(Stress detail, further down; it asks for calendar permission there.)_ · Needs Apple Watch
- **Your training load** — Recent versus usual, in a word and a hill; it needs about two weeks of
  recorded strain. _(Trends, second module; the whole card is tappable.)_
- **Your vitals** — HRV, resting HR, oxygen, heart rate, respiration and skin temperature, each with
  its detail. _(Trends, the six-tile module.)_ · Needs Apple Watch
- **Compare signals** — Overlay two to four signals and see whether they move together. Association,
  not cause. _(Trends, at the bottom.)_
- **Explore every signal** — The full catalog, and what correlates with each one. _(Trends, at the
  bottom.)_
- **How you wake up after each sport** — How much each type of workout costs you to recover from.
  _(Trends → Activity, under the hairline.)_ · Needs Apple Watch
- **Longevity: fitness age, body age and VO₂ max** — Estimates, not diagnoses, with what moves them
  and when there are no signals yet. _(Trends, the longevity module.)_ · Needs Apple Watch
- **Agreement between sources** — When two sources report the same day you see both values; they're
  never averaged. _(Under the metric, one line.)_
<!-- GENERATED:ensenanza:tendencias END -->

---

## Entrenar — Train

<!-- GENERATED:ensenanza:entrenar START -->
The training planner — plan, routines, a guided live strength session, plus Breathe and Intervals.

- **Train: the plan that acts** — Today's routine, your week, the live session and the progression
  that goes up on its own. _(The third tab.)_
- **Build your week** — Pick a split, build your routine or import a plan; then Train serves it
  every day. _(Train, when there's no plan yet.)_
- **What Cénit can do** — Six hidden tricks and the gym words: AMRAP, drop, RIR, deload week, rests,
  1RM. _(Train: the «?» in the header.)_
- **Today's routine and Start** — Name, muscles, duration, what goes up today, and the button that
  starts the session. _(Train, at the top.)_
- **Another way: quick, intervals, mobility, breathe** — Four doors besides your routine, no guilt.
  _(Train: the «Otra forma» fold under the button.)_
- **The mosaic: week, dose, raises, body, marks, consistency, history** — Seven tiles that fill with
  your sessions; the ones that can't speak yet stay quiet and say why. _(Train, below the hero.)_
- **Your Plan and the multi-week program** — Assign routines per day, see volume per muscle, and
  turn your week into a program with a deload week. _(Train → Week → Edit.)_
- **Per-exercise progression** — Hit your reps and the routine adds weight; you enable it on each
  exercise's card. _(Routine editor → exercise card.)_
- **Reps in reserve** — How many more reps you could have done; 0 is failure. With this the app
  decides whether you go up. _(Live session, on each set's keypad.)_
- **As many as you can, and drop and continue** — Two set modes: AMRAP counts toward raises and
  records; drop adds volume. _(Session: long-press a set or tap its chip.)_
- **Rest in five forms** — Fixed, rest margin, peak drop, fixed BPM or HR reference; the pulse ones
  need a watch. _(Routine editor: tap a set's rest.)_
- **Exercise library and detail** — Search, filter by muscle or equipment, and for each exercise:
  guide, progress and your history. _(Train → Your Plan → Library.)_
- **Import your AI's plan, and the templates** — Cénit gives you a prompt, you run it in your AI and
  bring the file; or start from a template, even with no equipment. _(Train, first use and Your
  Plan.)_
- **Import your Strong or Hevy history** — One CSV and your past sessions come in, with exercises
  mapped to the catalog. _(Empty history, or Settings → Data sources.)_
- **The live session: Focus, plates and swapping exercises** — Tap the card to enter Focus, tap the
  weight to see which plates to load, and the menu to swap or add an exercise. _(During a session.)_
- **How hard was it?** — One tap when you close, and your session enters your load even without a
  watch. _(When you finish a session.)_
- **The receipt and your tickets** — Every session prints its receipt; the saved ones live in
  History. _(When you finish, and in History → My tickets.)_
- **History and raise cycles** — Your sessions, your month, volume per muscle, and what went up,
  what's waiting and what stalled. _(Train → History and progress.)_
- **Your marks** — Every record, most recent first; a row opens its exercise. _(Train → Marks
  tile.)_
- **Your body: the muscle map** — Which muscles you loaded and which are fresh, crossed with your
  recovery. _(Train → Body tile.)_
- **Breathe and Intervals** — A breathing pacer with haptic pulses, and an interval timer that
  alerts without looking. _(Train → Another way.)_
<!-- GENERATED:ensenanza:entrenar END -->

---

## Ajustes — Settings

<!-- GENERATED:ensenanza:ajustes START -->
Profile, units, data & backup, illness watch, reminders, support.

- **Profile and max HR** — Age, sex, weight and height give your zones and expenditure; max HR is
  estimated (Tanaka) or set by you. _(Settings → Profile.)_
- **Data sources** — Import your Apple Health export, sync, write sessions to Health, record on the
  watch, and see your coverage. _(Settings → Data sources.)_
- **Backup and restore** — Everything to a file, or to an iCloud Drive folder automatically;
  restoring replaces what's on the device. _(Settings → Data sources → Backup.)_
- **Watch for illness signals** — Crosses your wrist temperature with your night pulse to warn you
  early. Approximate, not a diagnosis. _(Settings → Monitoring.)_ · Needs Apple Watch
- **Morning notice and workout reminder** — One reminder a day to read yourself, and one on routine
  days; they never carry your word. _(Settings → Monitoring.)_
- **AFib History, in the Health app** — What it sharpens (nocturnal HRV) and what it costs. Neither
  recommended nor discouraged. _(Settings → Heart rhythm (only when it applies).)_ · Needs Apple
  Watch
- **During a session** — Keep the screen on, a tone when rest ends, and a notice even if you lock
  the phone. _(Settings → During a session.)_
- **Experimental metrics, cycle phase and recalibrate** — New approximate readings, an optional
  experiment, and re-anchoring your baseline from today. _(Settings → Experimental.)_
- **Exercise animations** — Cénit's only network exit, off by default: it downloads animations from
  an external service. _(Settings → Exercise library.)_
- **How Cénit works** — Everything the app teaches, by tab, to come back to whenever you want; and
  see the tips again. _(Settings → More, and the «?» on each tab.)_
- **What's new** — What changed in each version, and where to find it. _(Settings → What's new.)_
- **Appearance and units** — System, light or dark; metric or imperial; °C or °F. _(Settings →
  App.)_
<!-- GENERATED:ensenanza:ajustes END -->

---

## Fuera del iPhone — widgets, Live Activity, Watch

<!-- GENERATED:ensenanza:fuera-del-iphone START -->
Beyond the four tabs — widgets, the Live Activity, Apple Watch, local notices and every gesture with
its button.

- **Widgets: today's routine and your week** — Your routine and your word on the Home Screen; the
  button starts the routine. _(The iPhone widget gallery.)_
- **The session on the Lock Screen** — Set, rest and pulse without unlocking; with a watch, rest can
  end when your pulse drops. _(Lock Screen and Dynamic Island during a session.)_
- **Cénit on Apple Watch** — Your word and your routine on the wrist; log sets with the crown, even
  without the iPhone. _(The watch app; enabled in Settings → Data sources → Record on Apple Watch.)_
  · Needs Apple Watch
- **Local notices** — Morning, workout, rest-end and illness: all optional, all on your iPhone.
  _(Settings → Monitoring and During a session.)_
- **Gestures with their button** — Reorder sets, remove a round, delete a routine: every gesture has
  a tappable path. _(Routine editor and Your Plan.)_
<!-- GENERATED:ensenanza:fuera-del-iphone END -->

---

## Data Sources

**More › Ajustes › Data & sources · the import hub. Everything stays on your device.**

`DataSourcesView.swift` — bring your history in once, then it's yours. It is **Apple Health only**;
there is no third-party CSV import and no live-Bluetooth section. Sections:

- **Import** — **Apple Health Export**: import an `export.zip` (from *Health app → profile → Export
  All Health Data*). Cénit streams and aggregates years of HR, HRV, sleep, SpO₂, steps and body
  composition **locally**, showing record counts and a summary.
- **Apple Health** (live sync) — connect and keep a **two-way sync**: per-stage progress, a coverage
  summary (days + span), a per-metric "what landed" list, and write-back permissions. Two opt-in
  toggles (off by default): **Save workouts to Apple Health** (your strength sessions as workouts +
  an estimated active-energy ring) and **Record on Apple Watch** (only if a watch is paired — real
  HR/calories on the watch).
- **Coverage** — a diagnostic 30-day grid with a legend: **On-device**, **Apple Health only**, **No
  data**, plus a per-source day-count rollup.
- **Backup** — **Export / Import** a single backup file (Import replaces device data and relaunches),
  and an optional **Automatic iCloud backup** to a folder you choose (Back up now / Restore / Turn
  off).

All imports run on-device; nothing is uploaded.

---

## Illness early-warning

Cénit watches for the classic early-illness/strain signature on-device (`IllnessSignalEngine`). It
compares your last ~2 days against a ~28-night baseline (ending 3 days ago) across **resting HR,
HRV, skin-temperature deviation and respiration** — all within-source Apple Health z-scores — behind
a **≥2-signal corroboration gate**, with explicit suppression of confounders (alcohol, hard/late
training, sauna, already-ill, read from your journal). When it raises, a banner appears on **Hoy**:
*"Your body looks strained: … Consider taking it easy,"* naming the concrete signals.

On a clear→raised transition, Cénit also posts a **system notification** (at most once per local
day). The toggle lives in **Ajustes → Salud** and is **opt-in** (off by default — enabling it asks
notification permission). Needs at least 14 nights of baseline. On-device and approximate —
informational only, **not** a diagnosis.

---

## First-run onboarding

The onboarding wizard (`OnboardingWizard.swift`, with `OnboardingActo*.swift` siblings) appears
on first launch and runs once (tracked by an `@AppStorage` preference flag).
It is **not** a form wizard and there is no band to pair: it's a single scene that transforms
**seven times over one continuous particle field**, built entirely on **Apple Health** — no
Bluetooth, no external hardware, no radar. The canvas fills with *your* evidence (density comes from how much
real history landed, never from how long you wait), and color arrives once, as a revelation, when
your verdict tints the field. There is **no global progress indicator, no generic Skip, and no
cross-launch resume** — most acts carry a **Back** control, but the reveal does not, and quitting
before you finish restarts at act 1.

- **Act 1 · Promesa** — the pitch: "all your data, none of the cloud", with a one-line privacy
  promise you can check on the spot (turn on airplane mode). One button: **Empezar**.
- **Act 2 · Permiso** — the single gate of the whole app, and it *is* the weight diagram. It
  requests Apple Health access and, in the same breath, shows how the engine weighs your six
  signals: three votes — the **autonomic axis** (resting HR + night HRV), **sleep**, and the
  **sentinel** (skin temperature + respiration, which counts only when *both* drift the same day)
  — plus one signal that does **not** vote (daytime HRV, shown without color). A pinned **Conectar**
  button, an **Ahora no** off-ramp, and a note that a partial grant is indistinguishable from a
  denied one (HealthKit never reveals read permission).
- **Acts 3–4 · Conexión → Lectura** — one screen that transforms with no cut. First it **reads
  your last 180 days** of Apple Health: a rolling day counter, the current stage named and tinted
  (15 stages), a **2.5 s floor** (reading 180 days can't look like a blink) and a **20 s ceiling**
  (after which a real "enter anyway" exit appears); a failed sync offers **Reintentar**. Then the
  field converges, densifies to the evidence that actually exists, **tints with the verdict**, falls
  silent, and the **verdict word** fades in — borrowed from the same builder that says it on **Hoy**,
  so the two screens can never disagree. The landing has four branches (`OnboardingLanding.swift`,
  decided by what *landed* in the local database, never by the permission):
  - **lectura** — there's a word, with a confidence line ("8 of 14 nights") and a history line; an
    ⓘ points to the Acta.
  - **calibrando** — resting HR arrived but the baseline is young: no word, an honest count
    ("night N of 4").
  - **sinRitmoEnReposo** — signals arrived but *zero* resting HR: the hard ceiling. Without it
    there is no verdict, ever, so the flow doesn't promise one — it offers what works without a
    watch and a door back to Apple Health.
  - **sinDatos** — not a single row (denied read or empty Health, indistinguishable): open Health,
    retry, or enter anyway.
- **Act 5 · Acta** — what the word is made of. The field decomposes into three wells, one per axis,
  as you watch. It states plainly there is **no 0–100 score**, lists the four verdict words with
  their glosses and the three votes, and — inside the axis that leads — shows the actual weights
  (resting HR **1.0**, the spine; night HRV **0.5**, its companion), what doesn't weigh (daytime
  HRV, steps), and what it compares you against.
- **Act 6 · Perfil** — the four data points the engine needs from *you*: **age, sex, weight,
  height**, auto-filled from Apple Health where possible, each field showing its provenance ("From
  Apple Health" / "You set this" / "I set this"). Age alone drives your HR zones (Tanaka,
  208 − 0.7·age); sex, weight and height tune workout burn. The derived **max HR** updates live as
  you edit, and anything you change wins over the autofill. This is the **last common stop of every
  branch** — you pass through it whichever way you arrived.
- **Act 7 · Ciclo** — the close: "and with that, what?" The field circulates between the two
  centers the tab dock shows. It translates each verdict word into what it means for the day,
  renders the **real** tab dock (not a drawing), and — only where a reading can actually exist —
  offers the optional morning-reading notice. No confetti: tomorrow's word might be "take it easy".

**Salida ("Ahora no")** — the off-ramp from Permiso. Not a dead end: it names what you lose, what
still works, and leaves both doors open (reconsider and grant, or enter anyway). It never reappears
on its own.

You can edit your **Profile** any time from **Ajustes**.

---

## App-level gates & notices

Around the four tabs, a few whole-app surfaces:

- **Terms gate** (`TermsGateView.swift`, `Terms.swift`) — a clickwrap over *everything* (before
  onboarding), re-shown if the terms materially change (`currentVersion` "2.0"). The four points you
  accept: Cénit reads from Apple Health on your device (**no separate hardware pairing required**);
  it's offline and local (no account, server or telemetry); it's general wellness, not a medical
  device; and there's no warranty.
- **Restore offer** (`ContentView.swift`, FER-116) — shortly after onboarding, *only* if Apple
  Health is authorized but no data landed, Cénit offers to restore from a **backup file you exported
  yourself** (it has no cloud of its own). "Choose a backup file…" / "Not now".
- **Store failure** (`StoreFailureView.swift`) — if the local database can't open (a wedged
  migration or a corrupt file), an honest full-screen paper state with **Retry** and **Restore from
  backup…**, never an eternally empty dashboard.

---

## Support

**More › Ajustes › About & support · Cénit is free.**

`SupportView.swift` — thinned to essentials: Cénit's identity and version, a short mission ("A health
app built on Apple Health. Everything stays on this device… an independent, experimental project"),
and a single footer disclaimer: **"Not a medical device."**

---

## Privacy & data ownership

- **Offline by design.** Cénit reads the samples your **Apple Watch** and iPhone already save to
  **Apple Health**, on your device. No account, no sync, no cloud, no telemetry, no server — and no
  wearable to pair.
- **On-device storage.** All history (imported and computed) is stored locally in SQLite via GRDB.
- **Your data is yours.** Imports happen once and stay on your device; backups are files *you*
  export (with an optional iCloud folder *you* choose). Nothing is uploaded.
- **One opt-in network exception.** Downloading the exercise-animation library (Ajustes →
  Experimental) is off by default; enabling it fetches media from a CDN and exposes your IP to that
  service. Every other part of Cénit makes zero network calls.
