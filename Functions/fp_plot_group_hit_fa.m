function fp_plot_group_hit_fa(groupSubs, titleStr)
% FP_PLOT_GROUP_HIT_FA
%   For a given Genotype×Region×BlockType group (array of sub),
%   plot group-level mean±SEM traces for:
%       - All trials
%       - Hit trials
%       - FA trials
%
% Usage:
%   [allSubs, byGroup] = fp_collect_all_sub;
%   fp_plot_group_hit_fa(byGroup.WT_AUX_CleanOnly, ...
%       'WT AUX CleanOnly — All / Hit / FA');

    if nargin < 1 || isempty(groupSubs)
        error('fp_plot_group_hit_fa: groupSubs is required.');
    end
    if nargin < 2 || isempty(titleStr)
        titleStr = 'Group Hit / FA — All / Hit / FA';
    end

    % Ensure a column-vector session list.
    groupSubs = groupSubs(:);
    nSess     = numel(groupSubs);

    % ---- Check required time / traces fields ----
    if ~isfield(groupSubs(1), 'time') || ~isfield(groupSubs(1), 'traces')
        error('sub struct missing .time or .traces.');
    end

    % Use the first session time axis as the reference time base.
    t = groupSubs(1).time.t(:)';   % 1 x nTime
    nTime = numel(t);

    % ---- Collect session-level mean traces for All / Hit / FA ----
    [all_mean, all_sem, nSessAll] = collect_group_trace(groupSubs, 'All', nTime);
    [hit_mean, hit_sem, nSessHit] = collect_group_trace(groupSubs, 'Hit', nTime);
    [fa_mean,  fa_sem,  nSessFA ] = collect_group_trace(groupSubs, 'FA',  nTime);

    % ---- Plot ----
    figure; hold on;
    set(gcf, 'Color', 'w');

    % All
    if nSessAll > 0
        [hAll, hAllPatch] = plot_with_sem(t, all_mean, all_sem);
        hAll.DisplayName = sprintf('All (n=%d)', nSessAll);
    end

    % Hit
    if nSessHit > 0
        [hHit, hHitPatch] = plot_with_sem(t, hit_mean, hit_sem);
        hHit.DisplayName = sprintf('Hit (n=%d)', nSessHit);
    end

    % FA
    if nSessFA > 0
        [hFA, hFAPatch] = plot_with_sem(t, fa_mean, fa_sem);
        hFA.DisplayName = sprintf('FA (n=%d)', nSessFA);
    end

    % Use MATLAB's default color order automatically.
    xlabel('Time (s)');
    ylabel('z (session mean, baseline-centered)');
    title(titleStr, 'Interpreter', 'none');
    grid on;
    legend('Location','best');
end

% =====================================================================
% Helper: collect group-level mean / SEM
% =====================================================================
function [grpMean, grpSEM, nValidSess] = collect_group_trace(groupSubs, fieldName, nTime)
    nSess = numel(groupSubs);
    X = nan(nSess, nTime);  % each row stores one session mean trace

    for i = 1:nSess
        s = groupSubs(i);
        if ~isfield(s, 'traces') || ~isfield(s.traces, fieldName)
            continue;
        end
        tr = s.traces.(fieldName);
        if ~isfield(tr, 'mean') || isempty(tr.mean)
            continue;
        end
        m = tr.mean;
        m = m(:)';  % ensure a row vector

        L = min(numel(m), nTime);
        X(i,1:L) = m(1:L);
    end

    nValidSess = sum(any(~isnan(X),2));
    if nValidSess == 0
        grpMean = nan(1, nTime);
        grpSEM  = nan(1, nTime);
        return;
    end

    grpMean = mean(X, 1, 'omitnan');
    grpSEM  = std(X, 0, 1, 'omitnan') ./ sqrt(sum(~isnan(X),1));
end

% =====================================================================
% Helper: draw mean +- SEM using a shaded patch
% =====================================================================
function [hLine, hPatch] = plot_with_sem(t, meanTrace, semTrace)
    t  = t(:)';
    mu = meanTrace(:)';
    se = semTrace(:)';

    % Skip plotting when the entire trace is NaN.
    if all(isnan(mu))
        hLine  = matlab.graphics.chart.primitive.Line.empty;
        hPatch = matlab.graphics.primitive.Patch.empty;
        return;
    end

    % Plot the mean line first so we can reuse its color.
    hLine = plot(t, mu, 'LineWidth', 2);
    c = get(hLine, 'Color');

    % Draw the SEM shading.
    xPatch = [t, fliplr(t)];
    yPatch = [mu + se, fliplr(mu - se)];

    hPatch = patch(xPatch, yPatch, c, ...
        'FaceAlpha', 0.2, ...
        'EdgeColor', 'none');

    % Keep the mean line above the shaded patch.
    uistack(hLine, 'top');
end
