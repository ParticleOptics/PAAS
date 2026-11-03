# PAAS data-analysis procedure

This document describes the processing implemented in `run/run_campaign.m`.
It is intended to make the scientific treatment reproducible and to clarify
which corrections come from the instrument configuration.

## Quick start

1. In `run/run_campaign.m`, select:
   - `instrument_SN`
   - `campaign`
   - the absorption calculation method (`corr_method`)
   - the averaging interval (`time_av`)
   - the desired diagnostic plots in `plot_options`
2. Check that the instrument and campaign exist in both configuration files:
   - `config/instrument_config.json` contains scientific settings and is
     intended for version control.
   - `config/local_config.json` contains computer-specific input and output
     paths and must not be committed.
3. Run `run/run_campaign.m` in MATLAB. The script resolves the project root
   automatically, so it can be launched from the editor or another working
   directory.

The principal output is a MATLAB timetable named `TT_statistics`, saved as
`<campaign>_PAAS_statistics_<time_av>h_average.mat` in the configured data
output directory.

## Processing overview

The processing sequence is:

```text
instrument and campaign configuration
                  |
                  v
       import and concatenate CSV files
                  |
                  v
          correct timestamps
                  |
                  v
 phase, cell-constant, attenuation and interlock corrections
                  |
                  v
 identify sample/background relay blocks and calculate absorption
                  |
                  v
     campaign-specific absorption corrections
                  |
                  v
              STP correction
                  |
                  v
  time-averaged statistics, background statistics and AAE screening
                  |
                  v
        diagnostic figures and saved timetable
```

## 1. Configuration

`utilities/get_instrument_config.m` first loads the instrument defaults from
`instrument_config.json`. Campaign-specific entries then override fields with
the same name. Finally, paths are added from `local_config.json`.

The resulting configuration can include:

- relay states defining background and sample measurements;
- the common cell constant and calibration gain;
- wavelength- and period-specific cell-constant overrides;
- fixed power-meter attenuation by wavelength;
- dated attenuation overrides for documented optical configurations;
- a configurable minimum laser-power fraction for quality control;
- phase-angle corrections;
- interlock-failure periods;
- timestamp corrections;
- input and output directories.

This order is important: a dated or wavelength-specific override is applied
after the instrument default.

## 2. Raw-data import

`src/io/load_raw_data.m` imports every CSV file in the configured raw-data
folder, concatenates the tables and sorts the result by `TimeStamp`.

`src/io/import_PAAS.m` validates the number of comma-separated fields in each
record. Isolated malformed or joined rows are omitted through a temporary
validated copy; the original raw files are never modified. A warning reports
the number of omitted rows.

## 3. Time corrections

`src/processing/apply_time_corrections.m` applies the configured corrections
in this order:

1. normalize the timestamps and assign the input time zone;
2. apply index-based `manual_time_shifts` used for documented clock or
   daylight-saving discontinuities;
3. apply `period_time_shifts`, for example after changing the instrument
   computer from local time to UTC;
4. convert the time zone when `apply_timezone_conversion` is enabled;
5. apply a constant offset;
6. apply a linear clock-drift correction.

The function prints the number of affected rows and the applied shifts, then
sorts the data again. Campaign outputs should use the time zone declared in
the configuration; for the current Hyytiälä analysis this is UTC+2.

## 4. Corrections applied before absorption calculation

`src/processing/apply_raw_corrections.m` modifies the raw signals according
to the merged configuration.

### Phase rotation

For configured lasers and periods, the measured complex lock-in signal is
rotated to the target phase:

$$
\Delta\phi=\phi_{\mathrm{target}}-\phi_{\mathrm{lockin}},
$$

$$
X'=X\cos(\Delta\phi)-Y\sin(\Delta\phi),
\qquad
Y'=X\sin(\Delta\phi)+Y\cos(\Delta\phi).
$$

### Cell constant and calibration gain

