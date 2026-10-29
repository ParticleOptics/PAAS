function hFig = plot_bg_component_comparison(BG,stats,plotfolder)
%PLOT_BG_COMPONENT_COMPARISON Plot block-mean backgrounds from X and R.
%   One panel is used. Wavelength is encoded by colour; the signed
%   in-phase component X is solid and the magnitude R is dashed.

wavelength = stats.wavelength;
hFig = figure('Color','w','Units','normalized', ...
    'Position',[0.06 0.12 0.88 0.7], ...
    'Name','Background X and R comparison');
ax = axes(hFig);
hold(ax,'on')

for i = 1:numel(wavelength)
    wl = wavelength(i);
    color = wavelength2color(wl,'gammaVal',1,'maxIntensity',1, ...
        'colorSpace','rgb');
    time = BG.(sprintf('Time_%d',wl));
    bg_x = 1e6*BG.(sprintf('BG_X_%d',wl));
    bg_r = 1e6*BG.(sprintf('BG_R_%d',wl));

    [time_x,bg_x] = break_long_gaps(time,bg_x, ...
        stats.maximum_pair_gap_hours);
    [time_r,bg_r] = break_long_gaps(time,bg_r, ...
        stats.maximum_pair_gap_hours);

    plot(ax,time_x,bg_x,'-','Color',color,'LineWidth',1.1, ...
        'DisplayName',sprintf('%g nm, X',wl));
    plot(ax,time_r,bg_r,'--','Color',color,'LineWidth',1.1, ...
        'DisplayName',sprintf('%g nm, R',wl));
end

yline(ax,0,':','Color',[0.55 0.55 0.55], ...
    'HandleVisibility','off');
xlabel(ax,'Time');
ylabel(ax,'Background-equivalent signal [Mm^{-1}]');
title(ax,'Background-block means: X (solid) and R (dashed)');
legend(ax,'Location','best','NumColumns',2);
grid(ax,'on');
box(ax,'on');
ax.FontSize = 13;

if nargin >= 3 && ~isempty(plotfolder)
    filename = fullfile(plotfolder,'background_X_R_block_means.png');
    exportgraphics(hFig,filename,'Resolution',180);
end
end


function [time_out,value_out] = break_long_gaps(time,value,max_gap_hours)
% Insert missing values so plotted lines do not bridge data outages.
breaks = find(diff(time) > hours(max_gap_hours));
time_out = time;
value_out = value;
for i = numel(breaks):-1:1
    position = breaks(i)+1;
    time_out = [time_out(1:position-1); ...
        NaT(1,1,'TimeZone',time.TimeZone); time_out(position:end)];
    value_out = [value_out(1:position-1); NaN; value_out(position:end)];
end
end
