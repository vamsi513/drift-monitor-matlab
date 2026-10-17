%PARITY Compare MATLAB PSI against the Python values for the same snapshots.
%
%   Run from the project root:
%       >> parity
%
%   By default this scores the committed 2,000-row fixture, whose Python PSI
%   values were produced by running monitoring/drift.py on those exact rows
%   and are stored in data/expected_psi_fixture.csv.
%
%   To run against the full 50,000-row tables, export them as described in the
%   README ("Parity run") into data/full/ and the script picks them up. The
%   full-table comparison uses the per-feature values published in the
%   lead-scoring README, held in data/python_psi_full.csv. Those are rounded
%   to four decimals, so a difference of up to 5e-5 is rounding alone.
%
%   Nothing here is tuned to make the numbers agree. The gap is reported
%   as it falls out.

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

fullRef = fullfile(thisDir, 'data', 'full', 'reference.csv');
fullCur = fullfile(thisDir, 'data', 'full', 'current.csv');

if isfile(fullRef) && isfile(fullCur)
    refPath = fullRef;
    curPath = fullCur;
    expectedPath = fullfile(thisDir, 'data', 'python_psi_full.csv');
    expectedCol = 'published_psi';
    sourceLabel = 'full tables, Python values as published in the lead-scoring README';
    tolerance = 5e-5;   % the published values are rounded to 4 decimals
else
    refPath = fullfile(thisDir, 'data', 'fixture_reference.csv');
    curPath = fullfile(thisDir, 'data', 'fixture_current.csv');
    expectedPath = fullfile(thisDir, 'data', 'expected_psi_fixture.csv');
    expectedCol = 'python_psi';
    sourceLabel = 'committed 2,000-row fixture, Python values at full precision';
    tolerance = 1e-9;
    fprintf(['data/full/ not found, so this is the fixture comparison.\n' ...
             'See the README for how to run parity on the full tables.\n\n']);
end

reference = loadSnapshot(refPath);
current = loadSnapshot(curPath);
expected = readtable(expectedPath, 'TextType', 'string', 'VariableNamingRule', 'preserve');

monitor = drift.DriftMonitor();
result = monitor.fitScore(reference, current);

fprintf('PSI parity  (%s)\n', sourceLabel);
fprintf('reference %s (%d rows)\n', refPath, height(reference));
fprintf('current   %s (%d rows)\n\n', curPath, height(current));
fprintf('%-24s %10s %10s %12s  %s\n', 'feature', 'matlab', 'python', 'abs diff', 'verdict');

worstDiff = 0;
worstFeature = "";
comparedCount = 0;

for i = 1:height(result)
    name = result.feature(i);
    matlabPsi = result.psi(i);
    row = expected(expected.feature == name, :);

    if isempty(row) || isnan(row.(expectedCol)(1))
        fprintf('%-24s %10.4f %10s %12s  %s\n', name, matlabPsi, ...
            'n/a', '-', result.verdict(i));
        continue;
    end

    pythonPsi = row.(expectedCol)(1);
    diffValue = abs(matlabPsi - pythonPsi);
    comparedCount = comparedCount + 1;
    if diffValue > worstDiff
        worstDiff = diffValue;
        worstFeature = name;
    end
    fprintf('%-24s %10.4f %10.4f %12.2e  %s\n', name, matlabPsi, ...
        pythonPsi, diffValue, result.verdict(i));
end

fprintf('\ncompared %d of %d features against a published Python value\n', ...
    comparedCount, height(result));

if comparedCount == 0
    fprintf('no comparable Python values found, nothing to report\n');
else
    fprintf('largest absolute difference: %.3e  (%s)\n', worstDiff, worstFeature);
    if worstDiff <= tolerance
        fprintf('within the %.0e tolerance for this comparison\n', tolerance);
    else
        fprintf(['ABOVE the %.0e tolerance for this comparison.\n' ...
                 'Investigate the cause; do not adjust the binning to close the gap.\n'], ...
                 tolerance);
    end
end
