classdef DriftMonitorTest < matlab.unittest.TestCase
    %DRIFTMONITORTEST Edge cases and fixture parity for drift.DriftMonitor.
    %
    %   Run from the project root:
    %       >> results = runtests('tests');

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(projectRoot));
        end
    end

    methods (Test)

        % --- verdict thresholds ------------------------------------------

        function verdictBoundariesAreInclusiveBelow(testCase)
            % stable below 0.1, watch from 0.1, shift from 0.25.
            v = drift.DriftMonitor.verdictFor([0; 0.0999; 0.1; 0.2499; 0.25; 1.5]);
            testCase.verifyEqual(v, ...
                ["stable"; "stable"; "watch"; "watch"; "shift"; "shift"]);
        end

        % --- identical input ---------------------------------------------

        function identicalTablesScoreZero(testCase)
            t = DriftMonitorTest.sampleTable(500, 0);
            result = DriftMonitorTest.scoreTables(t, t);
            testCase.verifyLessThan(max(result.psi), 1e-12);
            testCase.verifyTrue(all(result.verdict == "stable"));
        end

        % --- empty bins ---------------------------------------------------

        function emptyBinsGiveLargeFiniteValue(testCase)
            % Every current value lands in the lowest reference bin, so the
            % upper bins empty out. Epsilon smoothing must keep this finite.
            reference = table((0:999)', 'VariableNames', {'x'});
            current = table(zeros(500, 1), 'VariableNames', {'x'});

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.verifyTrue(isfinite(result.psi(1)), ...
                'An emptied bin must not produce Inf or NaN.');
            testCase.verifyGreaterThan(result.psi(1), ...
                drift.DriftMonitor.ShiftThreshold);
            testCase.verifyEqual(result.verdict(1), "shift");
        end

        function emptyBinContributionMatchesEpsilonFloor(testCase)
            % A bin holding 10% of the reference and nothing in the current
            % contributes (eps - 0.1) * log(eps / 0.1), about 1.15.
            expectedShare = 0.1;
            eps = drift.DriftMonitor.Epsilon;
            contribution = (eps - expectedShare) * log(eps / expectedShare);
            testCase.verifyGreaterThan(contribution, 1.1);
            testCase.verifyTrue(isfinite(contribution));
        end

        % --- constant columns ----------------------------------------------

        function constantReferenceAndSameCurrentIsZero(testCase)
            reference = table(ones(300, 1) * 7, 'VariableNames', {'x'});
            current = table(ones(200, 1) * 7, 'VariableNames', {'x'});
            result = DriftMonitorTest.scoreTables(reference, current);
            testCase.verifyEqual(result.psi(1), 0);
            testCase.verifyEqual(result.verdict(1), "stable");
        end

        function constantReferenceAndMovedCurrentIsFlagged(testCase)
            % Half the current sample left the single reference value, so the
            % degenerate branch reports abs(1 - 0.5).
            reference = table(ones(300, 1) * 7, 'VariableNames', {'x'});
            current = table([ones(100, 1) * 7; ones(100, 1) * 9], ...
                'VariableNames', {'x'});
            result = DriftMonitorTest.scoreTables(reference, current);
            testCase.verifyEqual(result.psi(1), 0.5, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.verdict(1), "shift");
        end

        function constantColumnDoesNotErrorInsideAWiderTable(testCase)
            t = DriftMonitorTest.sampleTable(400, 0);
            t.flat = ones(height(t), 1);
            result = DriftMonitorTest.scoreTables(t, t);
            testCase.verifyEqual(height(result), width(t));
            testCase.verifyTrue(all(isfinite(result.psi)));
        end

        % --- missing values --------------------------------------------------

        function missingNumericValuesAreIgnoredNotPropagated(testCase)
            rng(11, 'twister');
            reference = table(randn(600, 1), 'VariableNames', {'x'});
            current = reference;
            current.x(1:60) = NaN;

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.verifyTrue(isfinite(result.psi(1)), ...
                'NaN in the current sample must not make PSI NaN.');
            testCase.verifyLessThan(result.psi(1), ...
                drift.DriftMonitor.WatchThreshold);
        end

        function missingValuesInReferenceStillProduceUsableEdges(testCase)
            rng(12, 'twister');
            reference = table(randn(600, 1), 'VariableNames', {'x'});
            reference.x(1:60) = NaN;
            current = table(randn(600, 1), 'VariableNames', {'x'});

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.verifyTrue(isfinite(result.psi(1)));
        end

        function missingCategoricalValuesAreExcluded(testCase)
            reference = table(repmat(["a"; "b"], 100, 1), 'VariableNames', {'g'});
            current = reference;
            current.g(1:20) = missing;

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.verifyTrue(isfinite(result.psi(1)));
            testCase.verifyLessThan(result.psi(1), ...
                drift.DriftMonitor.WatchThreshold);
        end

        % --- categorical handling ---------------------------------------------

        function unseenCategoryIsCountedNotDropped(testCase)
            reference = table(repmat(["a"; "b"], 250, 1), 'VariableNames', {'g'});
            current = table([repmat("a", 250, 1); repmat("zzz_new", 250, 1)], ...
                'VariableNames', {'g'});

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.verifyTrue(isfinite(result.psi(1)), ...
                'An unseen level must contribute a finite amount.');
            testCase.verifyGreaterThan(result.psi(1), ...
                drift.DriftMonitor.ShiftThreshold);
        end

        function categoricalAndStringColumnsAgree(testCase)
            levels = repmat(["a"; "b"; "c"], 100, 1);
            asString = table(levels, 'VariableNames', {'g'});
            asCategorical = table(categorical(levels), 'VariableNames', {'g'});

            shifted = table([repmat("a", 200, 1); repmat("b", 100, 1)], ...
                'VariableNames', {'g'});
            shiftedCat = table(categorical(shifted.g), 'VariableNames', {'g'});

            fromString = DriftMonitorTest.scoreTables(asString, shifted);
            fromCategorical = DriftMonitorTest.scoreTables(asCategorical, shiftedCat);

            testCase.verifyEqual(fromCategorical.psi(1), fromString.psi(1), ...
                'AbsTol', 1e-12);
        end

        % --- input validation --------------------------------------------------

        function emptyReferenceIsRejected(testCase)
            empty = table(zeros(0, 1), 'VariableNames', {'x'});
            current = table((1:10)', 'VariableNames', {'x'});
            testCase.verifyError(@() DriftMonitorTest.scoreTables(empty, current), ...
                'drift:DriftMonitor:emptyReference');
        end

        function emptyCurrentIsRejected(testCase)
            reference = table((1:10)', 'VariableNames', {'x'});
            empty = table(zeros(0, 1), 'VariableNames', {'x'});
            testCase.verifyError(@() DriftMonitorTest.scoreTables(reference, empty), ...
                'drift:DriftMonitor:emptyCurrent');
        end

        function scoringBeforeFittingIsRejected(testCase)
            current = table((1:10)', 'VariableNames', {'x'});
            unfitted = drift.DriftMonitor();
            testCase.verifyError(@() unfitted.score(current), ...
                'drift:DriftMonitor:notFitted');
        end

        function missingColumnInCurrentIsRejected(testCase)
            reference = table((1:10)', (1:10)', 'VariableNames', {'x', 'y'});
            current = table((1:10)', 'VariableNames', {'x'});
            monitor = drift.DriftMonitor();
            monitor = monitor.fit(reference);
            testCase.verifyError(@() monitor.score(current), ...
                'drift:DriftMonitor:unknownFeature');
        end

        % --- quantile rule ---------------------------------------------------

        function quantileUsesTheLinearInterpolationRule(testCase)
            % Hand-checked against the NumPy "linear" convention: for
            % x = 1..5 the median is 3 and the 0.25 quantile is 2.
            x = (1:5)';
            q = drift.DriftMonitor.quantileLinear(x, [0 0.25 0.5 0.75 1]);
            testCase.verifyEqual(q(:)', [1 2 3 4 5], 'AbsTol', 1e-12);
        end

        function quantileInterpolatesBetweenOrderStatistics(testCase)
            % x = [0 1], p = 0.3 sits 30% of the way from 0 to 1.
            q = drift.DriftMonitor.quantileLinear([0; 1], 0.3);
            testCase.verifyEqual(q, 0.3, 'AbsTol', 1e-12);
        end

        function outerEdgesAreOpened(testCase)
            edges = drift.DriftMonitor.numericEdges((1:100)', 10);
            testCase.verifyEqual(edges(1), -Inf);
            testCase.verifyEqual(edges(end), Inf);
            testCase.verifyTrue(all(diff(edges) > 0), ...
                'Bin edges must be strictly increasing.');
        end

        function valuesBeyondTheReferenceRangeStillFallInABin(testCase)
            reference = table((1:100)', 'VariableNames', {'x'});
            current = table([-500; 500; (1:98)'], 'VariableNames', {'x'});
            result = DriftMonitorTest.scoreTables(reference, current);
            testCase.verifyTrue(isfinite(result.psi(1)));
        end

        % --- parity against the Python values on the committed fixture ---------

        function fixtureMatchesPythonPsi(testCase)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            reference = loadSnapshot(fullfile(projectRoot, 'data', 'fixture_reference.csv'));
            current = loadSnapshot(fullfile(projectRoot, 'data', 'fixture_current.csv'));
            expected = readtable(fullfile(projectRoot, 'data', 'expected_psi_fixture.csv'), ...
                'TextType', 'string', 'VariableNamingRule', 'preserve');

            result = DriftMonitorTest.scoreTables(reference, current);

            testCase.assertEqual(height(result), height(expected), ...
                'Fixture and expected-value file disagree on the feature count.');

            worst = 0;
            for i = 1:height(result)
                row = expected(expected.feature == result.feature(i), :);
                testCase.assertNotEmpty(row, ...
                    sprintf('No Python value for feature %s.', result.feature(i)));
                worst = max(worst, abs(result.psi(i) - row.python_psi(1)));
            end

            fprintf('\n  fixture parity: largest absolute difference %.3e over %d features\n', ...
                worst, height(result));
            testCase.verifyLessThan(worst, 1e-9, ...
                'MATLAB and Python PSI disagree by more than floating-point noise.');
        end
    end

    methods (Static)
        function result = scoreTables(reference, current)
            %SCORETABLES Fit on one table and score another.
            %
            %   A named helper rather than drift.DriftMonitor().fitScore(...):
            %   MATLAB does not allow indexing into the result of a function
            %   call, so the constructor result needs a variable first.
            monitor = drift.DriftMonitor();
            result = monitor.fitScore(reference, current);
        end

        function t = sampleTable(n, shift)
            %SAMPLETABLE A small feature-like table for the generic cases.
            rng(7 + round(shift * 100), 'twister');
            t = table( ...
                DriftMonitorTest.poissonSample(4.5 * (1 + shift), n), ...
                -5 * (1 + shift) * log(rand(n, 1)), ...
                'VariableNames', {'n_total_7d', 'recency_days'});
            t.industry = DriftMonitorTest.pickLevels( ...
                ["saas", "retail", "finance"], [0.5 0.3 0.2], n);
        end

        function k = poissonSample(lambda, n)
            %POISSONSAMPLE Poisson draws using only base MATLAB.
            %
            %   Knuth's product-of-uniforms method. POISSRND belongs to
            %   Statistics and Machine Learning Toolbox, which this project
            %   does not depend on.
            threshold = exp(-lambda);
            k = zeros(n, 1);
            p = rand(n, 1);
            active = p > threshold;
            while any(active)
                k(active) = k(active) + 1;
                p(active) = p(active) .* rand(nnz(active), 1);
                active = p > threshold;
            end
        end

        function s = pickLevels(levels, probabilities, n)
            %PICKLEVELS Weighted categorical draws using only base MATLAB.
            %
            %   RANDSAMPLE and DATASAMPLE belong to Statistics and Machine
            %   Learning Toolbox.
            cumulative = [0, cumsum(probabilities(:)')];
            cumulative(end) = 1;
            idx = discretize(rand(n, 1), cumulative);
            s = levels(idx);
            s = s(:);
        end
    end
end
