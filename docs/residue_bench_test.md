# Residue + release bench test (SF2/SF3) — procedure

> ⚠️ This is a **bench coupon test**, not a machine test. There is no piston and no person
> here — only a heated plate and a dough disc. It measures the ONE number the whole design
> hinges on so the cleaning and scraper systems can be designed against real data.

**Goal.** Measure, on a real baked coupon, (a) the **release force** to detach a cooked
flatbread from a candidate food-contact surface, and (b) the **residue** left on that
surface after one bake + clean cycle. These are SeedCell's master variable (ADR-0011), the
food analog of HiveCell's seal drag: they set whether the machine can be **self-cleaning
without chemicals** (SF2), how aggressive the scraper must be (SF3), and whether the
low-adhesion surface + dry-flour boundary layer + self-releasing formula (ADR-0008) actually
work. First-principles estimate spans ~1000× (`scripts/residue.py`) — far too wide to freeze
a design on.

## 1. What we are measuring, and the units that matter
- **Release stress** `σ_rel` [kPa] — peak force to lift/peel the baked disc off the surface,
  divided by contact area. Feeds `RELEASE_KPA` in `actuator_sizing.py` (eject force).
- **Specific residue** `r` [mg/cm² per cycle] — mass left on the surface after one bake and
  one clean pass, per unit contact area. Feeds SF2 (is it below a safe threshold every
  cycle?) and the cross-contamination hazard H2. Also track it as **cumulative** over N
  cycles without a deep clean — the real question is whether it plateaus low or creeps up.

## 2. Bill of materials (~$150–250)
| Item | Purpose | Approx. cost |
|------|---------|-------------:|
| Candidate surface coupons: PTFE-coated, ceramic-coated, bare seasoned stainless | the variable under test | $40 |
| Hot plate / griddle with a set-point to 250 °C | the platen | $50 (or reuse a kitchen griddle) |
| Kitchen scale, 0.01 g resolution | residue mass (before/after) | $25 |
| Force gauge or hanging scale (peak-hold), 0–50 N | release force | $30 |
| Flours per the blend + a fine flour duster | dough + boundary layer | $15 |
| IR thermometer | verify surface temp | $20 |
| Scraper blade + small steam source (kettle) | the clean pass | $20 |

A digital kitchen scale + a fishing scale are valid low-cost substitutes for lab gear.

## 3. Procedure & data recording
1. **Weigh** the clean, dry coupon (`m0`).
2. **Boundary layer:** for "dusted" runs, dust the coupon with a metered dry-flour film;
   for "bare" runs, skip it (the control).
3. **Bake:** deposit a fixed dough charge (per `dosing.py`), press to ~8 mm, hold both-sided
   contact at the test temperature for the cook time from `cook_energy.py`.
4. **Release:** attach the force gauge to the cooled-just-enough disc and record the **peak**
   force to detach it; note whether it self-released before any force (σ_rel ≈ 0).
5. **Clean:** one representative pass — scrape + a few seconds of steam + a wipe (or dry
   heat-hold, to test the reused-heat sterilize step). No chemicals in the baseline.
6. **Weigh** the coupon again (`m1`). Residue mass = `m1 − m0`; `r = (m1 − m0) / area`.
7. **Repeat 3–6** on the SAME coupon for ≥20 cycles without a deep clean, logging `r`
   cumulatively — this is the plateau-vs-creep question that decides SF2.

Data table template:

| run | surface | boundary | hydration | σ_rel (N) | area (cm²) | **σ_rel (kPa)** | Δm (mg) | **r (mg/cm²)** | cum r |
|-----|---------|----------|-----------|-----------|-----------|-----------------|---------|----------------|-------|

Keep everything else fixed within a run so each row isolates one variable (surface,
boundary layer, or hydration).

## 4. Feed the result into the analysis
```sh
python3 scripts/residue.py                    # compare measured r to the first-order bracket
SCRAPER_DRAG_PER_M=<n> flatpak run --command=freecadcmd org.freecad.FreeCAD \
    scripts/actuator_sizing.py                # re-budget eject/scrape force at the measured value
```

## 5. What the number decides (acceptance thresholds)
| Measured residue trend | Consequence |
|------------------------|-------------|
| `r` plateaus low (≲ few µg/cm², cum stable) | **Go:** chemical-free self-cleaning (SF2) via scrape+steam+heat is viable; freeze the low-adhesion surface + flour boundary layer (ADR-0008/0010). |
| `r` moderate but creeping | Add a periodic (not per-cycle) deeper clean; revisit scraper interference/lip count (SF3); still no per-cycle chemical. |
| `r` high / baked-on film | **Rework:** the no-chemical claim fails — either change surface/formula, or add a per-cycle chemical step (and then own hazard H7 + a rinse-verify). Re-open ADR-0010. |

## 6. Test safety
Bench hazards only: a hot plate (burns — gloves, eye protection), steam, and food handling
hygiene (this is a food test — clean gear, fresh flour). There is no piston and no high force
here, only a coupon and a dough disc.
