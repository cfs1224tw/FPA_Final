%% =========================================================
% fp_debug_signal_at_timepoint.m
%
% Inspect signal near a target time point (e.g. t = 3.5 s)
% using fp_load_tdt_eventlocked_filter()
%
% Tony final debug version
%% =========================================================
clear; clc; close all;

%% ---------------- USER SETTINGS ----------------
targetTime   = 3.5;      % target time to inspect
halfWindow   = 0.30;     % show +/- 0.30 s around target
avgWindow    = 0.10;     % average over +/- 0.10 s around target for summary
outcomeName  = 'Hit';    % only labeling purpose here

% ---- FP loading params ----
EPOC_RANGE       = [-2 10];
t_discard        = 5;
DoDFF            = true;
BaqScalingType   = 'OLS';        % 'OLS' or 'IRLS'
FilterType       = 'nofilter';   % 'nofilter','highpass','lowpass','bandpass'
FilterOrder      = 3;
HighpassCutoff   = 0.0051;
LowpassCutoff    = 2.2860;
Padding          = true;
PaddingPerc      = 0.1;

% ---- two animals to compare ----
animals(1).AnimalID = 'FX_737';
animals(1).TankPath = '/Users/foxking/Desktop/FP_Project/AnimalData/FX_737/AUX/CleanOnly/737-250320-150419';

animals(2).AnimalID = 'FX_895';
animals(2).TankPath = '/Users/foxking/Desktop/FP_Project/AnimalData/FX_895/AUX/CleanOnly/895-250827-151656';

%% ---------------- LOAD DATA ----------------
nAnimals = numel(animals);

allTrialValuesAtTarget = [];
allTrialAnimalLabel    = [];
allAnimalMeans         = [];
allAnimalTrialCounts   = zeros(nAnimals,1);

for i = 1:nAnimals
    fprintf('\n=================================================\n');
    fprintf('Loading %s\n', animals(i).AnimalID);
    fprintf('=================================================\n');

    meta = struct();
    meta.AnimalID  = animals(i).AnimalID;
    meta.GroupName = animals(i).AnimalID;

    [z_eventlocked, t, out] = fp_load_tdt_eventlocked_filter( ...
        animals(i).TankPath, meta, ...
        'EPOC_RANGE',      EPOC_RANGE, ...
        't_discard',       t_discard, ...
        'DoDFF',           DoDFF, ...
        'BaqScalingType',  BaqScalingType, ...
        'FilterType',      FilterType, ...
        'FilterOrder',     FilterOrder, ...
        'HighpassCutoff',  HighpassCutoff, ...
        'LowpassCutoff',   LowpassCutoff, ...
        'Padding',         Padding, ...
        'PaddingPerc',     PaddingPerc);

    animals(i).z    = z_eventlocked;   % [nTrial x nTime]
    animals(i).t    = t;
    animals(i).out  = out;
    animals(i).meanTrace = mean(z_eventlocked, 1, 'omitnan');
    animals(i).semTrace  = std(z_eventlocked, 0, 1, 'omitnan') ./ sqrt(size(z_eventlocked,1));

    allAnimalTrialCounts(i) = size(z_eventlocked,1);

    % ---- indices around target ----
    idxTarget = findClosestIndex(t, targetTime);
    idxPlot   = t >= (targetTime-halfWindow) & t <= (targetTime+halfWindow);
    idxAvg    = t >= (targetTime-avgWindow)  & t <= (targetTime+avgWindow);

    animals(i).idxTarget = idxTarget;
    animals(i).idxPlot   = idxPlot;
    animals(i).idxAvg    = idxAvg;

    % ---- value exactly at target nearest sample ----
    animals(i).trialValueAtTarget = z_eventlocked(:, idxTarget);

    % ---- local mean around target ----
    animals(i).trialValueLocalMean = mean(z_eventlocked(:, idxAvg), 2, 'omitnan');

    % ---- summary ----
    animals(i).meanAtTarget      = mean(animals(i).trialValueAtTarget, 'omitnan');
    animals(i).stdAtTarget       = std(animals(i).trialValueAtTarget, 0, 'omitnan');
    animals(i).semAtTarget       = animals(i).stdAtTarget / sqrt(numel(animals(i).trialValueAtTarget));

    animals(i).meanLocalMean     = mean(animals(i).trialValueLocalMean, 'omitnan');
    animals(i).stdLocalMean      = std(animals(i).trialValueLocalMean, 0, 'omitnan');
    animals(i).semLocalMean      = animals(i).stdLocalMean / sqrt(numel(animals(i).trialValueLocalMean));

    allTrialValuesAtTarget = [allTrialValuesAtTarget; animals(i).trialValueLocalMean];
    allTrialAnimalLabel    = [allTrialAnimalLabel; i*ones(numel(animals(i).trialValueLocalMean),1)];
    allAnimalMeans         = [allAnimalMeans; animals(i).meanTrace];

    fprintf('Animal: %s\n', animals(i).AnimalID);
    fprintf('nTrials = %d\n', size(z_eventlocked,1));
    fprintf('Nearest sample to t=%.3f s is t=%.6f s\n', targetTime, t(idxTarget));
    fprintf('At target sample: mean = %.4f, std = %.4f, sem = %.4f\n', ...
        animals(i).meanAtTarget, animals(i).stdAtTarget, animals(i).semAtTarget);
    fprintf('Local mean (+/- %.3f s): mean = %.4f, std = %.4f, sem = %.4f\n', ...
        avgWindow, animals(i).meanLocalMean, animals(i).stdLocalMean, animals(i).semLocalMean);
