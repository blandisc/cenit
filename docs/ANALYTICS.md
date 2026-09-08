# The analytics layer

Every number Cénit shows about a body is computed on the device by a pure function in
`Packages/CenitAnalytics`. That package depends on `BiometricStreams` and `CenitModels` and nothing
else — no database, no file access, no clock, no network. Hand an engine values, get values back.

This document is the reference for those engines: what each one computes, the actual formula with its
constants, the published method it implements, and where it is honest about its own limits.

---

## The discipline

Four things are required of anything in this layer, and they are the reason the document exists.

**A published method.** No engine invents physiology. Each implements a method that someone published
and that a reader can go check.

**A verifiable citation.** The method's source is named in the engine's own file header, with enough
detail to find it. Where the implementation deviates from the source, the deviation is stated.

**A test.** Most engines carry an *oracle* test: a hand-computed reference value the code must
reproduce. Others carry boundary tests that pin behavior exactly at a threshold.

**Honest hedging.** Where a number is an approximation, a product calibration, or a presentation
device rather than a measurement, the code says so and the copy that shows it must say so too.

That last rule has teeth. Several engines carry a **claims allow-list**: the exact set of sentences
the interface is permitted to say about that engine's output. Adding a fifth sentence to a four-item
allow-list is a change to the science, not to the copy, and it is reviewed as one.

### Three vocabularies that recur

**Product calibration versus published quantity.** Many engines mix both. A threshold taken from a
paper is one thing; a knob chosen because it made a screen read well is another. The code labels
which is which, and this document preserves that labeling. When you see a bounded 0-to-100 score next
to a raw quantity, the raw quantity is usually the load-bearing figure and the score is presentation.

**Skip-and-hold.** When a night has no usable value, engines *hold* the previous state and advance a
staleness counter rather than folding a zero. A missing night must never read as a bad night.

**Own baseline per construct.** Two measurements of nominally the same thing, taken by different
instruments, never share a baseline. This is enforced structurally and is the subject of its own
section below.

---

## What is actually running

Not everything here has a caller. The package is deliberately larger than the app, because engines are
built and proven before the surface that will use them exists. Three tiers:

- **Live.** Called from the app on every refresh: the baselines, the morning verdict, load,
  sleep, zones, the source-fusion layer.
- **Wired but inert.** Complete, tested, and reachable, but the input that would activate them has no
  producer today.
- **Library-only.** Complete and tested, with no caller at all.

The library-only list is worth stating plainly, because an engine's output that no user has ever seen
deserves more scepticism than one that has been in front of people for months. As of this writing the
following have **no reference anywhere outside the package**:

| Engine | What it would do |
| --- | --- |
| `RecoveryScorer` | The nightly resting-pulse estimator, all that survives of the old composite. The one mention outside the package is a comment, not a call. |
| `AnalysisScheduler` | Incremental recompute scheduling. |
| `NocturnalDC` | Nocturnal deceleration capacity by phase-rectified signal averaging. |
| `StrainCeiling` | A recovery-scaled load ceiling. |
| `TrainingHabit` | Your habitual session hour. |
| `StreakMath` | Streak arithmetic. |

One type, the baseline status enumeration, is referenced only by tests and never by production code.

Two cautions on reading that list. First, it is derived from a whole-word search for the type name, so
an engine reached only through type inference can look dead when it is not — most of the element types
in the fuller audit are reachable through a live container. Second, an engine having no caller is not
by itself a defect: several are deliberately staged ahead of the surface that will use them.

---

## Baselines: the thing everything is measured against

Almost no engine compares a value to a population norm. They compare it to **your own rolling
normal**, and `Baselines` is the single implementation of that idea.

### The model

A winsorized exponentially weighted moving average, folded one night at a time. Each metric carries a
configuration with six fields: a plausible range, a noise floor for the dispersion, separate
half-lives for the center and the spread, and a flag for whether the whole thing lives in log space.

Folding one night follows six rules, each shadowing the ones after it:

1. No prior state, and a usable value — seed the center there.
2. No prior state, no usable value — park the center at the midpoint of the plausible range, with
   nothing folded.
3. Missing value — hold everything; only the gap counter advances.
4. Value outside the plausible range, checked in the metric's own units before any log transform —
   same as missing.
5. Beyond the hard-rejection width, **and the baseline is already mature** — the night is *seen*
   (the staleness counter resets) but not folded.
6. Otherwise — winsorize toward the center, then fold.

Rule 5's maturity condition is the subtle one. While a baseline is young the hard gate is
**suspended**, because a badly placed seed would otherwise reject exactly the genuine low nights that
ought to correct it, and the center would sit wrong for weeks.

### The constants

| Constant | Value | What it is |
| --- | --- | --- |
| Winsorization width | 3 dispersions | Tonight is clamped this far from the center before folding. The bounded-influence convention (Huber 1964). |
| Hard-rejection width | 5 dispersions | Past this, a mature baseline sees the night but does not fold it. Compared against the raw dispersion, so roughly 6.3σ in practice. |
| Dispersion-to-sigma bridge | 1.253 | For a normal distribution the mean absolute deviation is σ·√(2/π). An identity of the method, not a knob. |
| Nights to seed | 4 | Below this, nothing compares against the baseline. This is the denominator the calibration copy shows. |
| Nights to trust | 14 | At and above this, the baseline is mature and the young-baseline branches switch off exactly. |
| Staleness threshold | 14 nights | A mature baseline that has not seen a reading in this long is declared stale. |
| Confidence floor | 0.5 | The minimum weight a thin baseline's z-score keeps. |
| Early center half-life | 3 nights | Much faster than the mature half-life, so a bad seed converges in days rather than weeks. |
| Early spread inflation | 1.5× | Keeps the band honestly wide while the dispersion estimate is still worthless. |

Center and spread have **different half-lives on purpose** — 14 and 21 nights respectively for every
shipped metric. The spread is meant to move slower than the center. And the spread reads the
*unclamped* night, so a real shift widens the band instead of hiding inside it.

What is stored as "spread" is a **mean absolute deviation, not a standard deviation**, which is why
every consumer multiplies by 1.253 before treating it as one. The canonical robust alternative — the
scaled median absolute deviation (Rousseeuw and Croux 1993) — is named in the source and explicitly
rejected, because this estimator has to run one night at a time while retaining no history.

The typical range this produces is **not a smallest-worthwhile-change**, and no copy is permitted to
call it one.

### Confidence shrinkage

`Baselines.confidence(nValid:)` returns the fraction of a z-score a consumer should keep, given how
many valid nights the baseline has folded: the floor at or below the seed, 1.0 at or above trust,
linear between. Thin evidence gets pulled toward the center rather than believed — the empirical-Bayes
argument (Efron and Morris 1977).

This matters more than it sounds. Every driver in the recovery composite multiplies its z by this
factor, which is what stops a four-night-old baseline from producing a confident verdict.

### Log domain

