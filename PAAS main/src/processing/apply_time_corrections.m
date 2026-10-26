function paas = apply_time_corrections(paas, cfg)
%APPLY_TIME_CORRECTIONS Apply campaign-specific time corrections
%   Prints diagnostics about how many rows were modified.

    arguments
        paas table
        cfg struct
    end

    if ~ismember("TimeStamp", paas.Properties.VariableNames)
        error("TimeStamp column not found.");
    end

    tc = cfg.time_correction;

    N0 = height(paas);

    % ---------------------------------------------------------------------
    % 1. Ensure datetime and assign input timezone if missing
    % ---------------------------------------------------------------------
    if ~isdatetime(paas.TimeStamp)
        paas.TimeStamp = datetime(paas.TimeStamp, ...
            "InputFormat","yyyy-MM-dd HH:mm:ss");
    end
    
    % Store original AFTER normalization
    original_time = paas.TimeStamp;
    original_time.TimeZone = tc.input_timezone;

    % ---------------------------------------------------------------------
    % 2. Manual time shift blocks (index-based corrections)
    %    (Manual time shifts needed to correct day-light saving time jumps)
    % ---------------------------------------------------------------------
    if isfield(tc,"manual_time_shifts")
    
        total_manual = 0;
    
        for k = 1:numel(tc.manual_time_shifts)
    
            s = tc.manual_time_shifts(k);
    
            idx = s.start_index : s.step : s.end_index;
    
            paas.TimeStamp(idx) = ...
                paas.TimeStamp(idx) + seconds(s.shift_seconds);
    
            total_manual = total_manual + numel(idx);
    
            fprintf("\nManual shift applied: rows %d:%d (step %d), %+d seconds\n", ...
                s.start_index, s.end_index, s.step, s.shift_seconds);
        end
    
        if total_manual > 0
            fprintf("  Total rows manually shifted: %d\n", total_manual);
        end
    end

    % ---------------------------------------------------------------------
    % 2b. Timestamp-period shifts
    %     Used when the instrument computer timezone changes. Period limits
    %     refer to the timestamps as stored in the raw files, before shifts.
    % ---------------------------------------------------------------------
    if isfield(tc, "period_time_shifts")
        for k = 1:numel(tc.period_time_shifts)
            s = tc.period_time_shifts(k);
            period_start = datetime(s.start_time, ...
                "InputFormat", "yyyy-MM-dd HH:mm:ss");
            period_end = datetime(s.end_time, ...
                "InputFormat", "yyyy-MM-dd HH:mm:ss");
            idx = paas.TimeStamp >= period_start & ...
                paas.TimeStamp <= period_end;

            paas.TimeStamp(idx) = paas.TimeStamp(idx) + ...
                seconds(s.shift_seconds);

            fprintf(['\nPeriod shift applied: %s to %s, ' ...
                '%+d seconds (%d rows)\n'], ...
                s.start_time, s.end_time, s.shift_seconds, sum(idx));
        end
    end

    % Assign input timezone if not already set
    if isempty(paas.TimeStamp.TimeZone)
        paas.TimeStamp.TimeZone = tc.input_timezone;
    end

    % ---------------------------------------------------------------------
    % 3. Timezone conversion 
    % ---------------------------------------------------------------------
    if isfield(tc,"apply_timezone_conversion") && tc.apply_timezone_conversion
        
        paas.TimeStamp.TimeZone = tc.output_timezone;

        fprintf("\nTimezone conversion applied:\n");
        fprintf("  From: %s\n", tz_before);
        fprintf("  To:   %s\n", tc.output_timezone);
    end

    % ---------------------------------------------------------------------
    % 4. Static offset
    % ---------------------------------------------------------------------
    if isfield(tc,"offset_seconds") && tc.offset_seconds ~= 0
        paas.TimeStamp = paas.TimeStamp + seconds(tc.offset_seconds);
    end

    % ---------------------------------------------------------------------
    % 5. Linear drift correction
    % ---------------------------------------------------------------------
    if isfield(tc,"drift_seconds_per_day") && tc.drift_seconds_per_day ~= 0

        t0 = paas.TimeStamp(1);
        dt_days = days(paas.TimeStamp - t0);
        drift = dt_days .* tc.drift_seconds_per_day;

        paas.TimeStamp = paas.TimeStamp + seconds(drift);
    end

    % ---------------------------------------------------------------------
    % 6. Diagnostics: how many rows changed?
    % ---------------------------------------------------------------------
    shift_seconds = seconds(paas.TimeStamp - original_time);
    changed_idx   = abs(shift_seconds) > 0;
    n_changed     = sum(changed_idx);

    if n_changed > 0
        fprintf("\nTime correction summary:\n");
        fprintf("  Total rows:           %d\n", N0);
        fprintf("  Rows modified:        %d (%.2f %%)\n", ...
            n_changed, 100*n_changed/N0);
        fprintf("  Mean shift (s):       %.3f\n", mean(shift_seconds(changed_idx)));
        fprintf("  Max abs shift (s):    %.3f\n", max(abs(shift_seconds)));
    else
        fprintf("\nNo timestamp changes applied.\n");
    end

    paas = sortrows(paas,"TimeStamp");

    fprintf("Time correction complete.\n\n");

end