end

%% ---------------- GROUP SUMMARY ----------------
% trial-level pooled SEM
pooledMean_trialLevel = mean(allTrialValuesAtTarget, 'omitnan');
pooledStd_trialLevel  = std(allTrialValuesAtTarget, 0, 'omitnan');
pooledSEM_trialLevel  = pooledStd_trialLevel / sqrt(numel(allTrialValuesAtTarget));

% animal-level SEM
animalLevelValues = zeros(nAnimals,1);
for i = 1:nAnimals
    animalLevelValues(i) = animals(i).meanLocalMean;
end

pooledMean_animalLevel = mean(animalLevelValues, 'omitnan');
pooledStd_animalLevel  = std(animalLevelValues, 0, 'omitnan');
pooledSEM_animalLevel  = pooledStd_animalLevel / sqrt(numel(animalLevelValues));

fprintf('\n=================================================\n');
fprintf('GROUP SUMMARY around t = %.3f s\n', targetTime);
fprintf('=================================================\n');
fprintf('Trial-level pooled:  mean = %.4f, std = %.4f, sem = %.4f, n = %d trials\n', ...
    pooledMean_trialLevel, pooledStd_trialLevel, pooledSEM_trialLevel, numel(allTrialValuesAtTarget));
fprintf('Animal-level pooled: mean = %.4f, std = %.4f, sem = %.4f, n = %d animals\n', ...
    pooledMean_animalLevel, pooledStd_animalLevel, pooledSEM_animalLevel, numel(animalLevelValues));

%% ---------------- FIGURE 1: all trials around target ----------------
figure('Name','All trials around target','Color','w','Position',[100 100 1400 500]);

for i = 1:nAnimals
    subplot(1,nAnimals,i); hold on;

    zPlot = animals(i).z(:, animals(i).idxPlot);
    tPlot = animals(i).t(animals(i).idxPlot);

    for tr = 1:size(zPlot,1)
        plot(tPlot, zPlot(tr,:), 'LineWidth', 0.8);
    end

    plot(tPlot, animals(i).meanTrace(animals(i).idxPlot), 'k', 'LineWidth', 2.5);
    xline(targetTime, '--k', 'LineWidth', 1.2);

    xlabel('Time (s)');
    ylabel('z');
    title(sprintf('%s | all %s trials', animals(i).AnimalID, outcomeName), 'Interpreter','none');
    grid on;
end

%% ---------------- FIGURE 2: animal mean traces around target ----------------
figure('Name','Animal mean traces around target','Color','w','Position',[100 100 900 600]); hold on;

for i = 1:nAnimals
    tPlot = animals(i).t(animals(i).idxPlot);
    mPlot = animals(i).meanTrace(animals(i).idxPlot);

    plot(tPlot, mPlot, 'LineWidth', 2.5, 'DisplayName', animals(i).AnimalID);
end

xline(targetTime, '--k', 'LineWidth', 1.2, 'DisplayName', 'target');
xlabel('Time (s)');
ylabel('Mean z');
title(sprintf('Animal mean traces near t = %.2f s', targetTime));
legend('Location','best');
grid on;

%% ---------------- FIGURE 3: mean ± SEM around target for each animal ----------------
figure('Name','Animal mean SEM near target','Color','w','Position',[100 100 900 600]); hold on;

