function t = loadSnapshot(csvPath)
%LOADSNAPSHOT Read a feature snapshot CSV into a table.
%
%   T = LOADSNAPSHOT(P) reads the CSV at P, keeping text columns as string so
%   the categorical features compare by value rather than by category code.
%
%   Base MATLAB only.

arguments
    csvPath (1,1) string
end

if ~isfile(csvPath)
    error('drift:loadSnapshot:missingFile', ...
        ['Snapshot CSV not found: %s\n' ...
         'The committed fixtures live in data/. For the full tables see ' ...
         'the "Parity run" section of the README.'], csvPath);
end

t = readtable(csvPath, 'TextType', 'string', 'VariableNamingRule', 'preserve');
end
