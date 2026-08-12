%% PAAS NO2 CALIBRATION ANALYSIS
% This script loads NO2 calibration measurement data and applies the
% configured analysis workflow.
%
% The following parameters are loaded from the dataset entry in
% calibration_periods.json:
%   - filename             : calibration data file name
%   - do_phase_correction  : whether to apply phase correction
%   - phase_angle_target   : target phase angle for phase rotation
%   - wavelength           : laser wavelengths used in this dataset
%   - NO2_Cabs             : NO2 absorption cross sections for configured wavelengths
%   - bottle_conc          : NO2 source concentration in ppb
%   - total_flow           : total flow rate in standard units
%   - NO2_flow             : NO2 flow sequence for each measurement point
%   - freq_scan            : frequency scan file used for resonance correction
%   - background           : background time periods
%   - NO2_periods          : measurement time periods
%
% Configuration values that are not present in JSON fall back to hard-coded
% defaults here in the script.

clear; close all; clc;

%% CONFIGURATION
folder       = '/Users/emma/Documents/Instruments/PAAS/PAAS-4L-005/Characterisation/NO2 calibration/data/';
savefolder   = '/Users/emma/Documents/Instruments/PAAS/PAAS-4L-005/Characterisation/NO2 calibration/plots/';
dataset_date = "2026-07-08";

do_frequency_correction      = true; % this was used in NO2 in N2 and air calibration
select_periods_interactively = false; % you can select periods, but adding them to json is broken


%% Load json file
% Get the folder of the currently running script
scriptFolder = fileparts(mfilename('fullpath'));
cd(scriptFolder);

period_file  = 'calibration_periods.json';
db = jsondecode(fileread(period_file));
dataset_key = matlab.lang.makeValidName(dataset_date);
cfg = db.datasets.(dataset_key);

% Load optional config from JSON entry
if isfield(cfg,'do_phase_correction')
    do_phase_correction = cfg.do_phase_correction;
else
    do_phase_correction = true;
end

if isfield(cfg,'phase_angle_target')
    phase_angle_target = cfg.phase_angle_target;
else
    phase_angle_target = 229+34;
end

%% Load calibration data
paas = readtimetable(fullfile(folder,cfg.filename));
LockIn_phase_set = paas.Lockin_Phasing(1);
f_cal = paas.Laser_Frequency(1);

%% Remove points after laser switching
idx_change = find([false; diff(paas.Laser) ~= 0]);
idx_remove = unique([idx_change; idx_change+1; idx_change+2]);
idx_remove(idx_remove>height(paas)) = [];

paas(idx_remove,:) = [];

%% Optional phase correction
if do_phase_correction

    dphi = deg2rad(phase_angle_target - LockIn_phase_set);

    X_new = paas.X.*cos(dphi) - paas.Y.*sin(dphi);
    Y_new = paas.X.*sin(dphi) + paas.Y.*cos(dphi);

    paas.X = X_new;
    paas.Y = Y_new;

end

%% Interactive period picker (optional)
if select_periods_interactively

    figure
    plot(paas.TimeStamp, paas.R, '.-')
    
    ax = gca;
    ax.XLim = [min(paas.TimeStamp) max(paas.TimeStamp)];
    ax.XAxis.TickLabelFormat = 'yyyy-MM-dd HH:mm:ss';
    grid on
    title('Click start/end pairs')

    n_bg   = input('Number of background periods: ');
    n_meas = input('Number of measurement periods: ');

    period_bg  = strings(n_bg,2);
    period_meas = strings(n_meas,2);

    disp('Select BACKGROUND periods')

    ax = gca;  % get axis once
    for i = 1:n_bg
    
        [x,~] = ginput(2);
    
        % Convert using axis limits as reference
        t = datetime(x, 'ConvertFrom','datenum', ...
                     'TimeZone', paas.TimeStamp.TimeZone);
    
        t1 = t(1);
        t2 = t(2);
    
        period_bg(i,:) = [string(t1), string(t2)];
    
    end

    disp('Select MEASUREMENT periods')

    for i = 1:n_meas

        [x,~] = ginput(2);
    
        % Convert using axis limits as reference
        t = datetime(x, 'ConvertFrom','datenum', ...
                     'TimeZone', paas.TimeStamp.TimeZone);
    
        t1 = t(1);
        t2 = t(2);

        period_meas(i,:) = [string(t1),string(t2)];

    end

    % Save to JSON
    new_entry.filename = cfg.filename;
    new_entry.background = period_bg;
    new_entry.NO2_periods = period_meas;

    if isfile(period_file)

        db = jsondecode(fileread(period_file));

    else

        db.datasets = struct();

    end

    dataset_key = matlab.lang.makeValidName(dataset_date);
    db.datasets.(dataset_key) = new_entry;

    fid = fopen(period_file,'w');
    fprintf(fid,'%s',jsonencode(db,'PrettyPrint',true));
    fclose(fid);

    disp("Periods saved to JSON")

