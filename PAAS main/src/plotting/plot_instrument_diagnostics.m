function hFig = plot_instrument_diagnostics(paas, b_abs, alpha, time, ...
    laser_wavelength, stp_factor)
%PLOT_INSTRUMENT_DIAGNOSTICS Combine the core instrument QC information.

colors = zeros(numel(laser_wavelength), 3);
for i = 1:numel(laser_wavelength)
    colors(i, :) = wavelength2color(laser_wavelength(i), ...
        'gammaVal', 1, 'maxIntensity', 1, 'colorSpace', 'rgb');
end

if istimetable(paas)
    power_time = paas.Properties.RowTimes;
elseif ismember('TimeStamp', paas.Properties.VariableNames)
    power_time = paas.TimeStamp;
elseif ismember('Time', paas.Properties.VariableNames)
    power_time = paas.Time;
else
    error('paas must provide timestamps as row times, TimeStamp, or Time.');
end

hFig = figure('Color', 'w', 'Units', 'normalized', ...
    'Position', [0.05 0.08 0.9 0.82], 'Name', 'Instrument diagnostics');
layout = tiledlayout(hFig, 3, 1, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

% Laser power
ax_power = nexttile(layout);
hold(ax_power, 'on')
for i = 1:numel(laser_wavelength)
    mask = abs(double(paas.Laser_WaveLength) - laser_wavelength(i)) < 1;
    plot(ax_power, power_time(mask), paas.Power(mask), '.', ...
        'Color', colors(i, :), ...
        'DisplayName', sprintf('%.0f nm', laser_wavelength(i)));
end
ylabel(ax_power, 'Laser power')
title(ax_power, 'Laser power')
legend(ax_power, 'Location', 'best', 'NumColumns', ...
    min(4, numel(laser_wavelength)))
grid(ax_power, 'on')
box(ax_power, 'on')

% Phase response. Limit the number of displayed markers without changing
% any calculations, so long campaigns remain responsive.
ax_phase = nexttile(layout);
hold(ax_phase, 'on')
max_points = 20000;
for i = 1:numel(laser_wavelength)
    valid = find(isfinite(alpha(i, :)) & isfinite(b_abs(i, :)));
    if numel(valid) > max_points
        valid = valid(round(linspace(1, numel(valid), max_points)));
    end
    scatter(ax_phase, alpha(i, valid), 1e6*b_abs(i, valid), 8, ...
        'MarkerFaceColor', colors(i, :), 'MarkerEdgeColor', 'none', ...
        'MarkerFaceAlpha', 0.35, ...
        'DisplayName', sprintf('%.0f nm', laser_wavelength(i)));
end
xline(ax_phase, -10, '--k', 'HandleVisibility', 'off');
xline(ax_phase, 10, '--k', 'HandleVisibility', 'off');
xlabel(ax_phase, 'Phase angle, \alpha [degree]')
ylabel(ax_phase, 'b_{abs} [Mm^{-1}]')
title(ax_phase, 'Phase response')
legend(ax_phase, 'Location', 'best', 'NumColumns', ...
    min(4, numel(laser_wavelength)))
grid(ax_phase, 'on')
box(ax_phase, 'on')

% STP correction
ax_stp = nexttile(layout);
plot(ax_stp, time, 100*(stp_factor - 1), 'k-', 'LineWidth', 1.2)
ylabel(ax_stp, 'Correction [%]')
xlabel(ax_stp, 'Time')
title(ax_stp, 'STP correction applied to b_{abs}')
grid(ax_stp, 'on')
box(ax_stp, 'on')

title(layout, 'Instrument diagnostics')
end
