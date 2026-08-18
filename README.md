# Colorado River Tools

Web apps available at [https://rabutler-usbr.github.io/corivertools/](https://rabutler-usbr.github.io/corivertools/)

## Powell Mass-Balance Calculator

A self-contained water-year mass-balance calculator for Lake Powell. Solve for
any one of Start-of-WY Storage, WY Inflow, WY Release, or End-of-WY Storage,
given the other three plus evaporation. Elevation and storage can be entered
interchangeably (elevation ↔ storage dual entry), and the page includes the
full 2000–2026 historical unregulated-inflow series for context.

This is a static site: one HTML file plus three small JSON data files. No
build step, no server-side code, no dependencies beyond a static file host.

## Repository structure

```
index.html                          the calculator (HTML + CSS + JS, no build step)
data/
  compact_table.json                elevation -> area -> total capacity lookup table
                                     (1-ft increments, source: Reclamation's 2017
                                     Area and Capacity Tables). Static bathymetry
                                     data -- rarely needs updates.
  historical_inflow.json            water-year unregulated inflow, 2000-2026, in
                                     acre-feet. This is the file you'll update as
                                     new WY2026 forecasts come in.
  defaults.json                     default values pre-filled into the calculator
                                     on page load (starting elevation, average
                                     inflow, release, evaporation).
scripts/
  update_inflow.py                  small script that safely updates one year's
                                     value inside historical_inflow.json
.github/workflows/
  update-inflow.yml                 GitHub Action to update the inflow data
                                     (see "Updating the data" below)
```

The calculator loads `data/*.json` at runtime via `fetch()`. Because browsers
block `fetch()` against `file://` URLs, you can't just double-click
`index.html` from disk and expect the data to load -- it needs to be served
over HTTP(S), which GitHub Pages does for you.

## Updating the data

### Updating the WY2026 (or any year's) inflow value manually, by hand

Just edit `data/historical_inflow.json` directly -- change the number under
`"years"` for the year you want, commit, and push. GitHub Pages will
redeploy automatically. This is the simplest option and needs no setup.

### Updating it via GitHub Actions (no local editing needed)

This repo ships with a **manual-trigger** GitHub Action
(`.github/workflows/update-inflow.yml`) that updates the JSON file and pushes
the commit for you -- useful if you want to update the number from your phone,
or hand that job off to someone else without giving them git access.

To run it:

1. On GitHub, go to your repo's **Actions** tab.
2. Click **Update water-year inflow** in the left sidebar.
3. Click **Run workflow** (top right).
4. Fill in:
   - **Water year to update** -- e.g. `2026`
   - **New unregulated inflow value, in acre-feet** -- e.g. `4500000`
   - **Source URL** (optional) -- a link to whatever forecast/report you
     pulled the number from, for your own recordkeeping
5. Click **Run workflow**. Within a few seconds it will update
   `data/historical_inflow.json`, commit the change, and push it -- which
   triggers a GitHub Pages redeploy automatically.

### Automating it on a schedule (e.g. fetch a new forecast every month)

You mentioned the WY2026 value is based on a projection that changes monthly.
The workflow file has a commented-out `schedule:` block and TODO markers for
exactly this -- but since the specific forecast source you use wasn't
pinned down when this was built, it's left for you to wire up rather than
guessing at a URL or format that might not match. To finish it:

1. Decide on your source (e.g. Reclamation's 24-Month Study, a CBRFC
   forecast page, an internal system, etc.) and figure out how to pull a
   single number out of it programmatically (an API call, a PDF page, a
   CSV download -- whatever it is).
2. Write a small script (Python is easiest, since `scripts/update_inflow.py`
   is already Python) that fetches that value.
3. In `.github/workflows/update-inflow.yml`, uncomment the `schedule:` trigger
   and add a step that runs your fetch script, capturing its output, then
   pass that value into `scripts/update_inflow.py --acre-feet ...` in place
   of the manual `github.event.inputs.acre_feet` input.

Local testing of the update script works too, without needing GitHub Actions
at all:

```bash
python3 scripts/update_inflow.py --year 2026 --acre-feet 4500000 --source "https://example.com/your-forecast"
```

## Local development / testing

Because the page fetches JSON files, you need to serve it over HTTP rather
than opening `index.html` directly:

```bash
python3 -m http.server 8000
# then open http://localhost:8000/index.html
```

## Methodology & sources

- Elevation ↔ storage/area conversion uses Reclamation's [Lake Powell 2017 Area and Capacity Tables](https://www.usbr.gov/uc/water/Lake_Powell_Area_Capacity_Table_Report_FINAL.pdf) (Bradley, 2022, Technical Memorandum ENV-2021-98, NGVD29). "Live capacity" is total capacity minus capacity at dead pool (elev. 3,370 ft), consistent with how Reclamation reports storage in its [Weekly Hydrology Summary](https://www.usbr.gov/uc/water/rsvrs/ops/WeeklyHydrologySummary/Weekly_Hydro.pdf) and AOP reports.
- Live capacity at full pool (elev. 3,700 ft) computes to ≈23.31 million AF, consistent with the officially cited 23.314 MAF figure in Reclamation's [2023 AOP slides](https://www.usbr.gov/lc/region/g4000/AOP2023/2023AOP_2022-08-02_Slides.pdf).
- This is a single water-year (Oct 1 – Sep 30) mass balance. It does not account for bank storage change, local/tributary inflow below Powell, or intra-year timing -- only the four terms in the equation the page shows.
- Historical average inflow (9.6 MAF/yr, editable) and default evaporation (260 kAF/yr, editable) are user-specified planning assumptions, not fixed constants -- adjust them for your scenario.
- For current official conditions, see the [Lake Powell reservoir dashboard](https://www.usbr.gov/uc/water/hydrodata/reservoir_data/919/dashboard.html).

## License

No license file is included by default -- add one (e.g. MIT, or public
domain/CC0 if appropriate for a federal work) if you want to make the reuse
terms explicit for a public repo.
