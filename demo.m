%DEMO Run the whole drift monitor end to end on the committed fixture.
%
%   From the project root:
%       >> demo
%
%   Fits bin edges on the reference snapshot, scores the current snapshot,
%   prints the result table and saves the bar chart to docs/psi.png.
%
%   The data is synthetic: it comes from the generator in the lead-scoring
%   project, not from real leads.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

reference = loadSnapshot(fullfile(thisDir, 'data', 'fixture_reference.csv'));
current = loadSnapshot(fullfile(thisDir, 'data', 'fixture_current.csv'));

fprintf('reference: %d rows, %d features\n', height(reference), width(reference));
fprintf('current:   %d rows, %d features\n\n', height(current), width(current));

monitor = drift.DriftMonitor();
monitor = monitor.fit(reference);
result = monitor.score(current);

disp(result);

flagged = result(result.verdict == "shift", :);
fprintf('\n%d feature(s) at or above %.2f\n', ...
    height(flagged), drift.DriftMonitor.ShiftThreshold);
if ~isempty(flagged)
    fprintf('  %s\n', strjoin(flagged.feature', ', '));
end

watch = result(result.verdict == "watch", :);
fprintf('%d feature(s) in the watch band\n', height(watch));
if ~isempty(watch)
    fprintf('  %s\n', strjoin(watch.feature', ', '));
end

plot_psi(result);

fprintf('\nFor the comparison against the Python values, run: parity\n');
