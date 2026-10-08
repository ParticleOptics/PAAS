clear; close all;
addpath(genpath(pwd))

instrument_SN = "PAAS_4L_02_005";
campaign      = "Pallas"; % Hyytiala, Hyytiala_Phase2
corr_method   = 3; % method to calculate b_abs

time_av = 6; % in hours

% Plot selection. Each enabled entry creates one consolidated figure.
plot_options = struct( ...
    'instrument_diagnostics', true, ...
    'background', true, ...
    'absorption_aae', true, ...
    'monthly_absorption_aae', true);


%% 1. Load raw data
cfg = get_instrument_config(instrument_SN, campaign);
paas = load_raw_data(cfg);

%% 2. Apply corrections to raw data
paas = apply_time_corrections(paas, cfg); % campaign-specific time corrections
paas = apply_raw_corrections(paas, cfg);  % corrections to raw signal

%% 3. Calculate absorption
remove_start_segments_enabled = true;
if isfield(cfg, 'remove_start_segments_enabled')
    remove_start_segments_enabled = logical(cfg.remove_start_segments_enabled);
end
[b_abs,alpha,time,TimeStart,TimeEnd,time_highres,laser_wavelength] = ...
    calculate_b_abs(paas, cfg.valve_functionality, corr_method, ...
    remove_start_segments_enabled);

%% 4. Possible data corrections
b_abs = apply_corrections(b_abs,time,cfg);
[b_abs, stp_factor] = correct_to_stp(b_abs, time, paas, false);

%% 5. Compute statistics
TT_statistics = compute_statistics(time,b_abs,laser_wavelength, time_av);
[BG, stats]   = compute_bg_statistics(paas, cfg.valve_functionality, time_av);

% Channel-specific AAE validity limits: every absorption coefficient
% entering the spectral fit must exceed twice its background RMSE. Channel
% order is used deliberately because the green channel is recorded as both
% 515 and 520 nm during the campaign.
if numel(stats.X.rmse) ~= numel(laser_wavelength)
    error('Background and absorption channel counts do not match.');
end
aae_threshold = 2*stats.X.rmse(:)*1e6;

%% 5. Plot
if plot_options.instrument_diagnostics
    plot_instrument_diagnostics(paas, b_abs, alpha, time, ...
        laser_wavelength, stp_factor);
end

if plot_options.background
    plot_bg_diff_timeseries_hist(BG.BG_baseline, stats, 'X', ...
        time_av, cfg.outputfolder_plots);
end

if plot_options.absorption_aae
    plot_babs_aae(TT_statistics, laser_wavelength, aae_threshold, ...
        sprintf('%d h means', time_av), 'line');
end

if plot_options.monthly_absorption_aae
    plot_babs_aae(TT_statistics, laser_wavelength, aae_threshold, ...
        'monthly distributions of 6 h means', 'box');
end

% Give every open figure the same amount of space on the primary monitor.
tile_open_figures();

%% 6. Save
save_statistics(TT_statistics, cfg, time_av, campaign);

function tile_open_figures()
% Arrange all visible figures in an evenly sized grid on the primary screen.
figures = findall(groot, 'Type', 'figure', 'Visible', 'on');
if isempty(figures)
    return
end

% Keep the layout order predictable (Figure 1, Figure 2, ...).
[~, order] = sort([figures.Number]);
figures = figures(order);

screen_positions = get(groot, 'MonitorPositions');
screen = screen_positions(1, :);
n_figures = numel(figures);
n_columns = ceil(sqrt(n_figures));
n_rows = ceil(n_figures/n_columns);

outer_margin = 30;
top_reserved = 70;
gap = 12;
tile_width = floor((screen(3) - 2*outer_margin - ...
    (n_columns - 1)*gap)/n_columns);
tile_height = floor((screen(4) - outer_margin - top_reserved - ...
    (n_rows - 1)*gap)/n_rows);

for i = 1:n_figures
    row = floor((i - 1)/n_columns);
    column = mod(i - 1, n_columns);
    x = screen(1) + outer_margin + column*(tile_width + gap);
    y = screen(2) + screen(4) - top_reserved - ...
        (row + 1)*tile_height - row*gap;

    figures(i).WindowState = 'normal';
    figures(i).Units = 'pixels';
    figures(i).Position = [x, y, tile_width, tile_height];
end

drawnow
end