end

%% Load periods from JSON

% --- Fix structure if flattened (single period case)
bg = cfg.background;
if iscell(bg) && ischar(bg{1})
    bg = {bg};   % wrap into 1×1 cell containing the pair
end

% BG periods
n = numel(bg);
BG_periods = NaT(n,2);
for i = 1:n
    
    pair = bg{i};
    
    BG_periods(i,1) = datetime(pair{1});
    BG_periods(i,2) = datetime(pair{2});

end

% NO2 periods
n = numel(cfg.NO2_periods);
NO2_periods = NaT(n,2);
for i = 1:n
    
    pair = cfg.NO2_periods{i};
    
    NO2_periods(i,1) = datetime(pair{1});
    NO2_periods(i,2) = datetime(pair{2});

end

%% Split lasers automatically
unique_wl = unique(paas.Laser_WaveLength);
n_laser = numel(unique_wl);

for i = 1:n_laser
    laser_data{i} = paas(paas.Laser_WaveLength==unique_wl(i),:);
end

%% Plot phase angle
figure,
for i = 1:n_laser
    plot(atan2d(laser_data{i}.Y,laser_data{i}.X),laser_data{i}.Babs,'o','Color',wavelength2color(laser_data{i}.Laser_WaveLength(1))); hold on
end
grid on; box on
set(gca,'FontSize',15,'LineWidth',1.5)
xlabel('Phase angle'); ylabel('Uncorrected b_{abs}')


%% Extract background data
for i = 1:n_laser

    T = laser_data{i};

    mask = T.TimeStamp > BG_periods(1,1) & ...
           T.TimeStamp < BG_periods(1,2);

    BG{i} = T(mask,:);

end

%% Extract measurement periods
n_periods = size(NO2_periods,1);

for p = 1:n_periods

    for i = 1:n_laser

        T = laser_data{i};

        mask = T.TimeStamp > NO2_periods(p,1) & ...
               T.TimeStamp < NO2_periods(p,2);

        period_data{i,p} = T(mask,:);

    end

end

%% Compute background corrected complex signal and uncertainty

for i = 1:n_laser

    bg = BG{i};

    % Individual complex samples
    z_bg = bg.X./bg.Power + 1i*bg.Y./bg.Power;

    % Mean background
    BG_complex = mean(z_bg);

    % Standard error of background mean
    BG_sem = std(z_bg) ./ sqrt(length(z_bg));

    for p = 1:n_periods

        T = period_data{i,p};

        % Individual complex samples
        z = T.X./T.Power + 1i*T.Y./T.Power;

        % Mean signal
        S = mean(z);

        % Standard error of signal mean
        S_sem = std(z) ./ sqrt(length(z));

        % Background-corrected complex signal
        Z_corr = S - BG_complex;

        % Magnitude (your current quantity)
        S_corr(i,p) = abs(Z_corr);

        % -------------------------------------------------
        % Uncertainty propagation
        % -------------------------------------------------

        % Uncertainty of corrected complex value
        Z_sem = sqrt(S_sem.^2 + BG_sem.^2);

        % Convert complex uncertainty to magnitude uncertainty
        %
        % For small uncertainties:
        % σ(|Z|) ≈ σ(Z)
        %
        S_corr_std(i,p) = abs(Z_sem);

    end
end

%% Gas properties and quantum yield
NO2_Cabs      = cfg.NO2_Cabs;
wavelength    = cfg.wavelength;
bottle_conc   = cfg.bottle_conc;
total_flow    = cfg.total_flow;
flow_NO2      = cfg.NO2_flow;

T = 273.15+mean(paas.Temperature)+5;     % temperature in K (assuming 5°C higher temperature in the cell)
%T = 273.15 + 20;
p = 1013.25;                             % pressure in mbar
NO2_ppb = flow_NO2./total_flow .* bottle_conc;

% Quantum yield (Troe et al. 2000)
yield = 0.3;