Variability metrics are right-skewed, so their baselines live in natural-log space (Plews 2013). The
center is then a geometric mean and the band is multiplicative — a value at one dispersion below
scores exactly −1, symmetrically with one above. The flag travels **inside the baseline state**, not
in the config, so a reader never needs the configuration back to interpret the numbers.

### The seven shipped configurations

| Metric | Range | Dispersion floor | Log |
| --- | --- | --- | --- |
| Variability (`hrv`) | 5–250 ms | 0.08 ln-units, about ±10% | yes |
| Variability, second construct (`sdnn`) | identical to above | | yes |
| Resting heart rate | 30–120 bpm | 2.0 bpm | no |
| Respiration | 4–40 breaths/min | 0.5 | no |
| Skin temperature | 20–42 °C absolute | 0.3 °C | no |
| Sleep efficiency | 0.2–1.0 **as a fraction** | 0.03 | no |
| Sleeping-pulse thirds delta | −30 to +30 bpm | 2.5 bpm | no |

Two entries deserve a note. The second variability configuration is byte-identical to the first but
**keeps its own key deliberately**, because the two measurements it serves come from different
instruments and must never share a baseline — retuning one can then never move the other. And sleep
efficiency is a *fraction*, never a percentage; the importer depends on that scale to avoid a
hundred-fold error.

The thirds-delta configuration is the only one that can go negative, which is why it is never
logarithmic, and its bounds are explicitly product calibration rather than validated physiology.

---

## Autonomic signals

### `HRVAnalyzer` — variability from beat intervals

Two statistics, reproduced exactly as defined by the Task Force of the European Society of Cardiology
and the North American Society of Pacing and Electrophysiology (1996):

```
RMSSD = sqrt( mean( (NN[i+1] − NN[i])² ) )
SDNN  = sample standard deviation of NN, ddof = 1
```

Plus the mean interval and the proportion of successive differences exceeding 50 ms.

**Cleaning runs first**, and the order matters because the root-mean-square is an L2 statistic — one
enormous difference dominates a whole night.

1. **Range filter.** Drop anything outside 300–2000 ms, which is roughly 200 down to 30 beats per
   minute.
2. **Ectopic rejection.** Drop beats deviating more than 20% from a local median over a five-beat
   window. This is the classical rule (Malik et al. 1989).
3. **Minimum count.** Twenty clean intervals before any result is returned at all.

The file states its own deviation plainly: the reference implementation used a published artifact
classifier that models missed and extra beats, which is unavailable on device. The 20% local-median
rule is a simpler, fully deterministic approximation of the same intent, and it does not model beat
insertion.

**The segmented nocturnal path is a different filter, on purpose.** Wrist-derived beats arrive gappy
and non-contiguous, where a five-beat local median is unreliable. That path instead applies a
*pairwise* successive-difference rule: a beat-to-beat change exceeding 20% of the shorter interval is
rejected. The threshold matches the ectopic one by design, but the mechanism is distinct. Crucially it
counts a pair only when the two intervals are genuinely adjacent in time and both lie in the plausible
range — a pair crossing a recording gap is not beat-to-beat and is excluded rather than bridged. The
divisor is the number of **valid pairs**, not n−1, so a night stitched from many short segments is
scored only on its real successive differences.

The timestamp on a segmented interval is **fractional seconds**, deliberately. Truncating to whole
seconds would collapse two beats less than a second apart onto the same tick and silently drop valid
pairs, in a way that varies with heart rate.

The 20% figure was validated against 46 real nights: idle on clean nights, correcting the roughly
seven artifact-flipped directions, with 15% over-rejecting genuine respiratory variation and 25%
performing about the same.

### `NocturnalHRV` and `AutonomicTrend`

The one variability figure the app actually shows is a **direction, not a number**: whether your
nocturnal variability is running above, at, or below your own baseline. It reads real nocturnal
root-mean-square variability, and it deliberately does not come through the cross-source masking layer
described below, because it is already single-construct by construction.

---

## The morning verdict

### `Preparedness` — a categorical answer, never a score

The current morning verdict is a pure, deterministic composition that returns a **category**, not a
number between 0 and 100. It answers one question: push today, or ease off.

Its design is the most heavily argued in the package, and the argument is worth preserving because it
is a negative result.

**All-day variability is out of the vote entirely.** Its weight is zero. The reasoning: even in a
*favourable* published comparison — a short supine morning reading on recent watch hardware against a
reference chest monitor with clinical analysis software — the watch's variability figure ran a mean absolute
percentage error near 29% with a negative bias. And the value actually available from the platform is
a *worse* construct than that: an all-day average, not that morning reading. It survives only as a
displayed read-out.

What remains is what a wrist device measures well:

- **The autonomic axis is resting heart rate** against your own baseline. One signal, the dense and
  reliable one.
- **Sleep is graded** against need and efficiency, not a binary threshold at six hours (Van Dongen
  2003).
- **The illness sentinel requires corroboration.** Temperature and respiration must *both* be elevated
  to vote. A lone temperature rise or a lone breathing rise no longer flags anything, which kills the
  warm-room and the talking false positives (Mishra 2020).

**Consensus is by axis, not by signal.** A single bad night moves several correlated signals at once;
grouping them into three axes — autonomic, sleep, sentinel — means that night casts one vote rather
than three.

Optional inputs all default to no-ops: a true nocturnal resting heart rate substituted through the
*whole* series so the baseline and the day share one construct; a luteal allowance applied to the
scored day **only, never the baseline**, so a normal cyclical shift is not misread as out of range
(Shilaih 2017, Maijala 2019); and dense-night nocturnal variability, which never votes without
resting heart rate present.

One method was considered and **deliberately not implemented**: post-exercise heart-rate recovery.
The literature validates it in a standardized exercise test as a mortality marker (Cole 1999), not as
a free-living daily readiness signal, and the engine declines to stretch it.

The honest limit is stated in the engine's own header: the platform's variability figure is sampled
all day rather than during sleep, and its resting pulse is an awake-sedentary aggregate. This is *your
resting signals against your own norm*, not an overnight measurement, and the copy is forbidden from
claiming otherwise.

### `RecoveryScorer` — what is left of the old composite

This engine used to hold a bounded 0-to-100 composite: five weighted drivers, a logistic, and
three-way colour cuts. **All of that is gone.** The column the score was written to had been null on
every write path for a long time, nothing on screen read it, and the verdict now comes from the
per-axis consensus above, which produces no single number. With no score left to cut, the cuts had
nothing to cut, and two constants kept alive only by their own test are debt rather than a definition.

What survives is one estimator that is defensible on its own: the **nightly resting heart rate**.

It is the minimum over five-minute bin means inside the sleep window, and a bin qualifies only with at
least five samples **and** a mean of at least 25 beats per minute. Without those two gates the minimum
latches onto a sparse dropout bin and fabricates a sub-physiological figure. When no bin qualifies it
returns nothing, which is an honest absence rather than an impossible number.

That estimator has **no caller today either**. It stays because this is where "resting heart rate at
night" is written down once and tested. Before adding a caller, check the nocturnal estimator first:
that one is live, and it estimates the nightly nadir by a more careful method.