The configured instrument value is assigned over its validity period.
Wavelength-specific dated overrides are applied afterwards. The calibration
gain is linked to the configured cell-constant treatment.

### Power-meter attenuation

The stored laser-power measurement was calculated using the attenuation in
the raw file. It is rescaled to the fixed attenuation assigned to that
wavelength:

$$
P_{\mathrm{corrected}} = P_{\mathrm{raw}}
\frac{10^{A_{\mathrm{target}}/10}}{10^{A_{\mathrm{raw}}/10}}.
$$

Because the photoacoustic signal is subsequently divided by laser power,
this correction propagates directly into the absorption coefficient. Dated
attenuation overrides are applied relative to the instrument-level target.

### Interlock failures

Laser power is set to `NaN` for documented channel-specific interlock-failure
periods. Those measurements consequently do not enter the absorption result
or its time averages.

### Minimum laser-power filter

When `minimum_laser_power_fraction` is configured, a high-state reference
power is calculated independently for each laser from the configured
`laser_power_reference_percentile`. This avoids treating a sustained
low-power state as normal merely because it contains more than half of the
campaign measurements. The wavelength-specific threshold is

$$
P_{\mathrm{minimum},\lambda}=
f_{\mathrm{minimum}}\,
\operatorname{percentile}_{p}(P_{\lambda}).
$$

Rows below this threshold are assigned `NaN` before the absorption
calculation. This prevents division by near-zero laser power from creating
large positive or negative absorption artefacts. The current Payerne settings
are `minimum_laser_power_fraction = 0.5` and
`laser_power_reference_percentile = 90`; both can be changed in
`instrument_config.json`. The reference power, applied threshold and number
of masked rows are printed for every wavelength when the analysis is run. The corrected
power before filtering is retained as `Power_before_quality_filter` for
diagnostics only. The laser-power panel shows the complete record in grey and
overlays accepted values in wavelength colours.

For Payerne, the sustained 515 nm low-power operation is additionally recorded
as two channel-specific failure periods in `interlock_failure_period`. The
laser recovered briefly on 27 March 2026, so that interval is retained rather
than masking the complete period from March to May.

## 5. Absorption calculation

`src/physics/calculate_b_abs.m` first calculates

$$
f=\frac{G_{\mathrm{calibration}}}{G_{\mathrm{lockin}}}
$$

and converts each lock-in component using

$$
X_c=\frac{X}{P\,C_{\mathrm{cell}}}f,
\qquad
Y_c=\frac{Y}{P\,C_{\mathrm{cell}}}f,
\qquad
R_c=\frac{R}{P\,C_{\mathrm{cell}}}f.
$$

### Relay-block averaging

A physical block is a contiguous period with the configured background or
sample relay state. Blocks are also separated at a backward timestamp or a
data gap longer than five minutes, preventing data from separate logger
periods or files from being averaged together.

For every block and laser, all valid observations of `X_c`, `Y_c` and `R_c`
are averaged. This does not require every acquisition cycle to contain the
same number of rows and therefore tolerates variable block duration and an
occasional missing wavelength record.

The mean background is represented at the midpoint of each background
block. At each sample-block midpoint, the background is obtained by linear
interpolation in time between the surrounding background-block means. The
nearer background therefore receives greater weight. If the sample lies
outside the available background range, the nearest background is used.
Linear interpolation is not allowed when the surrounding backgrounds are
more than `maximum_background_pair_gap_hours` apart. A sample inside such an
outage gap instead uses the temporally nearer endpoint, preventing an
artificial background ramp across days without data.

For the default `corr_method = 3`, the complex corrected signal is

$$
S_{\mathrm{corr}} =
(\overline{X}_{\mathrm{sample}}+i\overline{Y}_{\mathrm{sample}})
-(X_{\mathrm{BG}}(t)+iY_{\mathrm{BG}}(t)),
$$

and the reported absorption signal and diagnostic phase are

$$
b_{\mathrm{abs}}=\operatorname{Re}(S_{\mathrm{corr}}),
\qquad
\alpha=\arg(S_{\mathrm{corr}}).
$$