%% Optional frequency correction
if do_frequency_correction

    [C,hFig] = resonance_correction(cfg.freq_scan, f_cal);
    
    for i = 1:n_laser
        S_corr(i,:) = S_corr(i,:) .* C';
    end

% ---- Save figure ----
fname = fullfile(savefolder, ...
    sprintf('Frequency_correction_%s.png', dataset_date));
exportgraphics(hFig, fname, 'Resolution', 300);
end



%% Plot timeseries
figure,
for i = 1:n_laser
    temp = laser_data{1,i};
    %plot(temp.TimeStamp, temp.Babs, '-ok', 'Color',wavelength2color(temp.Laser_WaveLength(1)), 'LineWidth',2, 'DisplayName',[num2str(temp.Laser_WaveLength(1)),' nm, uncorrected']); hold on;
    plot(temp.TimeStamp, temp.X./temp.Power, '-ok', 'Color',wavelength2color(temp.Laser_WaveLength(1)), 'LineWidth',2, 'DisplayName',[num2str(temp.Laser_WaveLength(1)),' nm, corrected']); hold on;
end
grid on
box on
set(gca,'FontSize',15,'LineWidth',1.5)
ylabel('Total signal [m^{-1}]')
legend();
% ---- Save figure ----
fname = fullfile(savefolder, ...
    sprintf('Calibration_timeseries_%s.png', dataset_date));
exportgraphics(gcf, fname, 'Resolution', 300);

%% Plot calibration
figure('Units','centimeters','Position',[5 5 27 13])
tiledlayout(1,2,'TileSpacing','compact','Padding','compact')

% Initialise data dump variable
calibration_data = struct([]);

for i = 1:n_laser
    nexttile
    hold on

    wl = unique_wl(i);
    color = wavelength2color(wl);

    % Calculation of NO2 absorption coefficient 
    b_abs_NO2 = NO2_absorption(T, p, NO2_ppb, NO2_Cabs(wavelength==wl));
    % Correct for quantum yield for 405 nm
    if wl == 405
        b_abs_NO2 = b_abs_NO2 .* (1-yield);
    else
        b_abs_NO2 = b_abs_NO2;
    end

    % Linear regression
    model = fitlm(b_abs_NO2,S_corr(i,:),'linear','intercept',true);

    scatter(b_abs_NO2,S_corr(i,:),45,...
        'MarkerEdgeColor',color,...
        'MarkerFaceColor','w',...
        'LineWidth',1.2)

    x_fit = linspace(0,450e-6,200);

    intercept = model.Coefficients(1,1).Estimate;
    slope     = model.Coefficients(2,1).Estimate;
    slope_SE  = model.Coefficients.SE(2);

    plot(x_fit,slope*x_fit+intercept,...
        'Color',color,...
        'LineWidth',2)

    xlabel('NO_2 absorption coefficient [m^{-1}]')
    ylabel('PA signal [V W^{-1}]')

    legend(sprintf('C_{cell} = %.0f \\pm %.0f Vm W^{-1}',...
        slope,slope_SE),...
        'Location','northwest',...
        'Box','off','fontsize',16)

    title(sprintf('%d nm',wl),...
        'FontWeight','normal')

    grid on
    box on

    ax = gca;
    ax.FontSize = 14;
    ax.LineWidth = 1.4;
    ax.FontName = 'Helvetica';
    ax.GridAlpha = 0.15;
    ax.MinorGridAlpha = 0.08;
    ax.XMinorGrid = 'on';
    ax.YMinorGrid = 'on';
    ax.TickDir = 'out';

    % Save plot data
    calibration_data(i).wavelength = wl;

    % Measured calibration points
    calibration_data(i).b_abs_NO2  = b_abs_NO2;
    calibration_data(i).signal     = S_corr(i,:);
    calibration_data(i).signal_std = S_corr_std(i,:);
    
    % Fit curve
    calibration_data(i).x_fit = x_fit;
    calibration_data(i).y_fit = slope*x_fit + intercept;
    
    % Fit parameters
    calibration_data(i).cell_constant = slope;
    calibration_data(i).cell_constant_SE = slope_SE;
    calibration_data(i).intercept = intercept;

end

sgtitle(sprintf('NO_2 calibration (%s)',dataset_date),...
    'FontSize',14,...
    'FontWeight','normal')

exportgraphics(gcf,...
    fullfile(savefolder,...
    sprintf('Calibration_%s.png',dataset_date)),...
    'Resolution',300)

% Save plot data
save(fullfile(savefolder,...
    sprintf('Calibration_%s.mat',dataset_date)), ...
    'calibration_data')


