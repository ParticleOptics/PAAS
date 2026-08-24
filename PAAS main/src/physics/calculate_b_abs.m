function [b_abs,alpha,time,TimeStart,TimeEnd,time_highres,laser_wavelength] = ...
    calculate_b_abs(paas,valve_functionality,corr_method)
%calculate_b_abs Calculates absorption coefficients from imported PAAS data
% Background subtraction included
% X, Y and R are converted into m-1 using given f and cell constant
%   -> gain changes are taken into account
%   input                 
%       paas:                   imported paas data
%       valve_functionality:    status of relay 1 and 2 for BG and sample
%       corr_method:            method to calculate b_abs
%
%   For KIT PAAS: valve_functionality = [-1 0; 0 -1];

% Number of lasers and first laser
lasers = unique(paas.Laser);
number_of_lasers = length(lasers);

% Dataset should start with a background measurement
i = 1;
while (paas.Relay1(i) ~= valve_functionality(1,1))
    paas(i,:) = [];
end

% Dataset should end with a full background cycle
i = size(paas,1);
while i >= number_of_lasers
    % Check last N entries
    idx = (i-number_of_lasers+1):i;
    is_bg = (paas.Relay1(idx) == valve_functionality(1,1)) & ...
            (paas.Relay2(idx) == valve_functionality(1,2));
    % Check also that all lasers are present
    lasers_block = paas.Laser(idx);
    if all(is_bg) && numel(unique(lasers_block)) == number_of_lasers
        break
    end
    % Otherwise remove last entry and continue
    paas(i,:) = [];
    i = i - 1;
end

% Remove instrument start segments until valid BG
% (Both Relays 0) -> THIS DOES NOT WORK FOR PALLAS
paas = remove_start_segments(paas, valve_functionality);

% Calculate f
f = paas.Calibration_Gain ./ paas.Lockin_Gain;

% Cell constant
C_cell = paas.Calbration_CellConstant;

% Correct laser power
paas.X = paas.X ./ paas.Power;
paas.Y = paas.Y ./ paas.Power;
paas.R = paas.R ./ paas.Power;

% Apply cell constant
paas.X = paas.X ./ C_cell .*f;
paas.Y = paas.Y ./ C_cell .*f;
paas.R = paas.R ./ C_cell .*f;

% Calculate BG
X_bg_temp = [];
Y_bg_temp = [];
R_bg_temp = [];
for i = 1:number_of_lasers
    index_bg = find(paas.Relay1 == valve_functionality(1,1) & ...
        paas.Relay2 == valve_functionality(1,2) & paas.Laser==lasers(i));
    idx = find(diff(index_bg)>number_of_lasers);
    % Length of measurement cycle
    n = max(diff(idx));
    % Average BG measurements
    x_bg = paas.X(index_bg); x_bg = reshape(x_bg(1:n*floor(length(index_bg)./n)),n,floor(length(index_bg)./n));
    y_bg = paas.Y(index_bg); y_bg = reshape(y_bg(1:n*floor(length(index_bg)./n)),n,floor(length(index_bg)./n));
    r_bg = paas.R(index_bg); r_bg = reshape(r_bg(1:n*floor(length(index_bg)./n)),n,floor(length(index_bg)./n));
    X_bg_temp(i,:) = mean(x_bg,1,'omitnan');
    Y_bg_temp(i,:) = mean(y_bg,1,'omitnan');
    R_bg_temp(i,:) = mean(r_bg,1,'omitnan'); % not phase correct
    % Average time
    time_start_bg = paas.TimeStamp_start(index_bg); time_start_bg = reshape(time_start_bg(1:n*floor(length(index_bg)./n)),n,floor(length(index_bg)./n));
    time_end_bg = paas.TimeStamp_end(index_bg); time_end_bg = reshape(time_end_bg(1:n*floor(length(index_bg)./n)),n,floor(length(index_bg)./n));
    TimeStart(i,:) = time_start_bg(1,:);
    TimeEnd(i,:) = time_end_bg(end,:);
