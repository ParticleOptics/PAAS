function b_abs = correct_to_stp(b_abs, time, paas, makePlot)

% ---------------------------------------------------------
% Correct PAAS absorption coefficients to STP
%
% INPUT
%   b_abs      : [n_wavelength x n_time]
%   time       : datetime vector corresponding to b_abs
%   paas       : timetable/table containing
%                paas.TimeStamp
%                paas.Temperature   [°C]
%                Temperature measured downstream PAAS cell -> add 5°C
%   makePlot   : true/false
%
% OUTPUT
%   b_abs_stp  : STP corrected absorption coefficients
%
% STP:
%   T0 = 273.15 K
%   P0 = 1013.25 hPa
%
% Assuming pressure remains constant at P0:
%
%   b_abs(STP) = b_abs * T / T0
%
% ---------------------------------------------------------

if nargin < 4
    makePlot = false;
end

T0 = 273.15; % K

% Interpolate temperature onto absorption timestamps
T = interp1( ...
    datenum(paas.TimeStamp), ...
    paas.Temperature, ...
    datenum(time), ...
    'linear', ...
    'extrap');

T = T + 273.15 + 5;   % convert to Kelvin and add 5 K (assumed increase in cell)

% STP correction factor
CF = T ./ T0;

% Apply correction to all wavelengths
b_abs_stp = b_abs .* CF;

% Median change
median_change = median((CF - 1) * 100,'omitnan');

fprintf('\n STP correction changed absorption by a median of %.1f %%\n\n', ...
    median_change);

% ---------------------------------------------------------
% Diagnostic plot
% ---------------------------------------------------------
if makePlot

    hFig = figure( ...
        'Units','centimeters', ...
        'Position',[5 5 24 12]);

    tiledlayout(2,1, ...
        'TileSpacing','compact', ...
        'Padding','compact');

    % ---- Correction factor ----
    nexttile
    plot(time,CF,'LineWidth',1.8)

    ylabel('Correction factor')
    title('STP correction factor')
    grid on

    ax = gca;
    ax.FontSize = 12;
    ax.LineWidth = 1.2;
    ax.TickDir = 'out';

    % ---- Example wavelength comparison ----
    nexttile
    hold on

    semilogy(time,b_abs(1,:), ...
        'LineWidth',1.5)

    semilogy(time,b_abs_stp(1,:), ...
        'LineWidth',1.5,'LineStyle','--')

    ylabel('\beta_{abs}')
    xlabel('Time')

    legend({'Original','STP corrected'}, ...
        'Location','best', ...
        'Box','off')

    grid on

    ax = gca;
    ax.FontSize = 12;
    ax.LineWidth = 1.2;
    ax.TickDir = 'out';

end

end