%% FUNCTIONS
function b_abs_NO2 = NO2_absorption(T, p_mbar, NO2_ppb, NO2_Cabs)
%NO2_ABSORPTION Computes NO2 absorption coefficient in m^-1
%
% INPUTS:
%   T         - Temperature [K]
%   p_mbar    - Pressure [mbar]
%   NO2_ppb   - NO2 concentration [ppb] (can be vector)
%   NO2_Cabs  - Absorption cross section [cm^2 / molecule] (Vandaele)
%
% OUTPUT:
%   b_abs_NO2 - Absorption coefficient [1/m]

    % =========================
    % Physical constants (SI)
    % =========================
    N_a = 6.02214076e23;      % molecules/mol
    R   = 8.31446261815324;   % J/(mol·K)

    % =========================
    % Unit conversions
    % =========================
    p = p_mbar * 100;              % mbar → Pa
    chi_NO2 = NO2_ppb(:) * 1e-9;   % ppb → mole fraction (force column)

    % =========================
    % Convert Vandaele Cabs: cm^2 → m^2
    % =========================
    sigma = NO2_Cabs(:)' * 1e-4;   % [m^2/molecule], row vector

    % =========================
    % Air number density
    % =========================
    n_air = (N_a .* p) ./ (R .* T);   % molecules/m^3

    % =========================
    % NO2 number density
    % =========================
    n_NO2 = n_air .* chi_NO2;         % molecules/m^3

    % =========================
    % Absorption coefficient
    % =========================
    % Outer product: [time × wavelength] if vectors used
    b_abs_NO2 = n_NO2 * sigma;        % 1/m

end

function colorCode = wavelength2color(wavelength, varargin)

  % default arguments
  maxIntensity = 1;
  gammaVal = 0.8;
  colorSpace = 'rgb';

  for iargin=1:2:(nargin-1)
    switch varargin{iargin}
      case 'maxIntensity' 
        maxIntensity = varargin{iargin + 1};
      case 'gammaVal'
        gammaVal = varargin{iargin + 1};
      case 'colorSpace'
        switch varargin{iargin + 1}
          case 'rgb'
            colorSpace = 'rgb';
          case 'hsv'
            colorSpace = 'hsv';
          otherwise
            error('Invalid colorspace defined');
        end
      otherwise
        error('Invalid argument passed');
    end
  end

	function outputVal = adjust(inputVal, factor)

		if (inputVal == 0)
	  	outputVal = 0;
	  else
			outputVal = (inputVal * factor)^gammaVal;
	  end

	end

	if (wavelength >= 380) && (wavelength < 440)
		r = -(wavelength - 440) / (440 - 380);
    g = 0;
    b = 1;
	elseif (wavelength >= 440) && (wavelength < 490)
		r = 0;
 		g = (wavelength - 440) / (490 - 440);
    b = 1;
  elseif (wavelength >= 490) && (wavelength < 510)
  	r = 0;
    g = 1;
    b = -(wavelength - 510) / (510 - 490);
  elseif (wavelength >= 510) && (wavelength < 580)
  	r = (wavelength - 510) / (580 - 510);
    g = 1;
    b = 0;
  elseif (wavelength >= 580) && (wavelength < 645)
    r = 1;
    g = -(wavelength - 645) / (645 - 580);
    b = 0;
  elseif (wavelength >= 645) && (wavelength < 780)
    r = 1;
    g = 0;
    b = 0;
  else
  	r = 0;
    g = 0;
    b = 0;
  end
    
  if (wavelength >= 380) && (wavelength < 420)
  	factor = 0.3 + 0.7 * (wavelength - 380) / (420 - 380);
  elseif (wavelength >=  420) && (wavelength < 700)
    factor = 1;
  elseif (wavelength >= 700) && (wavelength < 780)
  	factor = 0.3 + 0.7 * (780 - wavelength) / (780 - 700);
  else
    factor = 0;
  end

  r = adjust(r, factor);
  g = adjust(g, factor);
  b = adjust(b, factor);

  rgbCode = [r, g, b];

  switch colorSpace
    case 'rgb'
      colorCode = rgbCode;
    case 'hsv'
      colorCode = rgb2hsv(rgbCode);
  end

  colorCode = colorCode * maxIntensity;

end

function [f0_fun,p,f0_arr] = compute_f0(datafolder,scan_files,NO2_fraction)

n_scans = length(scan_files);

