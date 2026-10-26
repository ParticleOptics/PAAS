%% Photoacoustic Frequency Scan Plot
% Input     csv-file with PAAS scans
% Generates plot per scan that is saved in "outputfolder"
% Performs Lorenzian fir to data and saves f0 and Q

homeDir = char(java.lang.System.getProperty('user.home'));
datafolder   = fullfile(homeDir,'/Documents/Instruments/PAAS/PAAS-4L-005/Characterisation/Frequency scans/data/');
outputfolder = fullfile(homeDir,'/Documents/Instruments/PAAS/PAAS-4L-005/Characterisation/Frequency scans/plots');

filename = 'paas_005_scan_261021.csv';

split_and_plot_frequency_scans(datafolder, filename, outputfolder)


%% helper function
function split_and_plot_frequency_scans(datafolder, dataname, outputfolder)

%% ------------------------------------------------
% Load data
%% ------------------------------------------------
filepath = fullfile(datafolder,dataname);
paas_scan = readtimetable(filepath);

%% Extract variables
frequency_scan = paas_scan.Laser_Frequency;
R_scan         = paas_scan.R;
alpha_scan     = paas_scan.PhaseAngleXY;
lockin_phase   = paas_scan.Lockin_Phasing;
laser_wl       = paas_scan.Laser_WaveLength;
time           = paas_scan.TimeStamp;
temp           = paas_scan.Temperature;

alpha_scan_corr = alpha_scan - lockin_phase;

%% ------------------------------------------------
% Lorenzian function
%% ------------------------------------------------
lorentz = @(b,f) b(1) + ...
                 b(2) * ( (b(3)/(2*b(4)))^2 ) ./ ...
                 ( (f-b(3)).^2 + (b(3)/(2*b(4)))^2 );

% parameters: [offset amplitude f0 width]
b0 = [0.05 0.5 3200 20];


%% ------------------------------------------------
% Detect scan boundaries
%% ------------------------------------------------
scan_start = [1; find(diff(frequency_scan) < 0) + 1];
scan_end   = [scan_start(2:end)-1; length(frequency_scan)];

n_scans = length(scan_start);

fprintf('Detected %d scans\n',n_scans)

% Keep small scan sets visible for inspection and arrange them on screen.
% Larger batches retain the original behaviour: plots are exported and
% closed immediately to avoid filling the desktop with figure windows.
keep_figures_open = n_scans < 5;

if keep_figures_open
    screen = get(groot,'ScreenSize');
    margin = 40;
    gap = 20;

    n_cols = ceil(sqrt(n_scans));
    n_rows = ceil(n_scans/n_cols);

    available_width = screen(3) - 2*margin - (n_cols-1)*gap;
    available_height = screen(4) - 2*margin - (n_rows-1)*gap;
    fig_width = min(700, floor(available_width/n_cols));
    fig_height = min(520, floor(available_height/n_rows));

    grid_width = n_cols*fig_width + (n_cols-1)*gap;
    grid_height = n_rows*fig_height + (n_rows-1)*gap;
    grid_left = screen(1) + floor((screen(3)-grid_width)/2);
    grid_bottom = screen(2) + floor((screen(4)-grid_height)/2);
end

%% ------------------------------------------------
% Loop scans
%% ------------------------------------------------
for s = 1:n_scans

    idx = scan_start(s):scan_end(s);

    freq  = frequency_scan(idx);
    dfreq = diff(freq); dfreq = dfreq(1);
    R     = R_scan(idx);
    alpha = alpha_scan_corr(idx);
    wl    = round(mode(laser_wl(idx)));
    temp_mean = mean(temp(idx));

    %% Plot
    if keep_figures_open
        col = mod(s-1,n_cols);
        row_from_top = floor((s-1)/n_cols);
        fig_left = grid_left + col*(fig_width+gap);
        fig_bottom = grid_bottom + ...
            (n_rows-1-row_from_top)*(fig_height+gap);
        fig_position = [fig_left fig_bottom fig_width fig_height];
    else
        fig_position = [300 300 650 500];
    end

    fig = figure('Color','w', ...
        'Position',fig_position, ...
        'Name',sprintf('Frequency scan %d/%d',s,n_scans), ...
        'NumberTitle','off');

    yyaxis right
    p1 = plot(freq,R,'-ok','MarkerFaceColor','k',...
        'MarkerSize',5,'LineWidth',2); hold('on')

    ylabel('Photoacoustic Signal (V)',...
        'FontSize',16,'FontWeight','bold')

    set(gca,'ycolor','k')

    yyaxis left
    plot(freq,alpha,'-ob','MarkerFaceColor','b',...
        'MarkerSize',5,'LineWidth',2)

    ylabel('Phase Angle (°)',...
        'FontSize',16,'FontWeight','bold')

    xlabel('Frequency (Hz)',...
        'FontSize',16,'FontWeight','bold')

    grid on
    set(gca,'FontSize',14,'LineWidth',2)

    %% Fit
    b = nlinfit(freq, R, lorentz, b0);
    offset = b(1);
    amp    = b(2);
    f0     = b(3);
    Q      = abs(b(4));

    f_fit = linspace(min(freq), max(freq), 2000);
    R_fit = lorentz(b, f_fit);

    % fitted curve
    yyaxis right
    p2 = plot(f_fit, R_fit, '-r','LineWidth',2);
    xline(f0,'--k','HandleVisibility','off','LineWidth',2)
    xlim([min(freq), max(freq)])

    width = f0/Q;

    legend([p1 p2],...
        {sprintf('Measurement (LockIn phase %.0f)',lockin_phase(1)),...
         sprintf('Lorentz fit  f_0 = %.0f Hz,  FWHM = %.0f Hz,  Q = %.0f',f0,width,Q)},...
        'Location','northoutside','FontSize',14)

    %% ------------------------------------------------
    % Build filenames
    %% ------------------------------------------------
    t0 = time(idx(1));
    date_str = datestr(t0,'yyyymmdd');
    time_str = datestr(t0,'HHMMSS');
    [~,name,~] = fileparts(dataname);
    dfreq_rounded = round(dfreq);

    outname_plot = sprintf('FreqScan_%s_%s_%dnm_%02dHz.png',...
        date_str,time_str,wl,dfreq_rounded);
    outpath_plot = fullfile(outputfolder,outname_plot);

    outname_data = sprintf('FreqScan_%s_%s_%dnm_%02dHz.mat',...
        date_str,time_str,wl,dfreq_rounded);
    outpath_data = fullfile(outputfolder,outname_data);

    %% Export plot
    exportgraphics(fig,outpath_plot,'Resolution',300)
    if ~keep_figures_open
        close(fig)
    end

    %% Save scan and fit parameters
    scan_data = struct();
    scan_data.frequency = freq;
    scan_data.R = R;
    scan_data.alpha = alpha;
    scan_data.R_fit = R_fit;
    scan_data.f_fit = f_fit;
    scan_data.fit_parameters.offset = offset;
    scan_data.fit_parameters.amplitude = amp;
    scan_data.fit_parameters.f0 = f0;
    scan_data.fit_parameters.width = width;
    scan_data.fit_parameters.Q = Q;
    scan_data.mean_temperature = temp_mean;
    scan_data.laser_wavelength = wl;

    save(outpath_data,'-struct','scan_data')

end

end


