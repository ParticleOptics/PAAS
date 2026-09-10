function paas = apply_raw_corrections(paas, cfg)
%APPLY_CORRECTIONS Apply campaign-specific corrections to raw data:
%   - phase angle rotation
%   - correction of cell constant
%   - mark interlock failure periods as NaN

    arguments
        paas table
        cfg struct
    end

    % -------------------------------------------------------------
    % Phase angle correction
    % -------------------------------------------------------------
    if isfield(cfg,"phase_angle_soll") && ...
       isfield(cfg,"phase_angle_soll_period") && ...
       isfield(cfg,"phase_angle_soll_lasers")
    
        % --- Time selection ---
        period = datetime(cfg.phase_angle_soll_period, ...
                          "TimeZone", paas.TimeStamp.TimeZone);
    
        idx_time = paas.TimeStamp >= period(1) & ...
                   paas.TimeStamp <  period(2);
    
        % --- Laser selection ---
        idx_laser = ismember(paas.Laser, cfg.phase_angle_soll_lasers);
    
        % --- Combined mask ---
        idx = idx_time & idx_laser;
    
        if any(idx)
            % Phase correction only for selected subset
            dphi = deg2rad(cfg.phase_angle_soll - paas.Lockin_Phasing(idx));
    
            X_new = paas.X(idx).*cos(dphi) - paas.Y(idx).*sin(dphi);
            Y_new = paas.X(idx).*sin(dphi) + paas.Y(idx).*cos(dphi);
    
            paas.X(idx) = X_new;
            paas.Y(idx) = Y_new;
    
            fprintf(['Phase angle set to %.1f° for lasers [%s] ' ...
                     'in period %s to %s (%d points).\n\n'], ...
                cfg.phase_angle_soll, ...
                num2str(cfg.phase_angle_soll_lasers), ...
                datestr(period(1)), ...
                datestr(period(2)), ...
                sum(idx));
        end
    end


    % -------------------------------------------------------------
    % Cell constant correction
    % -------------------------------------------------------------
    if isfield(cfg,"c_cell_soll") && isfield(cfg,"c_cell_soll_period")

        period = datetime(cfg.c_cell_soll_period, ...
                          "TimeZone", paas.TimeStamp.TimeZone);
    
        idx = paas.TimeStamp >= period(1) & paas.TimeStamp < period(2);
    
        if any(idx)
            
            Calbration_CellConstant_new = cfg.c_cell_soll;
            Calibration_Gain_new        = cfg.calibration_gain;
    
            paas.Calbration_CellConstant(idx) = Calbration_CellConstant_new;
            paas.Calibration_Gain(idx)        = Calibration_Gain_new;
    
            fprintf(['Cell constant set to %.4f and calibration gain to %.1f ' ...
                     'for period %s to %s (%d timestamps).\n\n'], ...
                Calbration_CellConstant_new, ...
                Calibration_Gain_new, ...
                datestr(period(1)), ...
                datestr(period(2)), ...
                sum(idx));
        end
    end

    % -------------------------------------------------------------
    % Powermeter attenuation correction (wavelength-based)
    % -------------------------------------------------------------
    if isfield(cfg,"Powermeter_Attenuation_soll_wl") && ...
       ~isempty(cfg.Powermeter_Attenuation_soll_wl)

        % A period remains supported for exceptional campaign-specific
        % overrides. Without one, the instrument-level attenuation applies
        % to the complete dataset.
        has_attenuation_period = ...
            isfield(cfg,"Powermeter_Attenuation_period") && ...
            ~isempty(cfg.Powermeter_Attenuation_period);

        if has_attenuation_period
            period = datetime(cfg.Powermeter_Attenuation_period, ...
                              "TimeZone", paas.TimeStamp.TimeZone);

            idx_time = paas.TimeStamp >= period(1) & ...
                       paas.TimeStamp <  period(2);
        else
            idx_time = true(height(paas), 1);
        end
    
        if any(idx_time)
    
            wl_map = cfg.Powermeter_Attenuation_soll_wl;
    
            % Default: no correction
            scale = ones(sum(idx_time),1);
            
            wl_data = paas.Laser_WaveLength(idx_time);
            
            tol = 1;  % nm
            
            wl_fields = fieldnames(wl_map);
            
            for i = 1:numel(wl_fields)
            
                wl_key = wl_fields{i};
                wl_target = str2double(regexprep(wl_key, '[^0-9.]', ''));
            
                mask = abs(wl_data - wl_target) < tol;
            
                if any(mask)
            
                    A_soll = wl_map.(wl_key);
                    A_meas = paas.Powermeter_Attenuation(idx_time);
                    A_meas = A_meas(mask);
            
                    A_soll_lin = 10^(A_soll/10);
                    A_meas_lin = 10.^(A_meas/10);
            
                    scale(mask) = A_soll_lin ./ A_meas_lin;
            
                end
            end
            
            % Apply correction
            paas.Power(idx_time) = paas.Power(idx_time) .* scale;
    
            if has_attenuation_period
                fprintf(['Powermeter attenuation corrected ' ...
                         '(wavelength-based) for period %s to %s ' ...
                         '(%d points).\n\n'], ...
                    datestr(period(1)), ...
                    datestr(period(2)), ...
                    sum(idx_time));
            else
                fprintf(['Powermeter attenuation corrected ' ...
                         '(wavelength-based) for all timestamps ' ...
                         '(%d points).\n\n'], ...
                    sum(idx_time));
            end
    
        end
    end

    % -------------------------------------------------------------
    % Interlock failure
    %   - Sets paas.Power = NaN for affected laser + time periods
    % -------------------------------------------------------------
    if ~isfield(cfg,"interlock_failure_period") || ...
       ~isfield(cfg,"interlock_failure_laser")
        return
    end

    periods = cfg.interlock_failure_period;
    lasers  = cfg.interlock_failure_laser;

    for i = 1:size(periods,1)

        % --- Time selection ---
        period = datetime(periods{i,:}, ...
                          "TimeZone", paas.TimeStamp.TimeZone);

        idx_time = paas.TimeStamp >= period(1) & ...
                   paas.TimeStamp <= period(2);

        % --- Laser selection ---
        laser_id = lasers(i);
        idx_laser = paas.Laser == laser_id;

        % --- Combined mask ---
        idx = idx_time & idx_laser;

        if any(idx)
            % Apply masking
            paas.Power(idx) = NaN;

            fprintf(['Interlock filter: Laser %d masked for period %s to %s ' ...
                     '(%d points).\n'], ...
                laser_id, ...
                datestr(period(1)), ...
                datestr(period(2)), ...
                sum(idx));
        end
    end

end
