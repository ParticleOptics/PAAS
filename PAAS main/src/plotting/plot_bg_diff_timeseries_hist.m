function plot_bg_diff_timeseries_hist(BG_baseline, stats, component, time_av, plotfolder, axis_limit_override)

if nargin < 6
    axis_limit_override = [];
end

wavelength = stats.wavelength;
n_wl = length(wavelength);

graph = figure("Position",[0 0 1000 650]);

for i = 1:n_wl

    wl = wavelength(i);

    sigma = stats.(component).rmse(i)*1e6;
    mu    = stats.(component).mean(i)*1e6;

    laser_color = wavelength2color(wl,'gammaVal',1,'maxIntensity',1,'colorSpace','rgb');

    diff_var = sprintf("diff_BG_%s_%d",component,wl);
    y_values = BG_baseline.(diff_var)*1e6;
    x = y_values;
    x = x(isfinite(x));

    % Use a robust display range so isolated artefacts do not compress the
    % background distribution. The +/-2sigma lines always remain visible;
    % observations outside the display range are retained as border markers.
    if isempty(axis_limit_override)
        robust_limit = prctile(abs(x),99.5);
        axis_tick_limit = max([0.25, 1.15*(2*sigma), 1.10*robust_limit]);
        axis_tick_limit = ceil(axis_tick_limit*10)/10;
        % Keep the labelled outer ticks inside the axes instead of directly
        % on the panel boundary.
        axis_limit = 1.07*axis_tick_limit;
    else
        % Optional common range for figures that must be compared directly.
        axis_limit = axis_limit_override;
        axis_tick_limit = floor(axis_limit);
    end

    y0 = 0.77 - (i-1)*0.21;

    %% Time series
    subplot('Position',[0.075 y0 0.68 0.19])

    data_handle = plot(BG_baseline.Time, y_values,'.', ...
        'Color',laser_color);

    hold on

    limit_handle = plot([BG_baseline.Time(1) BG_baseline.Time(end)], ...
        [2*sigma 2*sigma],'--k','LineWidth',3);
    plot([BG_baseline.Time(1) BG_baseline.Time(end)], ...
        [-2*sigma -2*sigma],'--k','LineWidth',3,'HandleVisibility','off')

    above_limit = isfinite(y_values) & y_values > axis_limit;
    below_limit = isfinite(y_values) & y_values < -axis_limit;
    plot(BG_baseline.Time(above_limit), ...
        repmat(0.96*axis_limit,sum(above_limit),1),'^', ...
        'Color',laser_color,'MarkerFaceColor',laser_color, ...
        'MarkerSize',4,'LineStyle','none','HandleVisibility','off')
    plot(BG_baseline.Time(below_limit), ...
        repmat(-0.96*axis_limit,sum(below_limit),1),'v', ...
        'Color',laser_color,'MarkerFaceColor',laser_color, ...
        'MarkerSize',4,'LineStyle','none','HandleVisibility','off')

    grid on
    set(gca,'FontSize',16,'YMinorTick','on','LineWidth',1.5)

    ylim([-axis_limit axis_limit])
    yticks([-axis_tick_limit 0 axis_tick_limit])
    xlim([BG_baseline.Time(1) BG_baseline.Time(end)])

    ylabel('b_{abs} [Mm^{-1}]')

    if i < n_wl
        set(gca,'XTickLabel',[])
    else
        xlabel('Time')
    end

    legend([data_handle limit_handle], ...
        {sprintf('%d nm',wl), sprintf('2\\sigma = %.2f Mm^{-1}',2.*sigma)}, ...
        'Location','northeast','FontSize',13)

    %% Histogram
    subplot('Position',[0.76 y0 0.2 0.19])

    histogram_handle = histogram(x,50,'FaceColor',laser_color, ...
        'EdgeColor','none','Normalization','pdf');

    hold on

    y = linspace(-axis_limit,axis_limit,2001);
    f = exp(-(y-mu).^2./(2*sigma^2))./(sigma*sqrt(2*pi));

    plot(y,f,'LineWidth',2.5,'Color',laser_color)

    grid on
    set(gca,'FontSize',12,'XMinorTick','on','XTickLabel',[], ...
        'YTickLabel',[],'LineWidth',1.5,'View',[90 -90])

    legend({'Histogram','Normal PDF'},'Location','northeast','FontSize',14)

    xlim([-axis_limit axis_limit])
    density_limit = 1.1*max([histogram_handle.Values(:); f(:)]);
    ylim([0 density_limit])

end

set(gcf,'paperpositionmode','auto')
filename = fullfile(plotfolder,['BGvariation_',num2str(time_av),'h_averaging.png']); 
exportgraphics(graph, filename)

end