The deletion is worth recording as a pattern rather than an incident. A score nobody reads is not
harmless: it keeps a column, a set of constants, a test suite and a paragraph of documentation alive,
and each of those invites a future reader to believe the number means something.

---

## Load

### `StrainScorer`

A bounded logarithmic load score built on published training-impulse methods.

```
HRR   = HRmax − RHR                                     (Karvonen 1957)
%HRR  = clamp((HR − RHR)/HRR × 100, 0, 100)

Edwards TRIMP  = Σ zoneWeight × sampleDurationMin       (Edwards 1993)
   weights by %HRR: ≥90→5, ≥80→4, ≥70→3, ≥60→2, ≥50→1, else 0

Banister TRIMP = Σ durationMin × x × 0.64 × e^(b·x)     (Banister 1991)
   x = %HRR/100;  b = 1.92 male, 1.67 female

score = 21 × ln(TRIMP + 1) / ln(7201)
```

**Why the denominator is 7201.** The top Edwards zone weight is 5. Sustained for 24 hours that is
7200 impulse-minutes — the method's own theoretical daily ceiling. Adding one makes the logarithm of
the ceiling equal the logarithm of the denominator, so the ceiling maps to exactly 21.0. The constant
is derived, not tuned.

**Maximum heart rate** comes from the age formula (Tanaka 2001: 208 − 0.7 × age) unless the user's own
observed history says otherwise. With at least 600 samples the engine takes the interpolated 99.5th
percentile of observed values and uses it *if it exceeds* the age estimate. A separate last-resort
fallback of 220 − age exists and is labeled as such.

**Sample duration is the median plausible gap**, not the first pair. A single early gap must not
inflate the duration applied to every sample of the day. Gaps are counted only in a plausible window,
with a one-second fallback.

**The data gate** admits either 600 samples, or 20 samples spanning at least ten minutes. The sparse
branch never fabricates load: the impulse still integrates honestly over whatever pulse is present, so
a genuinely quiet day scores zero either way.

**The inverse** exists so loads can be added on the linear axis and mapped back once. Because the
forward direction rounds to two decimals, the round trip is exact only to about 0.21% relative —
compare with a relative tolerance, never an absolute epsilon.

**The incremental variant** keeps a running state so a live screen does not re-read 86 000 samples and
re-sort every gap several times a minute. It stays byte-identical to the batch recompute at any hour,
by a specific trick: the sample-duration scalar is factored *out* of both accumulators and applied
once at materialization, so a shifting median re-weights every bucket exactly as the batch would. The
median itself rides a bounded histogram of whole-second gaps, giving an order-statistic lookup that
returns the identical value including the even-count average. Freezing the median early would be
faster and would diverge, so it is deliberately not done.

### `ReadinessEngine` — load balance

Synthesizes established sports-science signals into a readiness level and the drivers behind it:
variability against baseline (Plews 2013, Buchheit 2014), resting-pulse drift, respiratory drift, the
acute-to-chronic workload ratio, and training monotony (Foster 1998).

The ratio uses the **coupled exponentially-weighted form** (Williams et al. 2017) rather than rolling
averages, with decay constants of 2/(N+1) over 7 and 28 days — 0.25 and about 0.069. The replay walks
explicit calendar days, and it distinguishes three states that a rolling mean would conflate: a
missing day holds without advancing coverage, a rest day folds as a genuine zero, and a load day folds
its impulse. It gates on 14 days of coverage, at least 4 active days in the window, and a positive
chronic value.

Monotony is the trailing seven **calendar** days, needing at least four loads and a nonzero spread. A
documented behavior change: it no longer reaches back past a week to gather seven non-missing values.

One nuance worth copying: every signal's displayed figure is the **raw** standardized distance, while
the one that votes is orientation-adjusted and confidence-shrunk. Showing the shrunk number would
misreport the measurement; voting on the raw one would over-trust a thin baseline.

The ratio's treatment is the notable part. The 0.8-to-1.3 band comes from Gabbett (2016), but the
engine treats it as a **load-balance descriptor, not an injury predictor**, and says why: the ratio is
coupled, since the acute window sits inside the chronic one, which inflates the correlation (Lolli
2019), and the metric's statistical properties undercut causal use (Impellizzeri 2020).

### `StrainCeiling` — no live caller

Multiplies a 28-day chronic load by a recovery-derived factor spanning the same 0.8-to-1.3 band. Its
own header is unusually candid: the linear map from recovery onto that band is **not from Gabbett or
anyone** — it is a product calibration, physiologically sensible but unvalidated. It needs at least
14 load-days and returns nothing otherwise.

---

## Sleep

### `SleepStager`

The largest engine in the package, and the most hedged. It finds sleep periods and labels each
30-second epoch light, deep or REM.

**Stage 0** builds the sleep-and-wake spine from motion stillness: a window counts as sleep when at
least 70% of it is below a small movement threshold, runs are broken by long gaps, short runs are
absorbed into their neighbours, and a candidate must exceed 60 minutes.

Acceptance then applies four gates in order: duration; a **16-hour span cap** whose failure **drops**
the run rather than truncating it, because truncating would fabricate a wake time; confirmation
against a resting-pulse band; and an off-wrist backstop rejecting runs more than half covered by
sensor gaps. The backstop disables itself entirely when the stream is naturally sparse, because a
sparse night's ordinary gaps must not read as an absent wrist.

**Stage 1** grids the session into 30-second epochs carrying movement counts, a movement fraction,
mean pulse, pooled intervals and raw respiration. Missing motion coverage yields a movement fraction
of 1.0 — treat as moving, the conservative direction.

**Stage 2** classifies against **session-relative percentile bands**, not absolute thresholds:

```
WAKE  : moving AND (cardiac activation OR no pulse data)
DEEP  : still AND parasympathetic high AND pulse low AND intervals regular
REM   : still AND cardiac activation AND intervals irregular
REM'  : still AND pulse high AND pulse variance high AND no respiration data
else  : LIGHT
```

Missing respiration is treated as "regular", which is a documented bias toward deep.

**Stage 3** median-smooths and re-imposes physiology: REM within the first 15 minutes after onset
becomes light, and deep in the last two-thirds of the night becomes light.

**Wake and sleep detection** uses the Cole-Kripke activity index (Cole et al. 1992), rescaled to
30-second epochs per te Lindert and Van Someren (2013).

**The hedging is explicit and belongs in any surface that shows this data.** The stages are
approximations, not validated against polysomnography, and the file names its own ceiling: published
work puts four-class agreement without electroencephalography at roughly 65-73%. It goes further and
names the weakest link — **the light-versus-deep separation, so deep-minute estimates are the least
reliable output the engine produces.**

The frequency-domain features the reference implementation used are absent on device, so the
parasympathetic-tone signal is the time-domain statistic alone.

### Sleep need and debt

The need is a **fixed published target of 450 minutes**, within the 7-to-9-hour range recommended for
healthy adults (Hirshkowitz et al. 2015). Debt is the sum over the trailing seven nights of the
shortfall, **floored per night**, so one long night does not pay off a short one.