f0_arr = zeros(n_scans,1);

for s = 1:n_scans

    load(fullfile(datafolder,scan_files{s}))

    f0_arr(s) = fit_parameters.f0;

end

p = polyfit(NO2_fraction(:),f0_arr,1);

f0_fun = @(x) polyval(p,x);

end

%% New resonance correction function
% Fits a Lorenzian fit to measured resonance frequency measured with N2
function [C,hFig] = resonance_correction(matfile,f_cal)

% Load frequency scan
S = load(matfile);

p     = S.fit_parameters;
f     = S.frequency;
R     = S.R;
f_fit = S.f_fit;
R_fit = S.R_fit;

% Lorentzian
lorentz = @(f) p.offset + ...
    p.amplitude .* ((p.f0./(2*p.Q)).^2) ./ ...
    ((f-p.f0).^2 + (p.f0./(2*p.Q)).^2);

% Correction factor
R_peak = lorentz(p.f0);
R_cal  = lorentz(f_cal);

C = R_peak ./ R_cal;


% ---------------------------------------------------------
% Figure
% ---------------------------------------------------------
hFig = figure( ...
    'Units','centimeters', ...
    'Position',[5 5 14 10], ...
    'Color','w');

hold on

% Raw data
scatter(f,R,40,...
    'MarkerFaceColor',[0.25 0.25 0.25],...
    'MarkerEdgeColor','none')

% Fit
plot(f_fit,R_fit,...
    'k',...
    'LineWidth',2)

% Peak frequency
plot(p.f0,R_peak,...
    'o',...
    'MarkerSize',8,...
    'MarkerFaceColor',[0.1 0.45 0.85],...
    'MarkerEdgeColor','k')

% Calibration frequency
plot(f_cal,R_cal,...
    's',...
    'MarkerSize',8,...
    'MarkerFaceColor',[0.85 0.25 0.25],...
    'MarkerEdgeColor','k')

% Visualize shift
plot([f_cal p.f0],[R_cal R_cal],...
    'Color',[0.5 0.5 0.5],...
    'LineWidth',1.5)

% Vertical guides
xline(f_cal,':',...
    'Color',[0.85 0.25 0.25],...
    'LineWidth',1.5);

xline(p.f0,':',...
    'Color',[0.1 0.45 0.85],...
    'LineWidth',1.5);

% Text box
text(0.03,0.97,...
    sprintf(['f_{cal} = %.1f Hz\n' ...
             'f_{0} = %.1f Hz\n' ...
             '\\Deltaf = %.1f Hz\n' ...
             'Correction = %.4f'], ...
             f_cal,p.f0,p.f0-f_cal,C),...
    'Units','normalized',...
    'VerticalAlignment','top',...
    'FontSize',10,...
    'BackgroundColor','w')

xlabel('Modulation frequency [Hz]')
ylabel('PA signal [V W^{-1}]')

legend({'Measurement','Lorentz fit',...
        'Resonance peak','Calibration frequency'},...
        'Location','best',...
        'Box','off')

grid on
box on

ax = gca;
ax.FontName = 'Helvetica';
ax.FontSize = 12;
ax.LineWidth = 1.2;
ax.TickDir = 'out';
ax.GridAlpha = 0.15;
ax.MinorGridAlpha = 0.08;
ax.XMinorGrid = 'on';
ax.YMinorGrid = 'on';
title(sprintf('Resonance correction (Q = %.1f)',p.Q),...
    'FontWeight','normal')

end

function [C_fun,C_unc] = compute_frequency_correction(datafolder,scan_files)

n_scans = length(scan_files);

df_all = [];

for s = 1:n_scans

    load(fullfile(datafolder,scan_files{s}))

    df_all = [df_all ; (f_fit - fit_parameters.f0)];

end

df_grid = linspace(min(df_all(:)),max(df_all(:)),500);

R_interp = nan(n_scans,length(df_grid));

for s = 1:n_scans

    load(fullfile(datafolder,scan_files{s}))

    df = f_fit - fit_parameters.f0;

    R_norm = R_fit./max(R_fit);

    R_interp(s,:) = interp1(df,R_norm,df_grid,'linear','extrap');

end

R_mean = mean(R_interp,1);
R_std  = std(R_interp,0,1);

C = 1./R_mean;

C_sigma = R_std./(R_mean.^2);

C_fun = @(df) interp1(df_grid,C,df,'linear','extrap');
C_unc = @(df) interp1(df_grid,C_sigma,df,'linear','extrap');

end