function [BG, stats] = compute_bg_statistics( ...
        paas, valve_functionality, time_av, maximum_pair_gap_hours)

if nargin < 4 || isempty(maximum_pair_gap_hours)
    maximum_pair_gap_hours = 6;
end

laser_id = unique(paas.Laser);
n_wl = length(laser_id);

% Map internal laser IDs (0, 1, ...) to physical wavelengths. Using the IDs
% as wavelengths made wavelength2color return black for every background
% trace.
wavelength = NaN(n_wl, 1);
for i = 1:n_wl
    idx_laser = paas.Laser == laser_id(i);
    wavelength(i) = median(double(paas.Laser_WaveLength(idx_laser)), ...
        'omitnan');
end

% Dataset should start with a background measurement
i = 1;
while (paas.Relay1(i) ~= valve_functionality(1,1))
    paas(i,:) = [];
end

% Dataset should end with a full background cycle
i = size(paas,1);
while i >= n_wl
    % Check last N entries
    idx = (i-n_wl+1):i;
    is_bg = (paas.Relay1(idx) == valve_functionality(1,1)) & ...
            (paas.Relay2(idx) == valve_functionality(1,2));
    % Check also that all lasers are present
    lasers_block = paas.Laser(idx);
    if all(is_bg) && numel(unique(lasers_block)) == n_wl
        break
    end
    % Otherwise remove last entry and continue
    paas(i,:) = [];
    i = i - 1;
end

BG = struct();

for i = 1:n_wl

    wl = wavelength(i);
    id = laser_id(i);

    idx = paas.Relay1 == valve_functionality(1,1) & ...
          paas.Relay2 == valve_functionality(1,2) & ...
          paas.Laser == id;

    time = paas.TimeStamp(idx);

    R = paas.R(idx);
    X = paas.X(idx);
    P = paas.Power(idx);
    f_g    = paas.Calibration_Gain(idx) ./ paas.Lockin_Gain(idx);
    C_cell = paas.Calbration_CellConstant(idx) ./ f_g;
    
    % absorption signals
    BG_R = R ./ P ./ C_cell;
    BG_X = X ./ P ./ C_cell;

    % File boundaries can produce duplicate timestamps. Consolidate those
    % first, then average every complete physical background relay block.
    [time, ~, time_group] = unique(time);
    mean_omitnan = @(x) mean(x,'omitnan');
    BG_R = accumarray(time_group, BG_R, [], mean_omitnan, NaN);
    BG_X = accumarray(time_group, BG_X, [], mean_omitnan, NaN);
    P = accumarray(time_group, P, [], mean_omitnan, NaN);

    % Within a background block, records for a given wavelength are about
    % 30 s apart. The intervening sample period creates a much longer gap.
    % Five minutes therefore separates physical background blocks while
    % tolerating an occasional missing acquisition.
    new_block = [true; diff(time) > minutes(5) | diff(time) < seconds(0)];
    block_id = cumsum(new_block);
    n_blocks = block_id(end);
    block_time_numeric = accumarray(block_id,posixtime(time), ...
        [n_blocks 1],@mean,NaN);
    time = datetime(block_time_numeric,'ConvertFrom','posixtime', ...
        'TimeZone',time.TimeZone);
    BG_R = accumarray(block_id,BG_R,[n_blocks 1],mean_omitnan,NaN);
    BG_X = accumarray(block_id,BG_X,[n_blocks 1],mean_omitnan,NaN);
    P = accumarray(block_id,P,[n_blocks 1],mean_omitnan,NaN);

    % Keep one row per block. A difference is assigned to the earlier block;
    % the final block has no following neighbour and therefore gets NaN.
    diff_BG_R = [diff(BG_R); NaN];
    diff_BG_X = [diff(BG_X); NaN];

    % Differences describe stability only when the two background records
    % belong to the same continuous operating period. Never bridge logger
    % outages or other multi-hour gaps: doing so turns a level change after
    % an outage into an artificial background-noise estimate.
    pair_gap = diff(time);
    invalid_pair = pair_gap < seconds(0) | ...
        pair_gap > hours(maximum_pair_gap_hours);
    invalid_difference = [invalid_pair; false];
    diff_BG_R(invalid_difference) = NaN;
    diff_BG_X(invalid_difference) = NaN;

    BG.(sprintf("BG_R_%d",wl)) = BG_R;
    BG.(sprintf("BG_X_%d",wl)) = BG_X;

    BG.(sprintf("diff_BG_R_%d",wl)) = diff_BG_R;
    BG.(sprintf("diff_BG_X_%d",wl)) = diff_BG_X;

    BG.(sprintf("Laser_Power_%d",wl)) = P;
    BG.(sprintf("Time_%d",wl)) = time;

    if i == 1
        BG.Time = time;
    end

end

% ------------------------------------------------
% create timetable
% ------------------------------------------------

BG_highres = timetable();

for i = 1:n_wl

    wl = wavelength(i);

    channel_time = BG.(sprintf("Time_%d",wl));
    channel_names = compose(["BG_R_%d", "BG_X_%d", ...
        "diff_BG_R_%d", "diff_BG_X_%d", "Laser_Power_%d"], wl);
    channel_tt = timetable(channel_time, ...
        BG.(sprintf("BG_R_%d",wl)), ...
        BG.(sprintf("BG_X_%d",wl)), ...
        BG.(sprintf("diff_BG_R_%d",wl)), ...
        BG.(sprintf("diff_BG_X_%d",wl)), ...
        BG.(sprintf("Laser_Power_%d",wl)), ...
        'VariableNames', cellstr(channel_names));
    channel_tt.Properties.DimensionNames{1} = 'Time';

    if width(BG_highres) == 0
        BG_highres = channel_tt;
    else
        BG_highres = synchronize(BG_highres, channel_tt, ...
            'union', 'fillwithmissing');
    end

end

BG.BG_highres = BG_highres;

% ------------------------------------------------
% averaging
% ------------------------------------------------

if time_av > 0.5
    BG.BG_baseline = retime(BG_highres,'regular',...
        @(x) mean(x,'omitnan'),'TimeStep',hours(time_av));
else
    BG.BG_baseline = BG_highres;
end

BG.wavelength = wavelength;

% ------------------------------------------------
% Compute statistics
% ------------------------------------------------

for i = 1:n_wl

    wl = wavelength(i);

    xR = BG.BG_baseline.(sprintf("diff_BG_R_%d",wl));
    xX = BG.BG_baseline.(sprintf("diff_BG_X_%d",wl));

    stats.R.mean(i) = mean(xR,'omitnan');
    stats.R.std(i)  = std(xR,'omitnan');
    stats.R.rmse(i) = sqrt(mean(xR.^2,'omitnan'));
    stats.R.prctile(:,i) = prctile(xR,[25 75]);

    stats.X.mean(i) = mean(xX,'omitnan');
    stats.X.std(i)  = std(xX,'omitnan');
    stats.X.rmse(i) = sqrt(mean(xX.^2,'omitnan'));
    stats.X.prctile(:,i) = prctile(xX,[25 75]);

end

stats.wavelength = wavelength;
stats.maximum_pair_gap_hours = maximum_pair_gap_hours;

end
