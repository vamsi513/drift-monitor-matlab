classdef DetectorTrialsTest < matlab.unittest.TestCase
    %DETECTORTRIALSTEST Does the PSI detector behave like a detector?
    %
    %   Two questions, each answered by repeated trials rather than a single
    %   draw, because a one-shot assertion on a random sample tells you almost
    %   nothing:
    %
    %     (a) how often does it flag a fresh sample from the same distribution?
    %     (b) how often does it flag a sample that really was shifted?
    %
    %   Both counts are printed by the tests themselves, so the numbers quoted
    %   in the README come from a run rather than an estimate.
    %
    %   The draws mirror tests/test_drift.py in the lead-scoring project, but
    %   MATLAB's random number generator is not NumPy's, so the trials are not
    %   the same trials. Expect the same verdict, not identical counts.

    properties (Constant)
        NumTrials (1,1) double = 100

        % Rows per sample. Comparable to a daily scoring batch, and small
        % enough that PSI has real sampling noise.
        SampleSize (1,1) double = 3000

        Numeric (1,:) string = ["n_total_7d", "n_total_30d", "recency_days", "trend_ratio"]
        Categorical (1,:) string = ["industry", "source"]
    end

    methods (TestClassSetup)
        function addProjectToPath(testCase)
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture( ...
                matlab.unittest.fixtures.PathFixture(projectRoot));
        end
    end

    methods (Test)

        function sameDistributionIsNotFlagged(testCase)
            outcome = DetectorTrialsTest.runTrials(0.0, 2024);

            fprintf(['\n  same distribution: %d/%d flagged ' ...
                     '(mean worst psi %.4f, max %.4f)\n'], ...
                outcome.flagged, outcome.trials, outcome.meanPsi, outcome.maxPsi);

            testCase.verifyEqual(outcome.trials, DetectorTrialsTest.NumTrials);
            testCase.verifyEqual(outcome.flagged, 0, ...
                'An unshifted sample was flagged as drift.');
        end

        function twentyFivePercentShiftIsAlwaysFlagged(testCase)
            outcome = DetectorTrialsTest.runTrials(0.25, 2025);

            fprintf(['\n  25%% shift: %d/%d flagged ' ...
                     '(mean worst psi %.4f, max %.4f)\n'], ...
                outcome.flagged, outcome.trials, outcome.meanPsi, outcome.maxPsi);

            testCase.verifyEqual(outcome.trials, DetectorTrialsTest.NumTrials);
            testCase.verifyEqual(outcome.flagged, DetectorTrialsTest.NumTrials, ...
                'A 25% shift was missed in at least one trial.');
        end

        function fivePercentShiftIsTheHonestCaveat(testCase)
            % Not a pass/fail claim about the detector: a 5% shift is simply
            % below what a 0.25 threshold catches at this sample size. The
            % test records that rather than asserting it away.
            outcome = DetectorTrialsTest.runTrials(0.05, 2026);

            fprintf(['\n  5%% shift: %d/%d flagged ' ...
                     '(mean worst psi %.4f, max %.4f)\n'], ...
                outcome.flagged, outcome.trials, outcome.meanPsi, outcome.maxPsi);

            testCase.verifyEqual(outcome.trials, DetectorTrialsTest.NumTrials);
            testCase.verifyGreaterThan(outcome.meanPsi, 0, ...
                'A real shift should lift PSI above zero even when unflagged.');
        end
    end

    methods (Static)

        function outcome = runTrials(shift, seed)
            %RUNTRIALS Run NumTrials comparisons at a shift; count the flags.
            rng(seed, 'twister');
            n = DetectorTrialsTest.NumTrials;
            worstPerTrial = zeros(n, 1);
            flagged = 0;

            features = [DetectorTrialsTest.Numeric, DetectorTrialsTest.Categorical];
            monitor = drift.DriftMonitor();

            for i = 1:n
                reference = DetectorTrialsTest.draw(DetectorTrialsTest.SampleSize, 0.0);
                current = DetectorTrialsTest.draw(DetectorTrialsTest.SampleSize, shift);

                result = monitor.fitScore(reference, current, features);
                worst = max(result.psi);
                worstPerTrial(i) = worst;
                if worst >= drift.DriftMonitor.ShiftThreshold
                    flagged = flagged + 1;
                end
            end

            outcome = struct( ...
                'flagged', flagged, ...
                'trials', n, ...
                'maxPsi', max(worstPerTrial), ...
                'meanPsi', mean(worstPerTrial));
        end

        function t = draw(n, shift)
            %DRAW A feature-like sample; shift moves every distribution.
            %
            %   The shapes mimic the real feature table: counts are
            %   overdispersed and zero-heavy, recency is long-tailed, the
            %   ratio is centred near one.
            scale = 1.0 + shift;

            t = table( ...
                DetectorTrialsTest.poissonSample(4.5 * scale, n), ...
                DetectorTrialsTest.poissonSample(19.5 * scale, n), ...
                DetectorTrialsTest.exponentialSample(5.0 * scale, n), ...
                DetectorTrialsTest.lognormalSample(0.5 * shift, 0.5, n), ...
                'VariableNames', cellstr(DetectorTrialsTest.Numeric));

            industryP = [0.30 0.20 0.15 0.20 0.15];
            sourceP = [0.22 0.24 0.16 0.26 0.12];
            if shift ~= 0
                % Move mass toward one level by the same proportion.
                industryP = DetectorTrialsTest.movedToward(industryP, 1, shift);
                sourceP = DetectorTrialsTest.movedToward(sourceP, 5, shift);
            end

            t.industry = DetectorTrialsTest.pickLevels( ...
                ["saas", "manufacturing", "healthcare", "retail", "finance"], ...
                industryP, n);
            t.source = DetectorTrialsTest.pickLevels( ...
                ["organic", "paid_search", "webinar", "outbound", "referral"], ...
                sourceP, n);
        end

        function p = movedToward(p, target, shift)
            %MOVEDTOWARD Shift probability mass toward one level.
            goal = zeros(size(p));
            goal(target) = 1.0;
            p = p + shift * (goal - p);
            p = p / sum(p);
        end

        function k = poissonSample(lambda, n)
            %POISSONSAMPLE Poisson draws using only base MATLAB.
            %
            %   Knuth's product-of-uniforms method. POISSRND belongs to
            %   Statistics and Machine Learning Toolbox, which this project
            %   deliberately does not depend on.
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

        function x = exponentialSample(mu, n)
            %EXPONENTIALSAMPLE Exponential draws by inverse transform.
            %
            %   EXPRND belongs to Statistics and Machine Learning Toolbox.
            %   RAND never returns exactly 0, so the log is always finite.
            x = -mu * log(rand(n, 1));
        end

        function x = lognormalSample(mu, sigma, n)
            %LOGNORMALSAMPLE Lognormal draws from a normal.
            %
            %   LOGNRND belongs to Statistics and Machine Learning Toolbox.
            x = exp(mu + sigma * randn(n, 1));
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
