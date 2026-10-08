function hFig = plot_babs_aae(TT_statistics, laser_wavelength, ...
    b_threshold, statistics_label, plot_style)
%PLOT_BABS_AAE Plot absorption coefficients and their spectral AAE together.

if nargin < 5 || isempty(plot_style)
    plot_style = 'line';
end

time = TT_statistics.Time;
n_laser = numel(laser_wavelength);
B = NaN(n_laser, numel(time));
colors = zeros(n_laser, 3);

for i = 1:n_laser
    wl_text = num2str(laser_wavelength(i));
    B(i, :) = 1e6*TT_statistics.(['mean_' wl_text]).';
    colors(i, :) = wavelength2color(laser_wavelength(i), ...
        'gammaVal', 1, 'maxIntensity', 1, 'colorSpace', 'rgb');
end

if isscalar(b_threshold)
    b_threshold = repmat(b_threshold, n_laser, 1);
else
    b_threshold = b_threshold(:);
end
if numel(b_threshold) ~= n_laser
    error('b_threshold must be scalar or match laser_wavelength.');
end

% AAE from a log-log fit across all valid wavelengths at each time step.
AAE = NaN(1, numel(time));
log_wavelength = log(laser_wavelength(:));
for k = 1:numel(time)
    valid = isfinite(B(:, k)) & B(:, k) > b_threshold;
    if nnz(valid) >= 2
        fit_coefficients = polyfit(log_wavelength(valid), ...
            log(B(valid, k)), 1);
        AAE(k) = -fit_coefficients(1);
    end
end

hFig = figure('Color', 'w', 'Units', 'normalized', ...
    'Position', [0.08 0.1 0.84 0.76], ...
    'Name', ['Absorption and AAE - ' statistics_label]);
layout = tiledlayout(hFig, 2, 1, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax_babs = nexttile(layout);
hold(ax_babs, 'on')
if strcmpi(plot_style, 'box')
    month_start = dateshift(time, 'start', 'month');
    [months, ~, month_index] = unique(month_start);
    offsets = linspace(-0.3, 0.3, n_laser);
    box_width = 0.55/n_laser;
    for i = 1:n_laser
        valid = isfinite(B(i, :));
        boxchart(ax_babs, month_index(valid) + offsets(i), B(i, valid), ...
            'BoxFaceColor', colors(i, :), 'BoxWidth', box_width, ...
            'MarkerStyle', 'none', 'WhiskerLineStyle', 'none', ...
            'DisplayName', sprintf('%.0f nm', laser_wavelength(i)));

        monthly_median = NaN(1, numel(months));
        for month_number = 1:numel(months)
            in_month = month_index == month_number;
            monthly_median(month_number) = median(B(i, in_month), 'omitnan');
        end
        plot(ax_babs, (1:numel(months)) + offsets(i), monthly_median, ...
            '-', 'Color', colors(i, :), 'LineWidth', 1.2, ...
            'HandleVisibility', 'off');
    end
    xlim(ax_babs, [0.5, numel(months) + 0.5])
    xticks(ax_babs, 1:numel(months))
    xticklabels(ax_babs, repmat({''}, 1, numel(months)))
elseif strcmpi(plot_style, 'bar')
    bars = bar(ax_babs, time, B.', 'grouped', 'EdgeColor', 'none');
    for i = 1:n_laser
        bars(i).FaceColor = colors(i, :);
        bars(i).DisplayName = sprintf('%.0f nm', laser_wavelength(i));
    end
else
    for i = 1:n_laser
        plot(ax_babs, time, B(i, :), 'LineWidth', 1.3, ...
            'Color', colors(i, :), ...
            'DisplayName', sprintf('%.0f nm', laser_wavelength(i)));
    end
end
ylabel(ax_babs, 'b_{abs} [Mm^{-1}]')
title(ax_babs, ['Absorption coefficients (' statistics_label ')'])
legend(ax_babs, 'Location', 'best', 'NumColumns', min(4, n_laser))
if strcmpi(plot_style, 'box')
    grid(ax_babs, 'off')
    apply_robust_ylim(ax_babs, B(:));
    box(ax_babs, 'off')
else
    grid(ax_babs, 'on')
    box(ax_babs, 'on')
end

ax_aae = nexttile(layout);
if strcmpi(plot_style, 'box')
    valid = isfinite(AAE);
    boxchart(ax_aae, month_index(valid), AAE(valid), ...
        'BoxFaceColor', [0.25 0.25 0.25], 'MarkerStyle', 'none', ...
        'WhiskerLineStyle', 'none');
    monthly_aae_median = NaN(1, numel(months));
    for month_number = 1:numel(months)
        in_month = month_index == month_number;
        monthly_aae_median(month_number) = median(AAE(in_month), 'omitnan');
    end
    hold(ax_aae, 'on')
    plot(ax_aae, 1:numel(months), monthly_aae_median, 'k-', ...
        'LineWidth', 1.2);
    xlim(ax_aae, [0.5, numel(months) + 0.5])
    xticks(ax_aae, 1:numel(months))
    xticklabels(ax_aae, string(months, 'yyyy-MM'))
    xtickangle(ax_aae, 45)
elseif strcmpi(plot_style, 'bar')
    bar(ax_aae, time, AAE, 0.8, 'FaceColor', [0.25 0.25 0.25], ...
        'EdgeColor', 'none');
else
    plot(ax_aae, time, AAE, 'k-', 'LineWidth', 1.4)
end
ylabel(ax_aae, 'AAE')
xlabel(ax_aae, 'Time')
title(ax_aae, 'AAE, log-log fit where each b_{abs} > 2\sigma background')
if strcmpi(plot_style, 'box')
    grid(ax_aae, 'off')
    apply_robust_ylim(ax_aae, AAE(:));
    box(ax_aae, 'off')
else
    grid(ax_aae, 'on')
    box(ax_aae, 'on')
end

if ~strcmpi(plot_style, 'box')
    linkaxes([ax_babs, ax_aae], 'x')
end

function apply_robust_ylim(ax, values)
% Keep monthly summaries readable without letting isolated extremes set the
% complete vertical scale. Points beyond these limits are intentionally
% clipped from the overview figure.
values = values(isfinite(values));
if isempty(values)
    return
end

limits = prctile(values, [1 99]);
span = diff(limits);
if span <= 0
    span = max(abs(limits(1))*0.1, 1);
end
ylim(ax, limits + 0.05*span*[-1 1]);
end
end
