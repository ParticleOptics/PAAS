function [b_abs,alpha,time,TimeStart,TimeEnd,time_highres, ...
        laser_wavelength] = calculate_b_abs( ...
        paas,valve_functionality,corr_method,remove_start_segments_enabled, ...
        maximum_background_gap_hours)
%CALCULATE_B_ABS Calculate absorption from imported PAAS data.
%   The signals are normalized by laser power, cell constant and gain.
%   Sample and background measurements are averaged by physical relay-state
%   blocks, and the background is interpolated to each sample-block time.

if nargin < 4 || isempty(remove_start_segments_enabled)
    remove_start_segments_enabled = true;
end
if nargin < 5 || isempty(maximum_background_gap_hours)
    maximum_background_gap_hours = 6;
end

% Remove instrument-start segments when appropriate. Pallas weekly files
% contain zero-relay file-start markers that are valid, so this is disabled
% in that campaign's configuration.
if remove_start_segments_enabled
    paas = remove_start_segments(paas, valve_functionality);
end

lasers = unique(paas.Laser);
gain_factor = paas.Calibration_Gain ./ paas.Lockin_Gain;
cell_constant = paas.Calbration_CellConstant;

% Convert the lock-in components to inverse metres. Power values rejected
% by quality control are NaN and therefore propagate as missing data.
scale = gain_factor ./ (paas.Power .* cell_constant);
paas.X = paas.X .* scale;
paas.Y = paas.Y .* scale;
paas.R = paas.R .* scale;

[b_abs,alpha,time,TimeStart,TimeEnd,time_highres,laser_wavelength] = ...
    calculate_from_relay_blocks( ...
    paas, valve_functionality, corr_method, lasers, ...
    maximum_background_gap_hours);
end


function [b_abs,alpha,time,TimeStart,TimeEnd,time_highres, ...
        laser_wavelength] = calculate_from_relay_blocks( ...
        paas, valve_functionality, corr_method, lasers, ...
        maximum_background_gap_hours)
