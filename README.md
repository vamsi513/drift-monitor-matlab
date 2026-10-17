# drift-monitor-matlab

A MATLAB port of the population stability index (PSI) drift monitor from the
`lead-scoring-mlops` project, written to reproduce the Python numbers rather
than to reinvent them.

PSI compares how a feature's distribution is spread across a fixed set of bins
in a reference sample against a later one:

```
PSI = sum over bins of (actual_share - expected_share) * log(actual_share / expected_share)
```

Bin edges come from quantiles of the **reference** only, so the reference is
the fixed yardstick and the comparison sample is scored against it. The
conventional reading, kept here: below 0.10 is `stable`, 0.10 up to 0.25 is
`watch`, 0.25 and above is `shift`.

PSI is a distance between distributions. It says a feature moved. It does not
say the model got worse, and it knows nothing about the label distribution.

## Synthetic data

**All data in this repository is synthetic.** It comes from the generator in
the `lead-scoring-mlops` project, not from real leads or real customers. There
is no personal data here and nothing in `data/` describes a real person or
company.

## Requirements

Base MATLAB only. **No toolboxes are required** — in particular this project
does not depend on Statistics and Machine Learning Toolbox. Where a toolbox
function would have been the obvious choice, the rule is written out in base
MATLAB instead:

| Avoided (Statistics and ML Toolbox) | Used instead |
|---|---|
| `quantile` | `drift.DriftMonitor.quantileLinear` |
| `poissrnd` | Knuth product-of-uniforms, in the test classes |
| `exprnd` | inverse transform, `-mu*log(rand)` |
| `lognrnd` | `exp(mu + sigma*randn)` |
| `randsample` / `datasample` | `discretize` over a cumulative probability vector |

Minimum release **R2020a**, set by `exportgraphics` in `plot_psi.m`
(`arguments` blocks need R2019b, `xline` needs R2018b). CI pins R2024b.

## Running it

### MATLAB Online