end
TimeStart = datenum(TimeStart); TimeStart = min(TimeStart); TimeStart = datetime(TimeStart,'ConvertFrom','datenum');
TimeEnd = datenum(TimeEnd); TimeEnd = max(TimeEnd); TimeEnd = datetime(TimeEnd,'ConvertFrom','datenum');
time_bg = mean([TimeStart; TimeEnd],1,'omitnan');

% Extract measurements and reshape
X = [];
Y = [];
R = [];
X_highres = [];
Y_highres = [];
R_highres = [];
laser_wavelength = [];
for i = 1:number_of_lasers
    index = find(paas.Relay1 == valve_functionality(2,1) & ...
        paas.Relay2 == valve_functionality(2,2) & paas.Laser==lasers(i));
    idx = find(diff(index)>number_of_lasers);
    % Length of measurement cycle
    n = max(diff(idx));
    x = paas.X(index); 
    y = paas.Y(index); 
    r = paas.R(index); 
    % High resolution values
    X_highres(i,:) = x';
    Y_highres(i,:) = y';
    R_highres(i,:) = r';
    % Make average values
    x = reshape(x(1:n*floor(length(index)./n)),n,floor(length(index)./n)); X(i,:) = mean(x,1,'omitnan');
    y = reshape(y(1:n*floor(length(index)./n)),n,floor(length(index)./n)); Y(i,:) = mean(y,1,'omitnan');
    r = reshape(r(1:n*floor(length(index)./n)),n,floor(length(index)./n)); R(i,:) = mean(r,1,'omitnan');
    laser_wavelength(i) = paas.Laser_WaveLength(index(1));
end
laser_wavelength = laser_wavelength';

% Get time for measurement cycle
TimeStart = NaT(number_of_lasers,size(X,2));
TimeEnd = NaT(number_of_lasers,size(X,2));
time_highres = NaT(size(X_highres)); time_highres.TimeZone = paas.TimeStamp.TimeZone;
for i = 1:number_of_lasers
    index = find(paas.Relay1 == valve_functionality(2,1) &...
        paas.Relay2 == valve_functionality(2,2) & paas.Laser==lasers(i));
    idx = find(diff(index)>number_of_lasers);
    % Length of measurement cycle
    n = max(diff(idx));
    % High resolution time
    time_highres(i,:) = paas.TimeStamp(index);
    % Average time
    time_start = paas.TimeStamp_start(index); time_start = reshape(time_start(1:n*floor(length(index)./n)),n,floor(length(index)./n));
    time_end = paas.TimeStamp_end(index); time_end = reshape(time_end(1:n*floor(length(index)./n)),n,floor(length(index)./n));
    TimeStart(i,:) = time_start(1,:);
    TimeEnd(i,:) = time_end(end,:);
end
TimeStart = datenum(TimeStart); TimeStart = min(TimeStart); TimeStart = datetime(TimeStart,'ConvertFrom','datenum');
TimeEnd = datenum(TimeEnd); TimeEnd = max(TimeEnd); TimeEnd = datetime(TimeEnd,'ConvertFrom','datenum');
time = mean([TimeStart; TimeEnd],1,'omitnan');

% Make average BG
X_bg = [];
Y_bg = [];
R_bg = [];
for i = 1:number_of_lasers
    a = X_bg_temp(i,:);
    X_bg(i,:) = arrayfun(@(k) mean(a(k:k+1)),1:length(a)-1); % the averaged bg over 2 samples
    a = Y_bg_temp(i,:);
    Y_bg(i,:) = arrayfun(@(k) mean(a(k:k+1)),1:length(a)-1); % the averaged bg over 2 samples
    a = R_bg_temp(i,:);
    R_bg(i,:) = arrayfun(@(k) mean(a(k:k+1)),1:length(a)-1); % the averaged bg over 2 samples
