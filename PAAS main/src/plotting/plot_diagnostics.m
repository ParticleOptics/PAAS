function hFig = plot_diagnostics(paas, cfg)
% PLOT_DIAGNOSTICS Plot paas.Power by Laser_WaveLength and powermeter attenuation
%   hFig = plot_diagnostics(paas, cfg)
%   - paas: timetable (or table with TimeStamp/Time) containing 'Power' and 'Laser_WaveLength'
%           and powermeter attenuation column 'Powermeter_Attenuation' or per-wavelength attn cols.
%   - cfg: struct with fields:
%         .Powermeter_Attenuation_soll_wl  (struct with fields '405','473',...)
%         .Powermeter_Attenuation_period   (1x2 datetime/strings) OPTIONAL
%
% No file saving performed.

if nargin < 2, cfg = struct(); end

% Ensure timetable
if ~istimetable(paas)
    if ismember('TimeStamp', paas.Properties.VariableNames)
        paas = table2timetable(paas, 'RowTimes', paas.TimeStamp);
    elseif ismember('Time', paas.Properties.VariableNames)
        paas = table2timetable(paas, 'RowTimes', paas.Time);
    else
        error('paas must be a timetable or table with Time/TimeStamp variable.');
    end
end

% Validate required vars
if ~ismember('Power', paas.Properties.VariableNames) || ~ismember('Laser_WaveLength', paas.Properties.VariableNames)
    error('paas must contain variables ''Power'' and ''Laser_WaveLength''.');
end

% Unique wavelengths
wl_unique = unique(double(paas.Laser_WaveLength));
n = numel(wl_unique);

% Colors from wavelength2color
cols = zeros(n,3);
for i = 1:n
    cols(i,:) = wavelength2color(wl_unique(i));
end

% Prepare powermeter attenuation column mapping:
% Prefer single 'Powermeter_Attenuation' split by Laser_WaveLength; otherwise accept
% explicit per-wavelength attenuation columns if present.
vars = paas.Properties.VariableNames;
useSingleAttn = ismember('Powermeter_Attenuation', vars);
attnCols = cell(n,1);
if useSingleAttn
    for i = 1:n
        attnCols{i} = 'Powermeter_Attenuation';
    end
else
    % try exact known names (attn405 etc.)
    fixedNames = {'attn405','attn473','attn515','attn520','attn660','attn785'};
    for i = 1:n
        fname = sprintf('attn%d', wl_unique(i));
        if ismember(fname, vars)
            attnCols{i} = fname;
        else
            attnCols{i} = '';
        end
    end
end

% Parse cfg soll map and period
soll_map = containers.Map('KeyType','double','ValueType','double');
if isfield(cfg, 'Powermeter_Attenuation_soll_wl') && ~isempty(cfg.Powermeter_Attenuation_soll_wl)
    s = cfg.Powermeter_Attenuation_soll_wl;
    % build soll_map robustly: accept fieldnames like '405' or 'x405' etc.
    flds = fieldnames(s);
    for k = 1:numel(flds)
        % extract the first run of digits from the field name
        tok = regexp(flds{k}, '\d+', 'match', 'once');
        if isempty(tok)
            continue
        end
        key = str2double(tok);
        if ~isnan(key)
            soll_map(key) = s.(flds{k});
        end
    end
end
soll_period = [];
if isfield(cfg, 'Powermeter_Attenuation_period') && ~isempty(cfg.Powermeter_Attenuation_period)
    try
        soll_period = datetime(cfg.Powermeter_Attenuation_period);
    catch
        soll_period = [];
    end
end

% Create figure with two rows
hFig = figure('Units','centimeters','Position',[5 5 36 18],'Color','w');
t = tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

% Top: Power per laser
ax1 = nexttile;
hold(ax1,'on');
for i = 1:n
    wl = wl_unique(i);
    mask = paas.Laser_WaveLength == wl;
    if any(mask)
        plot(ax1, paas.Time(mask), paas.Power(mask), '.', 'Color', cols(i,:), 'DisplayName', sprintf('%d nm', wl));
    end
end
xlabel(ax1,'Time'); ylabel(ax1,'Power'); title(ax1,'PAAS Laser Power by Wavelength');
legend(ax1,'Location','best'); grid(ax1,'on'); box(ax1,'on');
ax1.XAxis.TickLabelFormat = 'yyyy-MM-dd';  % include year

% Bottom: Powermeter attenuation per laser
ax2 = nexttile;
hold(ax2,'on');
plottedAny = false;
for i = 1:n
    colname = attnCols{i};
    if ~isempty(colname) && ismember(colname, paas.Properties.VariableNames)
        if useSingleAttn
            % plot per-laser points from single Powermeter_Attenuation split by Laser_WaveLength
            mask = paas.Laser_WaveLength == wl_unique(i);
            plot(ax2, paas.Time(mask), paas.Powermeter_Attenuation(mask), '.', 'Color', cols(i,:), 'DisplayName', sprintf('%d nm', wl_unique(i)));
        else
            % plot full column (one per wavelength)
            plot(ax2, paas.Time, paas{:,colname}, '-', 'Color', cols(i,:), 'DisplayName', sprintf('%d nm', wl_unique(i)));
        end
        plottedAny = true;
    end
end
if ~plottedAny
    text(ax2, 0.5, 0.5, 'No powermeter attenuation columns found in paas', 'HorizontalAlignment','center');
    axis(ax2,'off');
else
    ylabel(ax2,'Powermeter Attenuation'); title(ax2,'Powermeter Attenuation per Laser');
    legend(ax2,'Location','best'); grid(ax2,'on'); box(ax2,'on');
    ax2.XAxis.TickLabelFormat = 'yyyy-MM-dd';
    
    % Overlay soll lines from cfg (if present and within period)
    show_soll = ~isempty(soll_map);
    if show_soll && ~isempty(soll_period) && plottedAny
        pm_start = min(paas.Time); pm_end = max(paas.Time);
        % ensure consistent time zones before comparing
        if isdatetime(pm_end), pm_end.TimeZone = ''; end
        if isdatetime(pm_start), pm_start.TimeZone = ''; end
        if isdatetime(soll_period), soll_period.TimeZone = ''; end

        if pm_end < soll_period(1) || pm_start > soll_period(2)
            show_soll = false;
        end
    end
    if show_soll
        xplot = [min(paas.Time), max(paas.Time)];
        for i = 1:n
            w = wl_unique(i);
            if soll_map.isKey(w)
                sval = soll_map(w);
                plot(ax2, xplot, [sval sval], '--', 'Color', cols(i,:), 'LineWidth',1.2, 'DisplayName', sprintf('soll %d nm', w));
                % also mark midpoint
                xm = xplot(1) + (xplot(2)-xplot(1))/2;
                plot(ax2, xm, sval, 'o', 'MarkerFaceColor', cols(i,:), 'MarkerEdgeColor','k');
            end
        end
    end
end

% Ensure x-axis shows full datetime year on both axes
linkaxes([ax1 ax2],'x');

end
