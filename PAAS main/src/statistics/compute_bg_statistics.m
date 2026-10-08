function [BG, stats] = compute_bg_statistics(paas, valve_functionality, time_av)

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

    BG.(sprintf("BG_R_%d",wl)) = BG_R(1:end-1);
    BG.(sprintf("BG_X_%d",wl)) = BG_X(1:end-1);

    BG.(sprintf("diff_BG_R_%d",wl)) = diff(BG_R);
    BG.(sprintf("diff_BG_X_%d",wl)) = diff(BG_X);

    BG.(sprintf("Laser_Power_%d",wl)) = P(1:end-1);

    if i == 1
        BG.Time = time(1:end-1);
    end

end

% ------------------------------------------------
% create timetable
% ------------------------------------------------

BG_highres = timetable(BG.Time);

for i = 1:n_wl

    wl = wavelength(i);

    BG_highres.(sprintf("BG_R_%d",wl)) = BG.(sprintf("BG_R_%d",wl));
    BG_highres.(sprintf("BG_X_%d",wl)) = BG.(sprintf("BG_X_%d",wl));

    BG_highres.(sprintf("diff_BG_R_%d",wl)) = BG.(sprintf("diff_BG_R_%d",wl));
    BG_highres.(sprintf("diff_BG_X_%d",wl)) = BG.(sprintf("diff_BG_X_%d",wl));

    BG_highres.(sprintf("Laser_Power_%d",wl)) = BG.(sprintf("Laser_Power_%d",wl));

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

end