end

% Check that measurement is always surrounded by BG
% valid = false(size(time));
% for k = 1:length(time)
%     if k <= length(time_bg)-1
%         if ~isnat(time_bg(k)) && ~isnat(time_bg(k+1))
%             valid(k) = true;
%         end
%     end
% end
% % Apply mask
% R(:,~valid) = [];
% X(:,~valid) = [];
% Y(:,~valid) = [];
% time(:,~valid) = [];

if corr_method == 1
    % Calculate b_abs using R given by the LockIn
    % Not phase correct 
    b_abs = R - R_bg; % in 1/m
    
    % High resolution data
    b_abs_highres = NaN.* R_highres;
    for i = 1:number_of_lasers
        r = R_highres(i,:);
        r = reshape(r(1:n*floor(size(R_highres,2)./n)),n,floor(length(index)./n));
        r = r - R_bg(i,:); % remove average background
        b_abs_highres(i,:) = r(:)';
    end
    
elseif corr_method == 2
    % Calculate b_abs using R calculated from X and Y
    % Same as method 1 but R is calculated from x and y (sanity check)
    R_bg = sqrt((X_bg).^2 + (Y_bg).^2); % in V
    Rc = sqrt((X).^2 + (Y).^2); % in V
    b_abs = Rc - R_bg; % in 1/m
    
    % High resolution data
    Rc_highres = sqrt((X_highres).^2 + (Y_highres).^2); % in V
    b_abs_highres = NaN.* R_highres;
    for i = 1:number_of_lasers
        r = Rc_highres(i,:);
        r = reshape(r(1:n*floor(size(R_highres,2)./n)),n,floor(length(index)./n));
        r = r - R_bg(i,:); % remove average background
        b_abs_highres(i,:) = r(:)';
    end
    
elseif corr_method == 3
    % Calculate b_abs using projected R  
    S           = (X + 1i*Y);        % X,Y aktuelle Messung;
    S_highres   = X_highres  + 1i*Y_highres;     
    W0          = (X_bg + 1i*Y_bg); % Xw,Yw aus Leer-Kalibrierung (W0)

    %  Background-corrected signal
    S_corr = S - W0;
    alpha = rad2deg(angle(S_corr));
    b_abs = real(S_corr); % korrigierter Amplitudenwert in VW-1 auf Phase 0 bezogen
    
    % High resolution data
    for i = 1:number_of_lasers
        s_highres = reshape(S_highres(1:n*floor(size(S_highres,2)./n)),n,floor(length(index)./n));
        % s_highres(:,~valid) = [];
        for j=1:size(s_highres,1)
            s_corr(j,:) = s_highres(j,:) - W0(i,:);
        end
        r = real(s_corr);
        b_abs_highres(i,:) = r(:)';
    end
    
else % corr_method == 4
    % Calculate b_abs in a phase correct manner
    %Rc = sqrt((X-X_bg).^2 + (Y-Y_bg).^2); % in V
    S = (X + 1i*Y) - (X_bg + 1i*Y_bg); % complex signal
    alpha = rad2deg(angle(S)); % phase angle of signal in degree
    b_abs = abs(S); % in 1/m
    
    % High resolution data
    temp1 = NaN.* R_highres;
    temp2 = NaN.* R_highres;
    for i = 1:number_of_lasers
        x = X_highres(i,:);
        x = reshape(x(1:n*floor(size(R_highres,2)./n)),n,floor(length(index)./n));
        x = x - X_bg(i,:); % remove average background
        temp1(i,:) = x(:)';
        y = Y_highres(i,:);
        y = reshape(y(1:n*floor(size(R_highres,2)./n)),n,floor(length(index)./n));
        y = y - Y_bg(i,:); % remove average background
        temp2(i,:) = y(:)';
    end
    b_abs_highres = sqrt(temp1.^2 + temp2.^2); % 1/m
end





