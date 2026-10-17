function outputPath = plot_psi(result, outputPath)
%PLOT_PSI Save a PSI bar chart per feature to a PNG.
%
%   PLOT_PSI(RESULT) writes docs/psi.png, where RESULT is the table returned
%   by drift.DriftMonitor/score.
%
%   PLOT_PSI(RESULT, PATH) writes to PATH instead.
%
%   Bars are coloured by verdict and the two thresholds are drawn in, so the
%   chart can be read without consulting the table. Base MATLAB only.
%
%   The figure is created invisible and closed afterwards, so this works in a
%   headless session such as MATLAB Online or CI.

arguments
    result table
    outputPath (1,1) string = ""
end

if outputPath == ""
    thisDir = fileparts(mfilename('fullpath'));
    outputPath = string(fullfile(thisDir, 'docs', 'psi.png'));
end

outputDir = fileparts(outputPath);
if outputDir ~= "" && ~isfolder(outputDir)
    mkdir(outputDir);
end

result = sortrows(result, 'psi', 'descend');
n = height(result);

fig = figure('Visible', 'off', 'Position', [100 100 1000 max(400, 26 * n + 170)]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig); %#ok<LAXES>

bars = barh(ax, (1:n)', flipud(result.psi));
bars.FaceColor = 'flat';

% One colour per verdict, applied bottom-up because barh counts from the
% bottom and the table is sorted worst first.
verdicts = flipud(result.verdict);
colours = containers.Map( ...
    {'stable', 'watch', 'shift'}, ...
    {[0.42 0.62 0.45], [0.85 0.68 0.28], [0.78 0.33 0.29]});
cdata = zeros(n, 3);
for i = 1:n
    cdata(i, :) = colours(char(verdicts(i)));
end
bars.CData = cdata;

set(ax, 'YTick', 1:n, 'YTickLabel', flipud(result.feature), 'TickLabelInterpreter', 'none');
ylim(ax, [0.5, n + 0.5]);
xlabel(ax, 'population stability index');
title(ax, sprintf('PSI by feature  (%d features, %d flagged at %.2f or above)', ...
    n, sum(result.psi >= drift.DriftMonitor.ShiftThreshold), ...
    drift.DriftMonitor.ShiftThreshold));

xMax = max([result.psi; drift.DriftMonitor.ShiftThreshold]) * 1.15;
xlim(ax, [0, xMax]);
hold(ax, 'on');
xline(ax, drift.DriftMonitor.WatchThreshold, '--', 'watch 0.10', ...
    'LabelVerticalAlignment', 'bottom', 'Color', [0.45 0.45 0.45]);
xline(ax, drift.DriftMonitor.ShiftThreshold, '--', 'shift 0.25', ...
    'LabelVerticalAlignment', 'bottom', 'Color', [0.45 0.45 0.45]);
hold(ax, 'off');
grid(ax, 'on');
ax.GridAlpha = 0.15;

exportgraphics(fig, outputPath, 'Resolution', 150);
fprintf('wrote %s\n', outputPath);
end