The fixed target replaced a personal trailing mean, and the reason is a good example of a definition
being wrong rather than a value being wrong: against your own average, *any* night below it counts as
debt while nights above never pay it back, so even a nine-hour sleeper with normal variance always
owes sleep. The metric was positive by construction.

### Two regularity engines

**Mid-sleep timing** computes the circular standard deviation of the mid-sleep point over a 14-night
window, requiring at least 7 nights and returning **nothing** below that so the interface can show a
calibration state rather than a fabricated figure.

```
θ = 2π·m/1440
R = |mean(e^{iθ})|
circularSD (min) = √(−2·ln R) · 1440/(2π)
score = round(100 × (1 − min(SD, 120)/120))
```

Two numerical guards matter. Fully dispersed input returns a capped 12 hours. And identical points
return a **clean zero** — the standard library returns R slightly below 1 for identical inputs, which
would otherwise leak a spurious few microseconds of standard deviation.

The weekend shift compares circular medians of weekend and weekday onsets, requiring at least two
nights on each side.

Citations: the mid-sleep point and the social-jetlag convention (Wittmann et al. 2006); regularity's
health associations (Huang and Redline 2019); regularity outpredicting duration for mortality (Windred
et al. 2024); the circular statistics themselves (Mardia and Jupp 2000).

**The regularity index** is the second engine and a different construct: the probability of being in
the same sleep-or-wake state at two instants exactly 24 hours apart, rescaled so anti-phase clamps to
zero (Phillips et al. 2017). An instant counts only when both it *and* its 24-hour partner fall within
a half-day window of some night anchor, so a missing night drops out of the pairing instead of reading
as an all-awake day.

Both engines filter naps through a shared **three-hour threshold**, and the reason is measured: a
nap's midpoint sits near anti-phase to nocturnal mid-sleep, so 13 steady nights plus one two-hour nap
produced a standard deviation of 127 minutes and a score of zero. The threshold is labeled a
product-calibration boundary, not a clinical claim.

For both, **the raw quantity is the load-bearing figure and the 0-to-100 score is presentation only**
— a bounded monotonic remap, never a clinical claim.

### Choosing one sleep source

When several sources write sleep for the same night, summing their stages double-counts and pushes
efficiency to a false 100%. So one source is **chosen, not merged** — mixing stages from two sources
is meaningless, because there is no answer to which stage a given minute was in.

The rule: consider only sources reporting more than zero asleep minutes; prefer platform-native
sources; within the chosen pool take the most asleep minutes; break ties deterministically. The
nonzero gate exists because a source reporting a generic state with zero staged minutes would
otherwise win on priority and knock out a source with real stages.

Time-in-bed is handled separately and *may* be summed, because overlapping it can only lower
efficiency, never invent a favourable one.

---

## Zones and energy

### `HRZones`

Maximum heart rate from the age formula (Tanaka 2001), with an optional manual override, and the five
conventional bands at 50/60/70/80/90 percent of maximum.

Note the deliberate split: **these are the display zones and they are a different model** from the
load math, which uses reserve-based zones. The two coexist on purpose and must not be conflated.

### `Calories`

Three published equations and nothing else, now in their own file.

**Resting energy** uses Harris-Benedict as revised by Roza and Shizgal (1984): basal rate in
kilocalories per day from weight, height and age, divided by 86 400 to reach the per-second rate
everything here works in.

**Active energy** uses Keytel et al. (2005): expenditure from heart rate, weight and age, divided by
251.04 to reach kilocalories per second. Heart rate is clamped to the person's maximum first, because
the equation was fitted inside the exercise range.

**Strength without heart rate** uses the Compendium of Physical Activities (Ainsworth et al. 2011):
mass times metabolic equivalents times hours, at 3.5 equivalents for resistance training at eight to
fifteen reps with varied resistance. That is the moderate entry, not the vigorous one, chosen because
a session logged without pulse carries no measure of effort.

**The third coefficient set is not published, and the file says so.** Both source equations give one
set for men and one for women, and Cénit does not require anyone to declare a sex. The third set is
the **arithmetic mean** of the two published sets. That is an interpolation, not a result: no study
fitted it, and it must never be described by the name of either source equation. It is kept because
the alternatives, forcing a declaration or refusing to estimate, are worse product.

The whole-day path applies a **higher activity gate** than the session path, and the asymmetry is
principled: the active equation is validated for genuine exercise intensities, so applying it across a
sedentary day would extrapolate far outside its fit. Samples below the gate burn the resting rate
instead, and the result is floored at resting metabolism.

> The retroactive workout detector that used to share this file no longer exists. Bout detection from
> pulse and motion was removed with the rest of the device-era path; only the session value type and
> the energy equations survive.

---

## Keeping sources honest

Two engines exist purely to stop different instruments' numbers from contaminating each other.

### `SourceLens`

The problem, stated concretely: one source's daily variability figure is a standard-deviation
construct sampled all day, while the engines were tuned on a beat-difference construct measured during
sleep. These are **different time-domain quantities with no published conversion** (Task Force 1996;
Shaffer and Ginsberg 2017). Mixing them measurably moved a baseline mean from about 49.6 ms
single-source to about 43.8 ms mixed.

So the cross-source columns are **cleared** before the folds see them — and a cleared column reads as
a *missing* night to the skip-and-hold rules, never as a zero.

What survives clearing is instructive. **Duration survives**, because it is comparable across
instruments and honestly feeds short-night confidence. **The stage breakdown does not**, because the
instruments have measured offsets. **The temperature deviation does not**, because each instrument
folds its own absolute baseline, so the stored deltas are not interchangeable.

### `SourceFusion`

Merges days from three partitions with a fixed precedence, and adds four rules worth naming:

- **Loads add in impulse space**, never on the logarithmic axis, and are mapped back once.
- **Sum when disjoint, take the maximum when overlapping.** A logged session overlapping a recorded
  workout is probably the same training. Taking the maximum alone made a run plus a lifting session
  read as just the run.
- **Trained but load unknown holds.** A day with a session but no usable load becomes *nothing*
  rather than zero, so the moving average holds instead of folding a false rest day. A stored zero is
  treated as unknown for the same reason.
- **The synthesis floor.** A day with no base row only gets a synthetic row from the first day that
  has a real one, or within the last 56 days. Without that floor, an imported era with no rest days
  seeds the chronic leg with per-session load instead of a daily dose, producing about four weeks of
  falsely easing readings after an import.

Nights merge per night rather than by timestamp, because the same sleep recorded by two instruments
has different start times and a timestamp dedupe cannot catch it.

---

## Statistics

### `MannWhitney`

The two-sample rank-sum test, used by the single-subject experiment path. The choice is deliberate:
the arms are independent — outcome on tagged days versus untagged — so the paired test does not apply,
and at five to ten observations per arm with right-skewed outcomes a normal-theory test is fragile. A
rank test needs no distributional assumption.

