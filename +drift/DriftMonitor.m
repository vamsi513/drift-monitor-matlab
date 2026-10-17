classdef DriftMonitor
    %DRIFTMONITOR Population stability index between two feature snapshots.
    %
    %   PSI compares how a feature's distribution is spread across a fixed set
    %   of bins in a reference sample against a later one:
    %
    %       PSI = sum over bins of (actual - expected) * log(actual / expected)
    %
    %   Bin edges come from quantiles of the reference only, so the reference
    %   is the fixed yardstick and the comparison sample is scored against it.
    %
    %   This is a port of monitoring/drift.py from the lead-scoring project and
    %   is written to reproduce its numbers. It uses base MATLAB only: no
    %   toolbox functions are called. In particular QUANTILE is deliberately
    %   not used, both because it belongs to Statistics and Machine Learning
    %   Toolbox and because its interpolation convention differs from the one
    %   the Python implementation relies on (see quantileLinear below).
    %
    %   Usage:
    %       monitor = drift.DriftMonitor();
    %       monitor = monitor.fit(referenceTable);
    %       result  = monitor.score(currentTable);
    %
    %   PSI is a distance between distributions. It says a feature moved; it
    %   does not say the model got worse, and it knows nothing about labels.

    properties (Constant)
        % Default bin count for numeric features.
        DefaultBins (1,1) double = 10

        % Conventional reading of a PSI value.
        WatchThreshold (1,1) double = 0.10
        ShiftThreshold (1,1) double = 0.25

        % Floor applied to a bin's share before the log, so a bin that is
        % empty in one sample gives a large but finite contribution instead
        % of infinity.
        Epsilon (1,1) double = 1e-6
    end

    properties (SetAccess = private)
        % Number of quantile bins requested for numeric features.
        % Literal rather than DefaultBins: a property default must not refer
        % to the class currently being defined.
        NumBins (1,1) double = 10

        % Feature name -> bin edges (numeric) learned from the reference.
        NumericEdges (1,1) struct = struct()

        % Feature name -> reference sample, kept for categorical levels and
        % for the degenerate constant-reference case.
        ReferenceValues (1,1) struct = struct()

        % Names in the order they were fitted, and their kind.
        FeatureNames (1,:) string = string.empty(1, 0)
        FeatureKinds (1,:) string = string.empty(1, 0)

        % True once fit has run.
        IsFitted (1,1) logical = false
    end

    methods
        function obj = DriftMonitor(numBins)
            %DRIFTMONITOR Construct a monitor, optionally with a bin count.
            arguments
                numBins (1,1) double {mustBeInteger, mustBePositive} = ...
                    drift.DriftMonitor.DefaultBins
            end
            obj.NumBins = numBins;
        end

        function obj = fit(obj, referenceTable, featureNames)
            %FIT Learn bin edges and categorical levels from a reference table.
            %
            %   OBJ = FIT(OBJ, T) fits every column of table T.
            %   OBJ = FIT(OBJ, T, NAMES) fits only the named columns.
            arguments
                obj
                referenceTable table
                featureNames (1,:) string = string(referenceTable.Properties.VariableNames)
            end

            if height(referenceTable) == 0
                error('drift:DriftMonitor:emptyReference', ...
                    'Cannot fit on a reference table with no rows.');
            end

            missingCols = setdiff(featureNames, ...
                string(referenceTable.Properties.VariableNames));
            if ~isempty(missingCols)
                error('drift:DriftMonitor:unknownFeature', ...
                    'Reference table has no column named "%s".', missingCols(1));
            end

            obj.NumericEdges = struct();
            obj.ReferenceValues = struct();
            obj.FeatureNames = string.empty(1, 0);
            obj.FeatureKinds = string.empty(1, 0);

            for name = featureNames
                column = referenceTable.(char(name));
                key = char(matlab.lang.makeValidName(name));

                if drift.DriftMonitor.isNumericColumn(column)
                    values = double(column(:));
                    obj.NumericEdges.(key) = drift.DriftMonitor.numericEdges( ...
                        values, obj.NumBins);
                    obj.ReferenceValues.(key) = values;
                    obj.FeatureKinds(end + 1) = "numeric"; %#ok<AGROW>
                else
                    obj.ReferenceValues.(key) = drift.DriftMonitor.asLevels(column);
                    obj.FeatureKinds(end + 1) = "categorical"; %#ok<AGROW>
                end
                obj.FeatureNames(end + 1) = name; %#ok<AGROW>
            end

            obj.IsFitted = true;
        end

        function result = score(obj, currentTable)
            %SCORE PSI per feature for a current table, worst first.
            %
            %   RESULT = SCORE(OBJ, T) returns a table with one row per fitted
            %   feature and the columns feature, kind, psi and verdict, sorted
            %   by descending psi.
            arguments
                obj
                currentTable table
            end

            if ~obj.IsFitted
                error('drift:DriftMonitor:notFitted', ...
                    'Call fit on a reference table before score.');
            end
            if height(currentTable) == 0
                error('drift:DriftMonitor:emptyCurrent', ...
                    'Cannot score a current table with no rows.');
            end

            n = numel(obj.FeatureNames);
            psi = zeros(n, 1);
            kinds = strings(n, 1);
            names = strings(n, 1);

            for i = 1:n
                name = obj.FeatureNames(i);
                key = char(matlab.lang.makeValidName(name));
                names(i) = name;
                kinds(i) = obj.FeatureKinds(i);

                if ~ismember(name, string(currentTable.Properties.VariableNames))
                    error('drift:DriftMonitor:unknownFeature', ...
                        'Current table has no column named "%s".', name);
                end
                column = currentTable.(char(name));

                if obj.FeatureKinds(i) == "numeric"
                    psi(i) = drift.DriftMonitor.psiNumeric( ...
                        obj.ReferenceValues.(key), double(column(:)), ...
                        obj.NumericEdges.(key));
                else
                    psi(i) = drift.DriftMonitor.psiCategorical( ...
                        obj.ReferenceValues.(key), ...
                        drift.DriftMonitor.asLevels(column));
                end
            end

            verdict = drift.DriftMonitor.verdictFor(psi);
            result = table(names, kinds, psi, verdict, ...
                'VariableNames', {'feature', 'kind', 'psi', 'verdict'});
            result = sortrows(result, 'psi', 'descend');
        end

        function result = fitScore(obj, referenceTable, currentTable, featureNames)
            %FITSCORE Convenience: fit on one table and score another.
            arguments
                obj
                referenceTable table
                currentTable table
                featureNames (1,:) string = ...
                    string(referenceTable.Properties.VariableNames)
            end
            obj = obj.fit(referenceTable, featureNames);
            result = obj.score(currentTable);
        end
    end

    methods (Static)
        function verdict = verdictFor(psi)
            %VERDICTFOR Conventional reading of a PSI value.
            %
            %   Below 0.10 is stable, 0.10 up to 0.25 is watch, 0.25 and above
            %   is shift. The label "shift" is the one the Python
            %   implementation uses and is kept here so the two agree.
            psi = psi(:);
            verdict = repmat("stable", numel(psi), 1);
            verdict(psi >= drift.DriftMonitor.WatchThreshold) = "watch";
            verdict(psi >= drift.DriftMonitor.ShiftThreshold) = "shift";
        end

        function q = quantileLinear(x, p)
            %QUANTILELINEAR Linear-interpolation quantiles, NumPy convention.
            %
            %   Reproduces numpy.quantile's default method ("linear", also
            %   known as R type 7): the sorted sample is placed at positions
            %   0..n-1 and the quantile is read off by linear interpolation at
            %   (n-1)*p.
            %
            %   MATLAB's own QUANTILE places the sorted sample at (i-0.5)/n
            %   instead, which is a different estimator, and it requires
            %   Statistics and Machine Learning Toolbox. Writing the rule out
            %   here keeps this file on base MATLAB and keeps the bin edges
            %   identical to the Python implementation.
            x = sort(double(x(:)));
            x = x(~isnan(x));
            n = numel(x);
            p = double(p(:));

            if n == 0
                q = nan(size(p));
                return;
            end
            if n == 1
                q = repmat(x, size(p));
                return;
            end

            h = (n - 1) .* p;
            lo = floor(h);
            hi = ceil(h);
            loIdx = min(max(lo + 1, 1), n);
            hiIdx = min(max(hi + 1, 1), n);
            q = x(loIdx) + (h - lo) .* (x(hiIdx) - x(loIdx));
        end

        function edges = numericEdges(reference, numBins)
            %NUMERICEDGES Quantile bin edges from the reference sample.
            %
            %   Duplicate edges are collapsed, which matters because several
            %   count features are zero for a large share of leads and would
            %   otherwise produce several identical cut points. The outer
            %   edges are opened so values beyond the reference range land in
            %   the first or last bin rather than outside every bin.
            probabilities = linspace(0, 1, numBins + 1);
            edges = unique(drift.DriftMonitor.quantileLinear(reference, probabilities));
            edges = edges(:)';

            if isempty(edges) || all(isnan(edges))
                edges = double.empty(1, 0);
                return;
            end

            edges(1) = -Inf;
            edges(end) = Inf;
        end

        function value = psiNumeric(reference, current, edges)
            %PSINUMERIC PSI for one numeric feature against fitted edges.
            reference = double(reference(:));
            current = double(current(:));

            if numel(edges) < 3
                % The reference is effectively constant, so there is nothing
                % to bin. Report movement only if the current sample left that
                % single value. This mirrors the Python implementation.
                refClean = reference(~isnan(reference));
                if isempty(current)
                    same = 1.0;
                elseif isempty(refClean)
                    same = 1.0;
                else
                    same = mean(current == refClean(1));
                end
                if same == 1.0
                    value = 0.0;
                else
                    value = abs(1.0 - same);
                end
                return;
            end

            expected = drift.DriftMonitor.shares(histcounts(reference, edges));
            actual = drift.DriftMonitor.shares(histcounts(current, edges));
            value = drift.DriftMonitor.psiFromShares(expected, actual);
        end

        function value = psiCategorical(reference, current)
            %PSICATEGORICAL PSI for one categorical feature, one bin per level.
            %
            %   Levels are the union of both samples, so a category that
            %   appears only in the current sample is counted rather than
            %   silently dropped. Missing values are excluded from both the
            %   level set and the denominator.
            reference = reference(:);
            current = current(:);
            reference = reference(~ismissing(reference));
            current = current(~ismissing(current));

            levels = unique([reference; current]);
            if isempty(levels)
                error('drift:DriftMonitor:emptySample', ...
                    'Cannot compute shares for a sample with no observed levels.');
            end

            expectedCounts = zeros(1, numel(levels));
            actualCounts = zeros(1, numel(levels));
            for i = 1:numel(levels)
                expectedCounts(i) = sum(reference == levels(i));
                actualCounts(i) = sum(current == levels(i));
            end

            expected = drift.DriftMonitor.shares(expectedCounts);
            actual = drift.DriftMonitor.shares(actualCounts);
            value = drift.DriftMonitor.psiFromShares(expected, actual);
        end
    end

    methods (Static, Access = private)
        function s = shares(counts)
            %SHARES Normalise bin counts, refusing an empty sample.
            counts = double(counts(:))';
            total = sum(counts);
            if total == 0
                error('drift:DriftMonitor:emptySample', ...
                    'Cannot compute shares for an empty sample.');
            end
            s = counts / total;
        end

        function value = psiFromShares(expected, actual)
            %PSIFROMSHARES Epsilon-floored PSI sum over matching bins.
            expectedSafe = max(expected, drift.DriftMonitor.Epsilon);
            actualSafe = max(actual, drift.DriftMonitor.Epsilon);
            value = sum((actualSafe - expectedSafe) .* log(actualSafe ./ expectedSafe));
        end

        function tf = isNumericColumn(column)
            %ISNUMERICCOLUMN True for numeric or logical data.
            tf = isnumeric(column) || islogical(column);
        end

        function levels = asLevels(column)
            %ASLEVELS Normalise any categorical-ish column to a string column.
            if iscategorical(column)
                levels = string(column(:));
            elseif isstring(column)
                levels = column(:);
            elseif ischar(column)
                levels = string(cellstr(column));
            elseif iscellstr(column) %#ok<ISCLSTR>
                levels = string(column(:));
            else
                levels = string(column(:));
            end
            levels = levels(:);
        end
    end
end