for i = 1:nAnimals
    tPlot   = animals(i).t(animals(i).idxPlot);
    meanP   = animals(i).meanTrace(animals(i).idxPlot);
    semP    = animals(i).semTrace(animals(i).idxPlot);

    fill([tPlot fliplr(tPlot)], ...
         [meanP+semP fliplr(meanP-semP)], ...
         [0.7 0.7 0.7], ...
         'FaceAlpha', 0.25, 'EdgeColor', 'none');

    plot(tPlot, meanP, 'LineWidth', 2.5, 'DisplayName', animals(i).AnimalID);
end

xline(targetTime, '--k', 'LineWidth', 1.2);
xlabel('Time (s)');
ylabel('Mean z \pm SEM');
title(sprintf('Animal mean \\pm SEM near t = %.2f s', targetTime));
legend('Location','best');
grid on;

%% ---------------- FIGURE 4: trial distribution at target ----------------
figure('Name','Trial distribution at target','Color','w','Position',[100 100 900 600]); hold on;

xBase = 1:nAnimals;

for i = 1:nAnimals
    y = animals(i).trialValueLocalMean;
    x = xBase(i) + 0.08*(rand(size(y)) - 0.5);

    scatter(x, y, 45, 'filled', 'MarkerFaceAlpha', 0.65);
    plot([xBase(i)-0.15 xBase(i)+0.15], ...
         [animals(i).meanLocalMean animals(i).meanLocalMean], ...
         'k-', 'LineWidth', 3);
end

xlim([0.5 nAnimals+0.5]);
set(gca, 'XTick', xBase, 'XTickLabel', {animals.AnimalID});
ylabel(sprintf('Local mean z around %.2f s', targetTime));
title(sprintf('Trial-level values around t = %.2f s (\\pm %.2f s)', targetTime, avgWindow));
grid on;

%% ---------------- FIGURE 5: heatmaps around target ----------------
figure('Name','Heatmaps around target','Color','w','Position',[100 100 1400 500]);

for i = 1:nAnimals
    subplot(1,nAnimals,i);

    zPlot = animals(i).z(:, animals(i).idxPlot);
    tPlot = animals(i).t(animals(i).idxPlot);

    imagesc(tPlot, 1:size(zPlot,1), zPlot);
    axis tight;
    set(gca,'YDir','normal');
    xline(targetTime, '--w', 'LineWidth', 1.2);

    xlabel('Time (s)');
    ylabel('Trial');
    title(sprintf('%s | heatmap', animals(i).AnimalID), 'Interpreter','none');
    colorbar;
end

%% ---------------- FIGURE 6: pooled group comparison summary ----------------
figure('Name','Pooled summary at target','Color','w','Position',[100 100 800 550]); hold on;

scatter(allTrialAnimalLabel, allTrialValuesAtTarget, 45, 'filled', 'MarkerFaceAlpha', 0.65);

for i = 1:nAnimals
    plot([i-0.18 i+0.18], [animals(i).meanLocalMean animals(i).meanLocalMean], ...
        'k-', 'LineWidth', 3);
end

plot([nAnimals+0.8 nAnimals+1.2], [pooledMean_trialLevel pooledMean_trialLevel], ...
    'r-', 'LineWidth', 3);
plot([nAnimals+1.8 nAnimals+2.2], [pooledMean_animalLevel pooledMean_animalLevel], ...
    'b-', 'LineWidth', 3);

set(gca, 'XTick', [1:nAnimals, nAnimals+1, nAnimals+2], ...
         'XTickLabel', [ {animals.AnimalID}, {'trial pooled'}, {'animal pooled'} ]);

ylabel(sprintf('Local mean z around %.2f s', targetTime));
title('Trial-level vs animal-level pooling');
grid on;
xlim([0.5 nAnimals+2.5]);

%% ---------------- OPTIONAL: print per-animal ranking ----------------
fprintf('\n=================================================\n');
fprintf('PER-ANIMAL local mean ranking near t = %.3f s\n', targetTime);
fprintf('=================================================\n');

for i = 1:nAnimals
    fprintf('%s : %.4f\n', animals(i).AnimalID, animals(i).meanLocalMean);
end

%% ---------------- HELPER FUNCTION ----------------
function idx = findClosestIndex(t, targetTime)
    [~, idx] = min(abs(t - targetTime));
end