The interpolation is identical to the mean of the preceding and following
backgrounds when the sample is exactly halfway between them. Differences
from the older calculation are most visible close to zero absorption because
small absolute changes in the estimated background then represent large
relative changes in the net signal.

### Other `corr_method` values

- `1`: subtract background from the lock-in `R` channel;
- `2`: subtract the magnitudes calculated from `X` and `Y`;
- `3`: subtract the complex background and retain its real component
  (current default);
- `4`: subtract the complex background and retain the magnitude.

Changing `corr_method` changes the physical definition of the reported
signal and should therefore be documented with the analysis.

## 6. Standard-temperature correction

`src/physics/correct_to_stp.m` interpolates the measured downstream
temperature to the sample-block times. The acoustic-cell temperature is
estimated as 5 K warmer than the downstream sensor. Assuming atmospheric
pressure equals the reference pressure, the correction is

$$
T_{\mathrm{cell}}=T_{\mathrm{downstream}}+273.15\ \mathrm{K}+5\ \mathrm{K},
$$

$$
b_{\mathrm{abs,STP}}=b_{\mathrm{abs}}
\frac{T_{\mathrm{cell}}}{273.15\ \mathrm{K}}.
$$

This is a temperature-only STP correction; no measured pressure correction
is currently applied.

## 7. Statistics and AAE quality control

`src/statistics/compute_statistics.m` retimes each wavelength independently
to the selected interval and reports:

- mean;
- standard deviation;
- standard error of the mean;
- median;
- 25th and 75th percentiles;
- minimum and maximum.

Background stability is evaluated by
`src/statistics/compute_bg_statistics.m`. For each wavelength it calculates
one mean X and R value for every physical background relay block. It then
calculates the difference between consecutive block means and derives the
mean, standard deviation, RMSE and interquartile range. A difference is set
to missing when the two background records are separated by more than
`maximum_background_pair_gap_hours` (six hours by default). Thus, the last
background before a logger outage is never paired with the first background
after it and cannot inflate the background RMSE.

An absorption value is admitted to the spectral AAE fit only when every
participating wavelength exceeds twice its channel-specific background RMSE:

$$
b_{\mathrm{abs},\lambda}>2\,\mathrm{RMSE}_{\mathrm{BG},\lambda}.
$$

This avoids interpreting background-dominated spectral ratios as aerosol
absorption trends.

## 8. Diagnostic figures

The current run script can create five consolidated figures:

1. instrument diagnostics: laser power, phase angle and STP factor;
2. background behaviour by wavelength;
3. a single-panel diagnostic containing one mean value per physical
   background relay block, with signed `X` as solid lines and magnitude `R`
   as dashed lines in wavelength-specific colours;
4. absorption and AAE at the selected averaging interval;
5. monthly absorption and AAE distributions.

The adopted `corr_method = 3` subtracts the complex background and retains
its real component, so the background threshold used for absorption and AAE
is derived from `X`. The magnitude `R` is plotted only as a phase-insensitive
diagnostic: because it is non-negative, it is not interchangeable with the
signed `X` component close to zero signal.

Open figures are tiled evenly over the primary display. Plotting does not
alter the saved statistics.

## 9. Reproducibility checklist

Before regenerating campaign data:

- confirm the raw-data directory and output paths in `local_config.json`;
- confirm the instrument and campaign selected in `run_campaign.m`;
- review dated phase, cell-constant, attenuation, interlock and time-shift
  periods in `instrument_config.json`;
- check the reported number of imported files and any malformed-row warnings;
- check the printed numbers of sample and background relay blocks;
- inspect the instrument and background diagnostic figures;
- confirm that the saved time zone and averaging interval are correct;
- record any scientific configuration change in the project analysis log.

Raw input files should remain immutable. Scientific changes belong in
`instrument_config.json` or version-controlled MATLAB code; local filesystem
paths belong only in the untracked `local_config.json`.
