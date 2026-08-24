clear; close all;
addpath(genpath(pwd))

instrument_SN = "PAAS_4L_02_005";
campaign      = "Hyytiala_Phase2"; % Hyytiala_Phase2
corr_method   = 3; % method to calculate b_abs

time_av = 6; % in hours


%% 1. Load raw data
cfg = get_instrument_config(instrument_SN, campaign);
paas = load_raw_data(cfg);

%% 2. Apply corrections to raw data
paas = apply_time_corrections(paas, cfg); % campaign-specific time corrections
paas = apply_raw_corrections(paas, cfg);  % corrections to raw signal

%% 3. Calculate absorption
[b_abs,alpha,time,TimeStart,TimeEnd,time_highres,laser_wavelength] = ...
    calculate_b_abs(paas, cfg.valve_functionality, corr_method);

%% 4. Possible data corrections
b_abs = apply_corrections(b_abs,time,cfg);
b_abs = correct_to_stp(b_abs, time, paas, true);

%% 5. Compute statistics
TT_statistics = compute_statistics(time,b_abs,laser_wavelength, time_av);
[BG, stats]   = compute_bg_statistics(paas, cfg.valve_functionality, time_av);

%% 5. Plot
% 5.1 Diagnostic plots
plot_phase_angle(b_abs, alpha, laser_wavelength, cfg.outputfolder_plots);
plot_diagnostics(paas,cfg)
plot_bg_diff_timeseries_hist(BG.BG_baseline, stats, 'X', time_av, cfg.outputfolder_plots);

% 5.2 Data plots
plot_timeseries_histogram(TT_statistics, stats, laser_wavelength, time_av);
plot_AAE_timeseries(TT_statistics, laser_wavelength, 0.9);
plot_daily_babs_statistics(time,b_abs,laser_wavelength);

%% 6. Save
save_statistics(TT_statistics, cfg, time_av, campaign);