%CALCULATE_FROM_RELAY_BLOCKS Average physical sample/background periods.

    is_bg = paas.Relay1 == valve_functionality(1,1) & ...
        paas.Relay2 == valve_functionality(1,2);
    is_sample = paas.Relay1 == valve_functionality(2,1) & ...
        paas.Relay2 == valve_functionality(2,2);

    state = zeros(height(paas), 1);
    state(is_bg) = 1;
    state(is_sample) = 2;

    % Do not merge equal relay states across logger outages or gaps between
    % separately downloaded files. Five minutes is comfortably longer than
    % the normal four-laser acquisition interval but shorter than an
    % operational interruption.
    time_gap_seconds = [0; seconds(diff(paas.TimeStamp))];
    new_block = [true; state(2:end) ~= state(1:end-1)] | ...
        time_gap_seconds > 300 | time_gap_seconds < 0;
    block_id = cumsum(new_block);

    bg_blocks = unique(block_id(is_bg), 'stable');
    sample_blocks = unique(block_id(is_sample), 'stable');
    n_bg = numel(bg_blocks);
    n_sample = numel(sample_blocks);

    if n_bg == 0 || n_sample == 0
        error(['Relay-block averaging requires at least one background ' ...
            'and one sample block.']);
    end

    n_lasers = numel(lasers);
    laser_wavelength = NaN(n_lasers, 1);

    % Map sparse logger block IDs and laser IDs to compact matrix indices,
    % then aggregate all rows in one pass. This scales linearly with record
    % count even for multi-year campaigns.
    block_to_sample = zeros(max(block_id), 1);
    block_to_sample(sample_blocks) = 1:n_sample;
    block_to_bg = zeros(max(block_id), 1);
    block_to_bg(bg_blocks) = 1:n_bg;
    [valid_laser, laser_position] = ismember(paas.Laser, lasers);
    mean_omitnan = @(x) mean(x, 'omitnan');

    sample_rows = is_sample & valid_laser;
    sample_subs = [laser_position(sample_rows), ...
        block_to_sample(block_id(sample_rows))];
    sample_x = accumarray(sample_subs, paas.X(sample_rows), ...
        [n_lasers, n_sample], mean_omitnan, NaN);
    sample_y = accumarray(sample_subs, paas.Y(sample_rows), ...
        [n_lasers, n_sample], mean_omitnan, NaN);
    sample_r = accumarray(sample_subs, paas.R(sample_rows), ...
        [n_lasers, n_sample], mean_omitnan, NaN);
    sample_signal = complex(sample_x, sample_y);

    bg_rows = is_bg & valid_laser;
    bg_subs = [laser_position(bg_rows), ...
        block_to_bg(block_id(bg_rows))];
    bg_x = accumarray(bg_subs, paas.X(bg_rows), ...
        [n_lasers, n_bg], mean_omitnan, NaN);
    bg_y = accumarray(bg_subs, paas.Y(bg_rows), ...
        [n_lasers, n_bg], mean_omitnan, NaN);
    bg_r_blocks = accumarray(bg_subs, paas.R(bg_rows), ...
        [n_lasers, n_bg], mean_omitnan, NaN);
    bg_signal_blocks = complex(bg_x, bg_y);

    timestamp_numeric = datenum(paas.TimeStamp);
    sample_block_index = block_to_sample(block_id(is_sample));
    sample_start_numeric = accumarray(sample_block_index, ...
        timestamp_numeric(is_sample), [n_sample, 1], @min, NaN);
    sample_end_numeric = accumarray(sample_block_index, ...
        timestamp_numeric(is_sample), [n_sample, 1], @max, NaN);
    bg_block_index = block_to_bg(block_id(is_bg));
    bg_start_numeric = accumarray(bg_block_index, ...
        timestamp_numeric(is_bg), [n_bg, 1], @min, NaN);
    bg_end_numeric = accumarray(bg_block_index, ...
        timestamp_numeric(is_bg), [n_bg, 1], @max, NaN);

    TimeStart = datetime(sample_start_numeric, 'ConvertFrom', 'datenum', ...
        'TimeZone', paas.TimeStamp.TimeZone)';
    TimeEnd = datetime(sample_end_numeric, 'ConvertFrom', 'datenum', ...
        'TimeZone', paas.TimeStamp.TimeZone)';
    bg_time_numeric = ((bg_start_numeric + bg_end_numeric)/2)';

    for i = 1:n_lasers
        wavelength_rows = paas.Laser == lasers(i);
        laser_wavelength(i) = median( ...
            paas.Laser_WaveLength(wavelength_rows), 'omitnan');
    end

    time = TimeStart + (TimeEnd - TimeStart)/2;
    sample_time_numeric = datenum(time);
    bg_signal = complex(NaN(n_lasers, n_sample));
    bg_r = NaN(n_lasers, n_sample);

    for i = 1:n_lasers
        bg_signal(i,:) = interpolate_block_background( ...
            bg_time_numeric, bg_signal_blocks(i,:), sample_time_numeric, ...
            maximum_background_gap_hours);
        bg_r(i,:) = interpolate_block_background( ...
            bg_time_numeric, bg_r_blocks(i,:), sample_time_numeric, ...
            maximum_background_gap_hours);
    end

    corrected_signal = sample_signal - bg_signal;
    alpha = rad2deg(angle(corrected_signal));
    switch corr_method
        case 1
            b_abs = sample_r - bg_r;
        case 2
            b_abs = abs(sample_signal) - abs(bg_signal);
        case 3
            b_abs = real(corrected_signal);
        case 4
            b_abs = abs(corrected_signal);
        otherwise
            error('corr_method must be 1, 2, 3 or 4.');
    end

    time_highres = NaT(0, 0, 'TimeZone', paas.TimeStamp.TimeZone);

    fprintf(['Relay-block averaging: %d sample blocks, %d background ' ...
        'blocks; background linearly interpolated in time with a %.1f h ' ...
        'maximum interpolation gap.\n'], ...
        n_sample, n_bg, maximum_background_gap_hours);
end


function interpolated = interpolate_block_background( ...
        bg_time, bg_value, sample_time, maximum_background_gap_hours)
%INTERPOLATE_BLOCK_BACKGROUND Interpolate with nearest endpoint fallback.

    valid = isfinite(bg_time) & isfinite(bg_value);
    bg_time = bg_time(valid);
    bg_value = bg_value(valid);

    if isempty(bg_time)
        interpolated = NaN(size(sample_time), 'like', bg_value);
        return
    end

    [bg_time, unique_index] = unique(bg_time, 'stable');
    bg_value = bg_value(unique_index);
    if numel(bg_time) == 1
        interpolated = repmat(bg_value, size(sample_time));
        return
    end

    interpolated = interp1(bg_time, bg_value, sample_time, 'linear');

    % Do not interpolate across logger outages. For a sample that lies
    % between backgrounds separated by a long gap, use whichever endpoint
    % is temporally nearer. This prevents a multi-day artificial background
    % ramp while still allowing a sample immediately after restart to use
    % the first new background.
    long_gap = find(diff(bg_time) > maximum_background_gap_hours/24);
    for k = long_gap
        in_gap = sample_time > bg_time(k) & sample_time < bg_time(k+1);
        nearer_right = (sample_time-bg_time(k)) > ...
            (bg_time(k+1)-sample_time);
        interpolated(in_gap & ~nearer_right) = bg_value(k);
        interpolated(in_gap & nearer_right) = bg_value(k+1);
    end
    interpolated(sample_time < bg_time(1)) = bg_value(1);
    interpolated(sample_time > bg_time(end)) = bg_value(end);
end