1. Open [MATLAB Online](https://matlab.mathworks.com) and sign in.
2. Upload this repository, or clone it from the **MATLAB Drive** file browser.
3. In the Command Window, from the project root:

```matlab
cd drift-monitor-matlab
demo                      % end to end: fit, score, chart to docs/psi.png
parity                    % MATLAB PSI next to the Python values
results = runtests('tests');   % the full suite
disp(table(results))
```

### Locally

Same commands, from the project root, in any MATLAB R2020a or later.

### Parity run on the full tables

`parity` uses the committed 2,000-row fixture by default. To run it against
the full 50,000-row snapshots, export them from the `lead-scoring-mlops`
checkout into `data/full/`, which is gitignored so the large files are never
committed:

```bash
cd ~/lead-scoring-mlops
python - <<'PY'
import pandas as pd
from lead_scoring.config import NUMERIC_FEATURES, CATEGORICAL_FEATURES
cols = list(NUMERIC_FEATURES) + list(CATEGORICAL_FEATURES)
out = '../drift-monitor-matlab/data/full'
import os; os.makedirs(out, exist_ok=True)
pd.read_parquet('data/features/snapshot=2025-01-31')[cols].to_csv(
    f'{out}/reference.csv', index=False, float_format='%.17g')
pd.read_parquet('data/features/snapshot=2025-02-15')[cols].to_csv(
    f'{out}/current.csv', index=False, float_format='%.17g')
PY
```

`parity` picks those up automatically and compares against the per-feature
values published in the `lead-scoring-mlops` README, held in
`data/python_psi_full.csv`. Those published values are rounded to four
decimals, so up to 5e-5 of the difference is rounding alone.

## Project layout

| Path | What it is |
|---|---|
| `+drift/DriftMonitor.m` | The class: `fit` learns bin edges from a reference table, `score` returns a PSI table with a verdict, `fitScore` does both. Static helpers `quantileLinear`, `numericEdges`, `psiNumeric`, `psiCategorical`, `verdictFor` are public so the tests can reach them. |
| `loadSnapshot.m` | Reads a snapshot CSV into a table, keeping text columns as `string`. |
| `demo.m` | End to end on the committed fixture: fit, score, print, chart. |
| `parity.m` | MATLAB PSI next to the Python values, with the largest absolute difference. |
| `plot_psi.m` | Saves a PSI bar chart per feature to `docs/psi.png`, coloured by verdict with both thresholds drawn in. |
| `tests/DriftMonitorTest.m` | Edge cases: empty bins, constant columns, missing values, unseen categories, input validation, quantile rule, and fixture parity. |
| `tests/DetectorTrialsTest.m` | Does it behave like a detector? 100 trials unshifted, 100 at a 25% shift, 100 at 5%. Prints the real counts. |
| `data/fixture_reference.csv` | 2,000 rows sampled from the train snapshot (seed 20250101). |
| `data/fixture_current.csv` | 2,000 rows sampled from the test snapshot (same seed). |
| `data/expected_psi_fixture.csv` | Python PSI for those exact fixture rows, full precision. |
| `data/python_psi_full.csv` | Per-feature PSI for the full tables as published in the `lead-scoring-mlops` README. |
| `.github/workflows/matlab.yml` | Runs the suite on `ubuntu-latest` and uploads JUnit results. |

## Differences from the Python implementation

The binning rule, the epsilon floor (1e-6), the thresholds and the verdict
labels are the same. Four differences are worth knowing about:

1. **The quantile estimator had to be written out by hand.** MATLAB's
   `quantile` places the sorted sample at plotting positions `(i-0.5)/n`,
   whereas `numpy.quantile`'s default `linear` method places it at `0..n-1`
   and interpolates at `(n-1)*p`. These are different estimators and would
   give different bin edges. `quantileLinear` implements the NumPy rule.
   It also keeps the project off Statistics and Machine Learning Toolbox,
   since `quantile` belongs to that toolbox.

2. **Missing values in the reference behave differently.** `quantileLinear`
   drops `NaN` before computing quantiles. The Python code calls
   `np.quantile` directly, which propagates `NaN`, so a reference column with
   any missing value yields all-`NaN` edges and silently falls into the
   degenerate "constant reference" branch. The MATLAB version bins on the
   observed values instead. On these snapshots the point is moot — neither
   table has a missing value — but the behaviour differs if yours do.

3. **Verdict label.** The Python `FeatureDrift.verdict` returns `"shift"` for
   PSI at or above 0.25, and that spelling is kept here so the two agree
   string-for-string. The band is the same thing you may see called "drift".

4. **Trial counts in the detector tests will not match exactly.** The tests
   mirror `tests/test_drift.py` in shape — same distributions, same sample
   size, same trial count — but MATLAB's Mersenne Twister stream is not
   NumPy's PCG64, so these are not the same draws. Expect the same verdict,
   not identical numbers.

The port's arithmetic was checked by transliterating `+drift/DriftMonitor.m`
back into Python and running it against `monitoring/drift.py` on both the full
tables and the committed fixture: identical to the last bit on all 21 features
in both cases. That validates the algorithm, **not** the MATLAB syntax — see
"What has not been run" below.

## Results

<!-- Fill these in from a real MATLAB run. Do not estimate them. -->

| | |
|---|---|
| MATLAB release | `<TO BE FILLED AFTER FIRST RUN>` |
| Tests, total | `<TO BE FILLED AFTER FIRST RUN>` |
| Tests, passed | `<TO BE FILLED AFTER FIRST RUN>` |
| Suite duration | `<TO BE FILLED AFTER FIRST RUN>` |

**Parity, full tables** (largest absolute difference against the published
Python values): `<TO BE FILLED AFTER FIRST RUN>`

**Parity, committed fixture** (largest absolute difference against
`data/expected_psi_fixture.csv`): `<TO BE FILLED AFTER FIRST RUN>`

**Detector trials**, counts printed by the tests themselves:

| Scenario | Flagged | Mean worst PSI | Max worst PSI |
|---|---|---|---|
| Same distribution | `<TO BE FILLED>` / 100 | `<TO BE FILLED>` | `<TO BE FILLED>` |
| Shifted 25% | `<TO BE FILLED>` / 100 | `<TO BE FILLED>` | `<TO BE FILLED>` |
| Shifted 5% | `<TO BE FILLED>` / 100 | `<TO BE FILLED>` | `<TO BE FILLED>` |

For reference, the Python suite reports 0/100, 100/100 and 0/100 for those
three rows. The MATLAB numbers are drawn from a different random stream and
are expected to differ in detail.

## What has not been run

MATLAB is not installed on the machine this was written on, so **no MATLAB
code in this repository has been executed**. Nothing above is reported as a
measured result, and every number that would come from a run is a placeholder.

Specifically unverified:

- That the `.m` files parse and run at all. They were read through twice for
  syntax, undefined names, and toolbox calls, and the identifier list was
  checked against a list of Statistics and ML Toolbox functions, but reading
  is not running.
- Every assertion in the test suite, and the test count.
- The PSI values MATLAB actually produces, and therefore the parity figure.
- That `plot_psi.m` renders, and that `exportgraphics` works headless here.
- That the GitHub Actions workflow succeeds.

What *was* verified, on this machine, without MATLAB:

- The Python side reproduces its own published README values exactly.
- The port's arithmetic, by transliteration (see above): bit-identical on all
  21 features, on both the full tables and the fixture.
- `quantileLinear`'s rule against `numpy.quantile`: bit-identical on every
  numeric column of the reference snapshot.
- The workflow file parses as YAML and every action is pinned to a 40-character
  commit SHA.

## Limitations

- **PSI is not a test.** The 0.10 and 0.25 thresholds are convention, not a
  calibrated significance level. They carry no false-positive rate.
- **It says a feature moved, not that the model got worse.** A feature can
  drift with no effect on predictions, and predictions can degrade with no
  feature drift at all. There is no label here.
- **Bin edges are fixed at fit time.** If the reference is small or oddly
  shaped, the edges inherit that, and every later score is read against them.
- **Quantile binning collapses duplicate edges.** For a feature that is zero
  for most rows, several cut points land on zero and are merged, so that
  feature is scored on fewer than `numBins` bins. This matches the Python
  implementation, but it means the effective resolution varies per feature.
- **A constant reference is a degenerate case.** With fewer than three
  distinct edges there is nothing to bin, and both implementations fall back
  to reporting the fraction of the current sample that left the single
  reference value. That number is on a different scale from a real PSI and
  should not be compared against one.
- **Non-finite values are not handled specially.** `NaN` is dropped, but an
  `Inf` in the reference would flow into the bin edges and could produce a
  duplicate outer edge. Neither snapshot contains one; it is untested.
- **The epsilon floor sets the ceiling.** A bin that empties out entirely
  contributes about 12 per unit of share. That is deliberate — it keeps the
  sum finite — but it caps how extreme a single bin can look.
- **Two samples only.** There is no trend over time, no alerting, and no
  storage of past runs.

## Troubleshooting

Problems actually hit while building this, and the fix for each. Most were
found by reading rather than running, because MATLAB was not available; this
section should grow after the first real run.

- **The CI workflow would not parse as YAML.** The step
  `command: fprintf('MATLAB release: %s\n', ...)` contains a colon followed by
  a space inside the MATLAB string, which YAML reads as a nested mapping and
  rejects with `mapping values are not allowed here`. Fixed by making the
  command a block scalar (`command: |`).

- **`drift.DriftMonitor().fitScore(...)` is not valid MATLAB.** MATLAB does
  not allow indexing into the result of a function call, so chaining a method
  onto a constructor fails. The tests used this pattern in 17 places. Fixed by
  assigning the constructor result to a variable first, via the
  `DriftMonitorTest.scoreTables` helper.

- **A property default must not reference the class being defined.**
  `NumBins (1,1) double = drift.DriftMonitor.DefaultBins` risks failing at
  class-load time. Fixed by using the literal `10` with a comment pointing at
  the constant.

- **Dynamic field and variable access with a `string` scalar.** Struct fields
  and table variables were being addressed as `s.(name)` with `name` a
  `string`. Char is accepted on every release, `string` only on newer ones.
  Fixed by wrapping in `char(...)` at all four sites.

- **`barh` was given mismatched vector orientations**, and bar `CData` was
  being grown one row at a time on a live graphics object. Fixed by
  transposing to `(1:n)'` and assigning the full `n`-by-3 matrix at once.

- **No pandas outside the project venv.** The fixture export and the YAML
  check both needed packages the system `python3` does not have. Run with
  `~/lead-scoring-mlops/.venv/bin/python`, and with `PYTHONDONTWRITEBYTECODE=1`
  so reading that repository leaves no `__pycache__` behind in it.
