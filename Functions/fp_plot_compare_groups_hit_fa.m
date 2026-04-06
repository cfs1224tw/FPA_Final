function fp_plot_compare_groups_hit_fa(groupWT, groupFX, titleStr, labelWT, labelFX)
% FP_PLOT_COMPARE_GROUP_HIT_FA
%   Compare WT vs FX (or any two groups) for:
%       - All trials
%       - Hit trials
%       - FA trials
%   using session-level mean traces from sub.traces.(All/Hit/FA).mean
%
% Usage:
%   [allSubs, byGroup] = fp_collect_all_sub;
%   fp_plot_compare_groups_hit_fa( ...
%       byGroup.WT_AUX_CleanOnly, ...
%       byGroup.FX_AUX_CleanOnly, ...
%       'AUX CleanOnly — WT vs FX (All / Hit / FA)', ...
%       'WT', 'FX');

    if nargin < 3 || isempty(titleStr)
        titleStr = 'WT vs FX — All / Hit / FA';
    end
    if nargin < 4 || isempty(labelWT)
        labelWT = 'WT';
    end
    if nargin < 5 || isempty(labelFX)
        labelFX = 'FX';
    end

    % ---- Safety: convert both inputs to column vectors ----
    groupWT = groupWT(:);
    groupFX = groupFX(:);

    if isempty(groupWT) || isempty(groupFX)
        error('Both groupWT and groupFX must be non-empty arrays of sub.');
    end

    % ---- Use the time axis from the first WT session ----
    if ~isfield(groupWT(1), 'time') || ~isfield(groupWT(1).time, 't')
        error('sub.time.t is missing in groupWT(1).');
    end
    t = groupWT(1).time.t(:)';    % 1 x nTime
    nTime = numel(t);

    % ---- Collect group-level All / Hit / FA for WT ----
    [WT_All_mean, WT_All_sem, nWT_All] = collect_group_trace(groupWT, 'All', nTime);
    [WT_Hit_mean, WT_Hit_sem, nWT_Hit] = collect_group_trace(groupWT, 'Hit', nTime);
    [WT_FA_mean,  WT_FA_sem,  nWT_FA ] = collect_group_trace(groupWT, 'FA',  nTime);

    % ---- Collect group-level All / Hit / FA for FX ----
    [FX_All_mean, FX_All_sem, nFX_All] = collect_group_trace(groupFX, 'All', nTime);
    [FX_Hit_mean, FX_Hit_sem, nFX_Hit] = collect_group_trace(groupFX, 'Hit', nTime);
    [FX_FA_mean,  FX_FA_sem,  nFX_FA ] = collect_group_trace(groupFX, 'FA',  nTime);

    % ---- Set up the figure ----
    figure; hold on;
    set(gcf, 'Color', 'w');

    % Define the two base colors (WT / FX).
    cWT = [0 0.4470 0.7410];      % MATLAB default blue
    cFX = [0.8500 0.3250 0.0980]; % MATLAB default red

    % ========= Plot WT =========
    h = struct();

    if nWT_All > 0
        [h.WT_All_line, h.WT_All_patch] = plot_with_sem_style( ...
            t, WT_All_mean, WT_All_sem, cWT, '-', ...
            sprintf('%s All (n=%d)', labelWT, nWT_All));
    end

    if nWT_Hit > 0
        [h.WT_Hit_line, h.WT_Hit_patch] = plot_with_sem_style( ...
            t, WT_Hit_mean, WT_Hit_sem, cWT, '--', ...
            sprintf('%s Hit (n=%d)', labelWT, nWT_Hit));
    end

    if nWT_FA > 0
        [h.WT_FA_line, h.WT_FA_patch] = plot_with_sem_style( ...
            t, WT_FA_mean, WT_FA_sem, cWT, ':', ...
            sprintf('%s FA (n=%d)', labelWT, nWT_FA));
    end

    % ========= Plot FX =========
    if nFX_All > 0
        [h.FX_All_line, h.FX_All_patch] = plot_with_sem_style( ...
            t, FX_All_mean, FX_All_sem, cFX, '-', ...
            sprintf('%s All (n=%d)', labelFX, nFX_All));
    end

    if nFX_Hit > 0
        [h.FX_Hit_line, h.FX_Hit_patch] = plot_with_sem_style( ...
            t, FX_Hit_mean, FX_Hit_sem, cFX, '--', ...
            sprintf('%s Hit (n=%d)', labelFX, nFX_Hit));
    end

    if nFX_FA > 0
        [h.FX_FA_line, h.FX_FA_patch] = plot_with_sem_style( ...
            t, FX_FA_mean, FX_FA_sem, cFX, ':', ...
            sprintf('%s FA (n=%d)', labelFX, nFX_FA));
    end

    % ========= Axis / legend =========
    xlabel('Time (s)');
    ylabel('z (session mean, baseline-centered)');
    title(titleStr, 'Interpreter','none');
    grid on;

    % Collect non-empty line handles for the legend.
    legendHandles = findobj(gca, 'Type','Line');
    legend(legendHandles(end:-1:1), 'Location','best'); % reverse so order roughly = plot order
end

% =====================================================================
% Helper: collect group-level mean / SEM
%   Each session contributes one mean trace, then we compute mean / SEM across sessions.
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
% Helper: draw mean +- SEM with a specified color and line style
% =====================================================================
function [hLine, hPatch] = plot_with_sem_style(t, meanTrace, semTrace, color, lineStyle, labelStr)
    t  = t(:)';
    mu = meanTrace(:)';
    se = semTrace(:)';

    % Skip plotting when the entire trace is NaN.
    if all(isnan(mu))
        hLine  = matlab.graphics.chart.primitive.Line.empty;
        hPatch = matlab.graphics.primitive.Patch.empty;
        return;
    end

    % Draw the SEM shading first.
    xPatch = [t, fliplr(t)];
    yPatch = [mu + se, fliplr(mu - se)];

    hPatch = patch(xPatch, yPatch, color, ...
        'FaceAlpha', 0.15, ...
        'EdgeColor', 'none', ...
        'HandleVisibility','off');   % keep the shaded patch out of the legend

    % Draw the mean line.
    hLine = plot(t, mu, ...
        'LineWidth', 2, ...
        'Color', color, ...
        'LineStyle', lineStyle, ...
        'DisplayName', labelStr);

    % Keep the mean line above the shaded patch.
    uistack(hLine, 'top');
end