Exact p-values by dynamic programming over the null distribution when there are no ties and the
combined sample is at most 30; otherwise the tie-corrected normal approximation with a continuity
correction. Two-sided only, because the templates carry no directional prior. The reported effect is
the Hodges-Lehmann shift in native units plus the rank-biserial correlation.

Citations: Wilcoxon 1945, Mann and Whitney 1947, Hodges and Lehmann 1963, Lehmann 1975.

### `MultipleComparisons`

Benjamini-Hochberg false-discovery-rate control (1995). The motivation is stated numerically: probing
dozens of behavior-by-outcome pairs at once means a family of 40 pure-noise tests yields about two
"significant" hits by chance.

```
sort ascending, then q(i) = min over k ≥ i of ( p(k) · m / k ), capped at 1
```

The running minimum enforces monotonicity, so the transform preserves the ordering of the raw
p-values. Under the global null this also bounds the family-wise error rate, which is what lets a
noise test assert that the fraction of random seeds producing any hit stays near the level.

### Correlation and comparison

`CorrelationEngine` and `ComparisonEngine` supply the cross-metric relationships and period
comparisons the insight surfaces read. Both feed through the correction above rather than reporting
raw p-values.

The correlation engine reads Pearson's r against the exact two-sided Student-t tail on n − 2 degrees
of freedom (the regularised incomplete beta by Lentz's continued fraction; *Numerical Recipes* §6.4),
and returns nothing below three pairs or at zero variance. `alignByDay` inner-joins two day-keyed
series, `lagged` shifts one of them forward by whole days to probe a delayed effect, and `pairs`
exposes that same pairing so another statistic can run over it. Three additions serve the «Tu
patrón» family below:

- **`spearman`** is Pearson on the midranks of each variable (ties share the mean rank), read
  against the same t tail on n − 2 — the classic t-approximation for ρ (Zar 1972). It is used where
  a series is zero-inflated (day strain is 0 on rest days) or heavy-tailed (steps), where Pearson
  would mostly measure the 0-versus-not contrast.
- **`effectiveN`** is Bartlett's AR(1) shrinkage of n for two autocorrelated series read over the
  same pairs — `n_eff = n · (1 − ρ₁ₓρ₁ᵧ) / (1 + ρ₁ₓρ₁ᵧ)`, each lag-1 autocorrelation truncated at
  0 so a train/rest alternation never buys evidence (Bartlett 1935; Dawdy and Matalas 1964).
  `pValue(r:n:)` reads the t tail on that fractional n. It is still AR(1) only: the raw p stays
  anticonservative on daily series, which is why the family never reads it directly.
  `lag1Autocorrelation` reads the paired values in day order and treats consecutive pairs as
  adjacent even when a day is missing between them: the dependence is measured at the sample's own
  spacing (exact for a regular gap — every other night — approximate for an irregular one), and the
  cross-gap products are kept rather than dropped. That biases ρ₁ DOWN relative to the true
  day-adjacent autocorrelation, which inflates n_eff and understates p: mildly ANTICONSERVATIVE
  within the AR(1) hedge above, not conservative. It is the safer of the two choices only next to
  the alternative of dropping the cross-gap products outright.
- **`spearmanPartial`** with `partialPValue` is the first-order partial Spearman,
  `r_xy·z = (r_xy − r_xz·r_yz) / √((1 − r_xz²)(1 − r_yz²))` on the midranks of x, y and z, read
  against the same t tail on **n − 3** degrees of freedom — one paid for the control (Fisher 1924).
  `triples` is `pairs` with the control read on y's day.
- **`spearmanPartial2`** with `partialPValue2` (FER-480) is the **second-order** partial Spearman —
  TWO controls held fixed at once — obtained by RECURSING the formula above rather than inverting a
  matrix (Fisher 1924's general recursive relation for a partial correlation of any order): partial
  z1 out of x, y and z2 first (three first-order partials on midranks), then partial the RESIDUAL z2
  out of the two survivors — `r_xy·z1 = partial(r_xy, r_xz1, r_yz1)`, `r_xz2·z1 = partial(r_xz2,
  r_xz1, r_z1z2)`, `r_yz2·z1 = partial(r_yz2, r_yz1, r_z1z2)`, `r_xy·z1z2 = partial(r_xy·z1, r_xz2·z1,
  r_yz2·z1)` — read against the t tail on **n − 4** degrees of freedom, one per control. This is
  algebraically the same coefficient a least-squares regression of x's and y's midranks on {z1, z2}
  (with an intercept) would leave in the residuals' correlation; `CorrelationEngineOracleTests`
  cross-checks the two paths agree. `quadruples` is `pairs` with one control read on x's day and the
  other on y's day.

### `WhatMovesItEngine` — «Tu patrón»

The «Tu patrón» block on a metric sheet says with which of the user's *own* daily series the metric
tends to move. It is **direction only** — rises or falls, never a coefficient — and **association
only** — «se mueve con», never a cause. The app layer maps a finding's copy key
(`patron.<relationship>.<rises|falls>`) to its sentence and nothing else.

Every pair is computed in one pass, so the multiplicity control can see all of them:

| Relationship | x → y | Statistic | Lag | Floor | Extra |
| --- | --- | --- | --- | --- | --- |
| `sleep.priorStrain` | strain[D] → sleep duration[D+1] | Spearman, **partial** on strain[D+1] | +1 | 42 | minority floor |
| `sleep.priorNight` | sleep duration[D] → sleep duration[D+1] | Spearman, **partial (2nd order)** on strain[D] and strain[D+1]; **plain Pearson** (FER-483) when that control is degenerate | +1 | 42 | raw n (auto-lag) |
| `strain.efficiency` | sleep efficiency[D] → strain[D] | Spearman | 0 | 56 | minority floor |
| `efficiency.priorStrain` | strain[D] → sleep efficiency[D+1] | Spearman, **partial** on strain[D+1] | +1 | 56 | minority floor |
| `steps.efficiency` | sleep efficiency[D] → steps[D] | Spearman | 0 | 56 | today's partial count excluded |
| `rhr.sleepDuration` | sleep duration[D] → resting HR[D] | Pearson | 0 | 42 | — |
| `rhr.priorStrain` | strain[D] → resting HR[D+1] | Spearman, **partial** on strain[D+1] | +1 | 42 | minority floor |
| `hrv.sleepDuration` | sleep duration[D] → dense-night ln(RMSSD)[D] | Pearson | 0 | 42 | — |
| `hrv.priorStrain` | strain[D] → dense-night ln(RMSSD)[D+1] | Spearman, **partial** on strain[D+1] | +1 | 42 | minority floor |

Day keys are the storage keys — sleep and efficiency by the **waking** day; strain, steps and the
resting pulse by the calendar day — so «strain[D] → sleep[D+1]» is today's load against the night
that follows. Rows after the device's local today are ignored (a UTC «tomorrow» row), and the steps
series also drops today itself, a partial running total.

**`hrv.*` (FER-472).** The two HRV pairs mirror `rhr.sleepDuration`/`rhr.priorStrain` exactly — same
statistic, same lag, same partial — but read a DIFFERENT series: the dense-night RMSSD partition
(`apple_rmssd_night`, produced by `HealthKitBridge.ingestNocturnalHRV` only for nights that clear
`NocturnalHRV`'s density floor — ≥ 60 clean beats and ≥ 30 successive pairs — and keyed by the
**waking** day, the same attribution `AutonomicTrend` uses), NEVER `DailyMetric.avgHrv` (Apple's
all-day SDNN) and never through `SourceLens`, which only ever clears `avgHrv`. RMSSD is right-skewed
(approximately lognormal), so the engine reads it in the natural-log domain — the same transform
`AutonomicTrend` already takes for its geometric-mean baseline — before either Pearson or the
Spearman rank pass, which is unaffected by a monotonic transform either way. Both pairs use the
plain 42-pair floor, not the 56-pair efficiency one: a dense night's own bar (60/30 above) is
already stricter than the wrist's sleep/wake reliability that motivates the higher floor elsewhere.
This is why the FER-438 retirement note below now reads "revived", not "excluded": the block was
never wrong about SDNN being the wrong construct, only about there being no alternative series —
`WhatMovesItTests.testHrvSleepDurationRisesOnLongerNights`/`testHrvPriorStrainFallsAfterHardDays`
pin the revived pairs; most users will not clear the 42-dense-night floor, and the sheet says
«todavía» honestly rather than inventing a direction.

**Citation scope for `hrv.sleepDuration` (FER-484 note, honest gap, not an overclaim).** Zhang 2025
supports the *construct* choice above only: under sleep deprivation RMSSD, not the all-day SDNN
Apple reports, is the parasympathetic marker that moves, which is why this block reads the
dense-night RMSSD partition instead of `avgHrv`. It does not, by itself, establish the *same-night*
dose-response `hrv.sleepDuration` tests: duration[D] against nocturnal RMSSD[D] on that identical
night, lag 0. That direction rests on physiological plausibility instead, namely sleep architecture
and nocturnal vagal tone, where parasympathetic activity rises across a night's stages, so a longer
night gives it more time to act, rather than on a citation that directly measures duration against
same-night RMSSD. The copy stays non-causal («se mueve con»), so the pair itself is not overclaimed,
but the gap between what Zhang 2025 shows and what this pair asserts is real and stays documented
here rather than blurred behind the citation.

**The gate.** Every value in it is a labeled product knob, not a derived constant:

1. **n floor** — 42 paired days (about six weeks, a calendar floor); **56** for the three pairs that
   carry sleep efficiency, because a wrist sleep/wake reliability of about 0.5 attenuates any true r
   by about √0.5, so a visible pattern needs more nights and the block flickers less.
2. **Minority-class floor** — where the zero-inflated strain series enters and has any 0,
   `min(#strain = 0, #strain > 0) ≥ 10`; otherwise seven training days out of 49 could pass a
   «finding» on seven points.
3. **Effective n** — every cross pair reads its p on `effectiveN`; the auto-lag pair does not,
   because under the null the series is white and its own ρ₁ *is* the statistic — shrinking n by it
   would double-count.
4. **Partial on the lag +1 strain pairs** — `sleep.priorStrain`, `efficiency.priorStrain` and
   `rhr.priorStrain` read Spearman's ρ holding fixed the strain of y's own day (z = strain[D+1];
   `spearmanPartial`, p on n_eff − 3). Without it they inherit a calendar artefact: a strain that is
   0 on rest days and never trains two days running has ρ₁ ≈ −0.39 at two sessions a week, so
   whenever y follows the *same* day's strain (r₀) the lag +1 pair reads −r₀·|ρ₁| of it — a longer
   night on training days painted as «shorter the night after». The post-implementation gate's
   fixture (sleep = 420 + 35·W(i) + 8·K(i)) read ρ = −0.28, q = 0.03; the partial reads +0.04. A
   real next-day effect survives the control (+0.78 → +0.75 on the positive fixture). The triples
   need strain on both days, so a D whose next day has no strain leaves that pair.
5. **Second-order partial on the sleep auto-lag** (FER-480) — `sleep.priorNight` sits on BOTH ends of
   the same calendar artefact at once: x = duration[D] is long because D followed a training day, and
   y = duration[D+1] falls on a day that, by the strain series' own ρ₁ ≈ −0.39, is rarely also a
   training day. Holding one side's strain fixed (piece 4 above) is not enough here; it takes strain
   on BOTH days at once — `spearmanPartial2` holding z1 = strain[D] and z2 = strain[D+1] fixed, p on
   n − 4. The CDO's pure-calendar fixture (sleep = 420 + 35·W(i), no real rebound term) read
   r = −0.405, p = 0.0015 before the control — a confident «shorter the night after» that was 100%
   the training calendar; the second-order partial reads r ≈ −0.016, p ≈ 0.91: nothing left. A real
   homeostatic rebound (Borbély 1982 process S), a weekend catch-up, or another schedule driver,
   superposed on the same calendar,
   survives the double control (`WhatMovesItTests.testSleepPriorNightSurvivesTheCalendarWithARealReboundUnderneath`).
5b. **Simple-correlation fallback for a degenerate control** (FER-483, owner decision, reversible):
   piece 5's partial needs strain[D] and strain[D+1] to be ESTIMABLE; someone who does not train has
   no training calendar to hold fixed, and the FER-480 fix was silently hiding their (uncontaminated)
   sleep pattern along with the confound it was built to catch. `sleep.priorNight` now reads strain
   over its own window (the full range its duration series covers) and falls back to the plain
   Pearson auto-lag it used **before** FER-480 only when that control is degenerate:
   `WhatMovesItEngine.controlDegenerates` answers YES when fewer than `WhatMovesItGate.
   effortPresenceFloor` (**3**) days show ANY measurable (> 0) effort, or when the available values
   have (numerically) zero variance. 3 is a floor on the on/off RHYTHM the FER-480 artefact needs
   (≈ 2 sessions/week sustained over six-plus weeks reads ρ₁ ≈ −0.39 in `strain`); one or two isolated
   training days in that same window cannot manufacture a detectable alternation, so that reader is
   functionally the same population as someone who does not train at all. Crucially, this does
   **not** trip on the gray case, someone who trains rarely but on a real, if thin, schedule: a
   sparse-but-real strain series clears the presence floor and has real variance, so it stays on the
   partial path and, if there are not enough QUADRUPLES to clear `minPairs`, is hidden by that
   ordinary floor exactly as before, never silently downgraded to the correlation the calendar could
   still be confounding. The rest of `sleep.priorNight`'s gate (n floor, raw-n p, family control) is
   unchanged either way, and the copy (`patron.sleep.priorNight.*`) does not change: the relationship
   still exists and fires when the pattern is real, on whichever path can see it.
   `WhatMovesItTests.testSleepPriorNightFallsBackToSimpleCorrelationWhenEffortIsAbsent` (no strain data
   at all, the CDO's own rebound fixture reappears at r ≈ −0.9925, the plain pre-FER-480 value) and
   `testSleepPriorNightSparseEffortStaysHiddenNotSimple` (real but sparse effort, still hidden, the
   anti-regression case) pin both sides.
6. **Family control** — the p-values of every testable pair go through Benjamini-Hochberg
   (`MultipleComparisons`); a finding needs **q < 0.05**. Seven tests at α = 0.05 would otherwise
   yield at least one false finding 30% of the time under the null.
7. `|r| ≥ 0.20` is **cosmetic**: below n ≈ 97 the q is the binding bar (|r| ≥ 0.30 at n = 42).

Below the gate the metric has nothing to assert, so the sheet hides the block and the detail says
«todavía»; it never invents a direction. Power is deliberately low (r = 0.30 at n = 42 is about
49%): the gate protects against the false positive, not the false negative.

**Revived, not excluded — `hrv` (FER-472).** The FER-209 block read the daily variability figure
(`avgHrv`) through the source lens that nils it on every Apple row, so it never painted, and Apple's
all-day SDNN is the wrong construct to test sleep/effort against (Zhang 2025: sleep loss moves
RMSSD, not SDNN) — FER-438 retired it rather than test the wrong construct. `hrv.sleepDuration` and
`hrv.priorStrain` (above) revive it on the RIGHT construct instead: the dense nocturnal-RMSSD
partition, never `avgHrv`.

**Excluded, and why.** The science and statistics gates that ran before implementing settled each
of these. **Prior-day strain → strain** — for a strain that is 0 on rest days its
lag-1 autocorrelation is −π/(1 − π) by construction: it described the calendar. **Same-day recovery
→ strain** — the recovery column is nil on every Apple row. **Steps or energy ↔ strain** — circular,
since the load estimator classifies rest by steps and energy. **Stress, the acute-to-chronic ratio,
sleep performance** — composites of series already in the family (double counting). **Sleep stages
and restorative minutes** — they scale with duration, and consumer staging agreement is about
κ ≈ 0.5. **Skin temperature, oxygen saturation, respiration, VO₂max, regularity, latency,
awakenings** — no defensible on-device relationship (no alcohol or altitude data, an intraday curve,
a sparse trait, one number per window, nil columns).

Citations, each verified by the science gate: Kredlow 2015 (acute exercise → total sleep time,
efficiency, wake after onset, slow-wave sleep); Atoui 2021 (efficiency and wake after onset →
next-day activity; activity → shorter total sleep, small); Lambiase 2013; Mead 2019 (day of week
confounds activity — hence «el calendario también pesa»); Borbély 1982 and 2022 (process S);
Dettoni 2012 and Faust 2020 (short or late nights → resting pulse up); Stanley 2013 (parasympathetic
reactivation 24–48 h after hard effort, cited for both `rhr.priorStrain` and `hrv.priorStrain`);
Zhang 2025 (sleep loss moves RMSSD, not the all-day SDNN construct — why `hrv.sleepDuration` reads
the dense nocturnal-RMSSD partition); Zar 1972; Bartlett 1935; Fisher 1924 (both the first- and
the second-order partial, FER-438 / FER-480); Benjamini and Hochberg 1995. Tests: `WhatMovesItTests`
(a positive and a negative fixture per relationship, one fixture per gate piece, the
calendar-artefact fixtures — pure and with a real rebound superposed — the two partial orders exist
for, and the FER-483 fallback pair: no effort at all, and sparse-but-real effort that must stay
hidden) and `CorrelationEngineOracleTests` (including the second-order partial cross-checked against an
independent least-squares residual regression).

---

## Long-horizon estimates

`FitnessAgeEngine` and `VitalityEngine` implement published population models with documented
domain-transfer corrections, and `VO2maxTrend` reports a **trajectory rather than a point**, using
standard robust methods, precisely because a single estimate carries more uncertainty than a direction
does.

The fitness-age engine now **refuses to score outside the age range its source model was fitted on**.
Outside that range it extrapolates, and because the output is clamped, extrapolation would have
produced a confidently wrong verdict rather than an obviously wrong one. Returning nothing is the
honest answer, and it is the same refusal the recovery composite makes at cold start.

Three domain-transfer corrections are documented in that engine, and the third is the one worth
knowing: the per-reading standard error of the source model, divided by the age slope, works out to
roughly ±19 years. The tighter band the interface shows is defensible **only for the age delta**, and
explicitly does not apply to the absolute uptake estimate.

Several rhythm engines are complete and tested but library-only today: nocturnal deceleration capacity
by phase-rectified signal averaging, nocturnal warming and its night-to-night stability, post-session
heart-rate recovery, and a short-scale detrended-fluctuation exponent. Each is labeled experimental in
its own header.

---

## Where a number becomes a word

Four small modules turn a value into something a screen can say. They are pure math and they carry
citations, so they belong here rather than in the design system.

**`MetricLevels`** holds the level cuts, and each is labeled by whether it has literature behind it.
Step thresholds come from Tudor-Locke (2011); sleep duration from Hirshkowitz (2015); resting-pulse
bands from conventional references plus Cooney (2010); the oxygen-saturation and respiration cuts are
the conventional clinical conventions. Recovery, effort and stress levels are **explicitly product
calibration, not peer-reviewed norms**, and are labeled as such.

One naming decision is instructive. The top resting-pulse level is called "high", not "elevated",
because above 80 is still inside the clinical normal range — a large cohort study puts the central 95%
at roughly 50-80 and 53-82 by sex. The word was chosen so the interface does not imply a finding.

**`VitalBands`** decides in-range or out-of-range for a passive tile, and it deliberately uses a
**two-sigma** cut rather than the baseline's own one-sigma typical range, because one sigma would flag
roughly a third of normal nights. It also applies an absolute-plausibility guard outside the personal
band, so an impossible value reads as out of range no matter how wide your personal spread is.

**`MetricFormat`** owns one grammar per metric across every surface, and guards non-finite values to a
dash rather than letting a not-a-number reach a label. **`MetricLevelPhrase`** maps a metric and a
level to a copy key by pure interpolation, returning nothing for pairs outside the contract rather
than falling through to a default.

**`ScoreConfidence`** grades a score's own certainty into three tiers. Its header carries the clearest
statement of the discipline in the package: only one of its thresholds has published physiological
backing, and every other count and duration cut is labeled a product-calibration knob **so the code
never disguises a knob as a derived constant.** The backed one is a staging-plausibility guard —
near-zero deep and REM at high efficiency is physiologically impossible.

---

## What the insight engine deliberately does not probe

Three omissions are documented in the source, and each is a decision rather than an oversight.

**No variability probe for night anomalies.** The available daily figure is an all-day
standard-deviation construct being compared against a configuration tuned for nocturnal
beat-difference variability. The probe was **removed rather than masked**, on the stated reasoning
that masking invites its return.

**No respiration probe yet.** The daily figure is a whole-calendar-day average contaminated by
breathing exercises, and with the configured noise floor a two-sigma trigger fires at about 1.25
breaths per minute — inside measurement noise.

**No same-day anomaly.** Only the most recent *closed* day is probed, never today.

The anomaly probe that does exist requires a **trusted** baseline of at least 14 nights, not merely a
usable one of 4, because at four nights the spread is itself mostly noise.

---

## Citation index

| Source | What it backs |
| --- | --- |
| Task Force ESC/NASPE 1996 | The variability definitions, and the requirement that artifacts be edited before computing them |
| Malik et al. 1989 | The 20% local-median ectopic rejection |
| Plews et al. 2013 | Log-domain variability baselines; variability against personal baseline |
| Shaffer and Ginsberg 2017 | Why two variability constructs are not interchangeable |
| Huber 1964 | The winsorization convention in the baseline fold |
| Efron and Morris 1977 | Shrinking a thin baseline's z toward the center |
| Karvonen 1957 | Percentage of heart-rate reserve |
| Edwards 1993 | The five-zone weighted training impulse |
| Banister 1991 | The exponential training impulse and its sex coefficients |
| Tanaka et al. 2001 | Maximum heart rate from age |
| Gabbett 2016 | The acute-to-chronic band |
| Lolli et al. 2019; Impellizzeri et al. 2020 | Why that ratio is a descriptor, not a predictor |
| Foster 1998 | Training monotony |
| Buchheit 2014 | Resting-pulse drift as a training-status signal |
| Cole et al. 1992; te Lindert and Van Someren 2013 | The activity index and its 30-second rescaling |
| Walch 2019 | The four-class staging ceiling without electroencephalography |
| Hirshkowitz et al. 2015 | The 450-minute sleep target |
| Wittmann et al. 2006 | Mid-sleep point and social jetlag |
| Huang and Redline 2019; Windred et al. 2024 | Regularity's health associations, and regularity over duration |
| Mardia and Jupp 2000 | Circular statistics |
| Phillips et al. 2017 | The regularity index definition |
| Van Dongen et al. 2003 | Graded sleep loss rather than a threshold |
| Mishra et al. 2020 | Requiring corroboration for an illness signal |
| Shilaih 2017; Maijala 2019 | Cyclical shifts in resting pulse and temperature |
| Cole 1999 | Heart-rate recovery, and why it is not used here |
| Keytel et al. 2005 | Energy from heart rate |
| Ainsworth et al. 2011 | Metabolic equivalents for resistance training |
| Roza and Shizgal 1984 | The revised basal-rate equation behind resting energy |
| Wilcoxon 1945; Mann and Whitney 1947; Hodges and Lehmann 1963; Lehmann 1975 | The rank-sum test, its effect size and its approximation |
| Benjamini and Hochberg 1995 | False-discovery-rate control |
| Lomb 1976; Scargle 1982 | The periodogram used for frequency-domain variability, on the uneven series without resampling |
| Cooper 1969 | Solar declination for the day-arc dial |
| Williams et al. 2017 | The coupled exponentially-weighted load ratio and its decay constants |
| Rousseeuw and Croux 1993 | The robust dispersion alternative that is named and deliberately rejected |
| Huber 1964 | Bounded influence, behind the winsorization width |
| Welch 1947; Satterthwaite 1946 | Unequal-variance comparison and its fractional degrees of freedom |
| Cohen 1988 | The pooled standardized effect size |
| Student 1908 | The significance of a correlation |
| Zar 1972 | The t-approximation for Spearman's ρ |
| Bartlett 1935; Dawdy and Matalas 1964 | The effective sample size of two autocorrelated daily series |
| Fisher 1924 | The partial correlation and the degree of freedom it costs |
| Kredlow et al. 2015; Atoui et al. 2021; Lambiase et al. 2013; Mead et al. 2019 | The exercise-sleep and sleep-activity relationships behind «Tu patrón», and the day-of-week confound |
| Borbély 1982; Borbély 2022 | Process S, behind the night-to-night pair |
| Dettoni et al. 2012; Faust et al. 2020; Stanley et al. 2013 | Short nights and hard effort against the next day's resting pulse, and (Stanley) the same for `hrv.priorStrain`'s dense-night RMSSD |
| Zhang 2025 (Front Neurol 16:1556784, doi:10.3389/fneur.2025.1556784) | Why `hrv.sleepDuration`/`hrv.priorStrain` read the dense nocturnal-RMSSD partition, not the all-day SDNN construct (construct only; `hrv.sleepDuration`'s same-night lag-0 direction rests on physiological plausibility, not this citation, see "Citation scope" note in the HRV block) |
| Zourdos et al. 2016; Helms et al. 2016 | Effort-anchored progression, and reducing load only when reps were missed |
| Steele et al. 2017 | Why a habitual high effort-rater must not be frozen out of progression |
| Epley 1985; Brzycki 1993 | The two one-repetition-maximum estimates |
| LeSuer 1997; Reynolds 2006 | Their validity range, and the noise floor it implies |
| Schoenfeld et al. 2017 | The weekly-set lower bound; the upper bound is explicitly a product convention |
| MacDougall 1995; Damas et al. 2015 | The fatigue decay half-life |
| Nes et al. 2011; Kurtze 2008 | Fitness age and its activity index |
| Kaminsky et al. 2015 | The oxygen-uptake reference percentiles |
| Kodama 2009; Cribb et al. 2023; Paluch 2022; Yin 2017; Cappuccio 2010 | The healthspan model's individual hazard terms |
| Hillebrand 2013 | The variability hazard shape, with its endpoint scope flagged |
| Bauer et al. 2006 | Phase-rectified signal averaging, with its clinical cut-offs deliberately not imported |
| Kräuchi et al. 1999 | Distal warming at sleep onset |
| Schyvens 2025; Herzig 2018 | The measured limits of consumer sleep staging |
| Trinder et al. 2001 | The nocturnal pulse fall, and its circadian confound |
| Tudor-Locke 2011; Cooney 2010; Quer 2020 | The step and resting-pulse level cuts, and the wording they force |
| Billman 2013 | Why frequency-domain balance is not claimed as autonomic balance |
| O'Grady 2024 | The measured error that put all-day variability out of the morning vote |
| Ohayon 2017 | The sleep-efficiency floor |
| Gonzales et al. 2023 | The instrument gap between seated and nocturnal resting pulse |

---

## Conventions

**Nothing here is a measurement.** Every output is an approximation of a published method, computed
from consumer-grade sensors, describing trends in one person's own data. There are no clinical claims
and no diagnostic use.

**A missing value is not a zero.** Engines return nothing rather than fabricate, and folds hold rather
than absorb. If you find a code path that substitutes a default for an absent reading, that is a bug.

**A raw quantity outranks its score.** Where an engine returns both, the raw quantity is the figure
with literature behind it and the bounded score is presentation.

**Two constructs never share a baseline.** This is enforced by separate configuration keys, by the
clearing layer, and by tests. It is the single most expensive class of error this layer has produced.

**Changing a constant changes every installed user's history.** Several thresholds are marked in the
source as contract for exactly that reason. Moving one is a science change with a test to update, not
a tuning exercise.
