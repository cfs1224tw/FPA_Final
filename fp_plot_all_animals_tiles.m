function fp_plot_all_animals_tiles(rootDir)
% FP_PLOT_ALL_ANIMALS_TILES
%   Auto-plot FP traces for ALL animals in SessionKey.xlsx.
%
%   For each AnimalID (e.g. 'WT_918'):
%       - Collect all context-based sessions from ctxGroups:
%           WT_AUX_CleanOnly
%           WT_AUX_Aud50_clean / WT_AUX_Aud50_distractor
%           WT_AUX_Vis50_clean / WT_AUX_Vis50_distractor
%           WT_AUX_DistractorOnly (if any)
%           (same for PFC)
%
%       - Produce TWO tiled figures per animal:
%           (1) AUX  — one tile per condition (Hit, FA)
%           (2) PFC  — one tile per condition (Hit, FA)
%
%       - Each tile:
%           X = time (t)
%           Y = z (baseline-centered, aligned at t=0)
%           Hit: solid line (genotype-specific color)
%           FA : solid line (different color from Hit，genotype-specific)
%           + SEM shadow (across sessions)
%           + Title includes: context + Hit/FA % + n trials (from SessionKey if available)
%
%       - Figures are saved to:
%           <rootDir>/Results/Tiles_byAnimal/AUX/<AnimalID>_AUX_tiles.png
%           <rootDir>/Results/Tiles_byAnimal/PFC/<AnimalID>_PFC_tiles.png
%
% Usage:
%   cd('/Users/foxking/Desktop/FP_Project');
%   fp_plot_all_animals_tiles;
%   fp_plot_all_animals_tiles('/some/other/root');

    if nargin < 1 || isempty(rootDir)
        rootDir = '/Users/foxking/Desktop/FP_Project';
    end

    % ----- 1) Read SessionKey.xlsx → AnimalID list -----
    skFile = fullfile(rootDir, 'SessionKey.xlsx');
    if ~isfile(skFile)
        error('SessionKey.xlsx not found at: %s', skFile);
    end

    T = readtable(skFile);

    if ismember('IncludeFlag', T.Properties.VariableNames)
        mask = T.IncludeFlag;
    else
        mask = true(height(T),1);
    end

    if ~ismember('AnimalID', T.Properties.VariableNames)
        error('SessionKey.xlsx must contain column "AnimalID".');
    end

    animalCol = string(T.AnimalID);
    animalIDs = unique(animalCol(mask), 'stable');

    fprintf('Found %d animals in SessionKey (IncludeFlag=1 if present).\n', numel(animalIDs));

    % ----- 2) Collect all sub_*.mat + context groups -----
    [allSubs, ~] = fp_collect_all_sub(rootDir);
    if isempty(allSubs)
        error('No sub_*.mat found. Run fp_run_all_sessions first.');
    end

    [ctxGroups, groupNames] = fp_build_context_groups(allSubs);
    if isempty(groupNames)
        error('No context-based groups found. Check fp_build_context_groups.');
    end

    % ----- 3) Dir -----
    tileRoot = fullfile(rootDir, 'Results', 'Tiles_byAnimal');
    if ~isfolder(tileRoot)
        mkdir(tileRoot);
    end
    auxDir = fullfile(tileRoot, 'AUX');
    pfcDir = fullfile(tileRoot, 'PFC');
    if ~isfolder(auxDir), mkdir(auxDir); end
    if ~isfolder(pfcDir), mkdir(pfcDir); end

    % ----- 4) Loop over animals -----
    for ia = 1:numel(animalIDs)
        thisID = animalIDs(ia);
        fprintf('\n===== Animal %d/%d: %s =====\n', ia, numel(animalIDs), thisID);
        plot_one_animal_tiles(thisID, ctxGroups, groupNames, tileRoot, T);
    end

    fprintf('\nDone plotting all animals.\n');
end

%% ============================================================
%% ================  per-animal plotting core  ================
%% ============================================================
function plot_one_animal_tiles(animalID, ctxGroups, groupNames, tileRoot, SessionKey)
    animalID = string(animalID);

    % ---- collect all conditions (groupKeys) for this animal ----
    condMap = struct();
    for k = 1:numel(groupNames)
        key = groupNames{k};
        sessions = ctxGroups.(key);
        keepIdx = false(1, numel(sessions));

        for i = 1:numel(sessions)
            m = sessions(i).meta;
            idStr = "";
            if isfield(m, 'ID') && ~isempty(m.ID)
                idStr = string(m.ID);
            elseif isfield(m, 'AnimalID') && ~isempty(m.AnimalID)
                idStr = string(m.AnimalID);
            end
            keepIdx(i) = (idStr == animalID);
        end

        if any(keepIdx)
            condMap.(key) = sessions(keepIdx);
        end
    end

    condNames = fieldnames(condMap);
    if isempty(condNames)
        fprintf('  [WARNING] No sessions found for animalID = %s\n', animalID);
        return;
    end

    % ---- sort conditions by Region + Context ----
    sortKeys = zeros(numel(condNames),1);
    for i = 1:numel(condNames)
        key = condNames{i};
        [regionStr, ctxStr] = parse_region_context_from_key(key);
        regW = region_weight(regionStr);
        ctxW = context_weight(ctxStr);
        sortKeys(i) = regW*100 + ctxW;
    end
    [~, idxOrder] = sort(sortKeys);
    condNames = condNames(idxOrder);

    % ---- time reference & genotype-based color ----
    firstKey = condNames{1};
    tRef     = condMap.(firstKey)(1).t;

    m0 = condMap.(firstKey)(1).meta;
    genoStr = "";
    if isfield(m0, 'genotype') && ~isempty(m0.genotype)
        genoStr = string(m0.genotype);
    else
        % fallback from AnimalID prefix
        if startsWith(animalID, "WT")
            genoStr = "WT";
        elseif startsWith(animalID, "FX")
            genoStr = "FX";
        else
            genoStr = "UNK";
        end
    end

    [hitColor, faColor] = get_hit_fa_colors(genoStr);

    defaultXLim = [-2 10];
    defaultYLim = [-1.5 0.5];

    % ---- split by Region: AUX / PFC ----
    regions = ["AUX","PFC"];

    for ir = 1:numel(regions)
        reg = regions(ir);
        condNamesReg = {};
        for i = 1:numel(condNames)
            key = condNames{i};
            [regionStr, ~] = parse_region_context_from_key(key);
            if strcmpi(regionStr, reg)
                condNamesReg{end+1} = key;
            end
        end

        if isempty(condNamesReg)
            fprintf('  Region %s: no conditions for %s\n', reg, animalID);
            continue;
        end

        nCond = numel(condNamesReg);

        % ---- tile layout 2x3 ----
        [nRows, nCols] = best_subplot_layout(nCond);

        figName = sprintf(' %s – %s', animalID, reg);
        fig = figure('Name', figName, ...
                     'Color', 'w', ...
                     'Units', 'normalized', ...
                     'Position', [0.05 0.05 0.9 0.85]);

        tlo = tiledlayout(fig, nRows, nCols, ...
            'TileSpacing', 'compact', ...
            'Padding', 'compact');

        title(tlo, figName, 'Interpreter', 'none');

        for iC = 1:nCond
            key = condNamesReg{iC};
            sessions = condMap.(key);

            [mHit, sHit, mFA, sFA, statsTrial] = aggregate_hit_fa(sessions, tRef);

            [regionStr, ctxStr] = parse_region_context_from_key(key);
            statsSK = lookup_stats_from_sessionkey(SessionKey, animalID, regionStr, ctxStr);

            if ~isempty(statsSK) && statsSK.nTotal > 0
                sUse = statsSK;
            else
                sUse = statsTrial;
            end

            ax = nexttile(tlo, iC);
            hold(ax, 'on');
            box(ax, 'on');
            grid(ax, 'on');
            ax.XLim = defaultXLim;
            ax.YLim = defaultYLim;

            hasPlotted = false;

            % Hit: solid line
            if ~all(isnan(mHit))
                yHit = align_at_t0(tRef, mHit);
                hHit = plot(ax, tRef, yHit, ...
                    'Color', hitColor, ...
                    'LineStyle', '-', ...
                    'LineWidth', 1.5);
                add_sem_patch(ax, tRef, yHit, sHit, hitColor);
                hHit.DisplayName = 'Hit';
                hasPlotted = true;
            end

            % FA: solid line
            if ~all(isnan(mFA))
                yFA = align_at_t0(tRef, mFA);
                hFA = plot(ax, tRef, yFA, ...
                    'Color', faColor, ...
                    'LineStyle', '-', ...
                    'LineWidth', 1.5);
                add_sem_patch(ax, tRef, yFA, sFA, faColor);
                hFA.DisplayName = 'FA';
                hasPlotted = true;
            end

            % Title：Context + Hit/FA % + n trials（From SessionKey）
            if sUse.nTotal > 0
                titleStr = sprintf('%s | Hit %.1f%%, FA %.1f%% (n=%d)', ...
                    ctxStr, sUse.hitPct, sUse.faPct, sUse.nTotal);
            else
                titleStr = sprintf('%s | no Hit/FA trials', ctxStr);
            end
            title(ax, titleStr, 'Interpreter', 'none', 'FontSize', 9);

            if iC > (nRows-1)*nCols
                xlabel(ax, 'Time (s)');
            end
            if mod(iC-1, nCols) == 0
                ylabel(ax, 'z (session)');
            end

            if hasPlotted
                legend(ax, 'Location', 'best', 'Box', 'off');
            end
        end

        % ---- Save AUX / PFC output ----
        safeID = char(animalID);
        regStr = char(reg);

        outRoot = tileRoot;
        outDirReg = fullfile(outRoot, regStr);
        if ~isfolder(outDirReg)
            mkdir(outDirReg);
        end

        outNamePng = sprintf('%s_%s_tiles.png', safeID, regStr);
        outFullPng = fullfile(outDirReg, outNamePng);
        saveas(fig, outFullPng);

        fprintf('  Saved figure: %s\n', outFullPng);

        % close(fig);
    end
end

%% ============================================================
%% ======================== HELPERS ===========================
%% ============================================================

function [mHit, sHit, mFA, sFA, stats] = aggregate_hit_fa(sessions, tRef)
    % For a given condition (one animal, one Region+Context):
    %   1) For each session: compute session-level mean trace (Hit / FA separately)
    %   2) Across sessions: mean ± SEM
    %   Also compute Hit/FA counts and percentages from labels as a fallback.

    nSess = numel(sessions);
    if nSess == 0
        mHit = nan(size(tRef));
        sHit = nan(size(tRef));
        mFA  = nan(size(tRef));
        sFA  = nan(size(tRef));
        stats = struct('nHit',0,'nFA',0,'nTotal',0,'hitPct',NaN,'faPct',NaN);
        return;
    end

    hitSessMean = nan(nSess, numel(tRef));
    faSessMean  = nan(nSess, numel(tRef));

    totalHit = 0;
    totalFA  = 0;

    for i = 1:nSess
        s = sessions(i);
        Z = s.Z;
        L = s.labels;
        nTrial = size(Z,1);

        hitFA = get_str_field(L, 'hitFA', nTrial, "Other");

        % Hit
        maskHit = (hitFA == "Hit");
        if any(maskHit)
            hitSessMean(i,:) = mean(Z(maskHit,:), 1, 'omitnan');
            totalHit = totalHit + sum(maskHit);
        end

        % FA
        maskFA = (hitFA == "FA");
        if any(maskFA)
            faSessMean(i,:) = mean(Z(maskFA,:), 1, 'omitnan');
            totalFA = totalFA + sum(maskFA);
        end
    end

    % Across-session mean ± SEM (Hit)
    validHitRow = ~all(isnan(hitSessMean), 2);
    if any(validHitRow)
        hitSessMean = hitSessMean(validHitRow, :);
        mHit = mean(hitSessMean, 1, 'omitnan');
        sHit = std(hitSessMean, 0, 1, 'omitnan') ./ sqrt(size(hitSessMean,1));
    else
        mHit = nan(size(tRef));
        sHit = nan(size(tRef));
    end

    % Across-session mean ± SEM (FA)
    validFARow = ~all(isnan(faSessMean), 2);
    if any(validFARow)
        faSessMean = faSessMean(validFARow, :);
        mFA = mean(faSessMean, 1, 'omitnan');
        sFA = std(faSessMean, 0, 1, 'omitnan') ./ sqrt(size(faSessMean,1));
    else
        mFA = nan(size(tRef));
        sFA = nan(size(tRef));
    end

    nTotal = totalHit + totalFA;
    if nTotal > 0
        hitPct = 100 * totalHit / nTotal;
        faPct  = 100 * totalFA  / nTotal;
    else
        hitPct = NaN;
        faPct  = NaN;
    end

    stats = struct('nHit',totalHit, 'nFA',totalFA, ...
                   'nTotal',nTotal, 'hitPct',hitPct, 'faPct',faPct);
end

function stats = lookup_stats_from_sessionkey(T, animalID, regionStr, ctxStr)
    % Beh_Pct SessionKey：
    %   HitRate_Clean_Pct, FARate_Clean_Pct, OmissRate_Clean_Pct, nTrials_Clean
    %   HitRate_Dist_Pct,  FARate_Dist_Pct,  OmissRate_Dist_Pct,  nTrials_Dist
    %
    % ctxStr：
    %   "CleanOnly"
    %   "Aud50_clean"
    %   "Aud50_distractor"
    %   "Vis50_clean"
    %   "Vis50_distractor"
    %   "DistractorOnly"

    stats = [];

    animalID  = string(animalID);
    regionStr = string(regionStr);
    ctxStr    = string(ctxStr);

    % ---- ctxStr → BlockType （clean / dist） ----
    blk     = "";
    modeStr = "";   % "clean" or "dist"

    if ctxStr == "CleanOnly"
        blk     = "CleanOnly";
        modeStr = "clean";
    elseif ctxStr == "Aud50_clean"
        blk     = "Aud50";
        modeStr = "clean";
    elseif ctxStr == "Aud50_distractor"
        blk     = "Aud50";
        modeStr = "dist";
    elseif ctxStr == "Vis50_clean"
        blk     = "Vis50";
        modeStr = "clean";
    elseif ctxStr == "Vis50_distractor"
        blk     = "Vis50";
        modeStr = "dist";
    elseif ctxStr == "AudDistractorOnly"
        blk     = "AudDistractorOnly";
        modeStr = "dist";
    elseif ctxStr == "VisDistractorOnly"
        blk     = "VisDistractorOnly";
        modeStr = "dist";
    else
        return;
    end

    % ---- Cols ----
    if ~all(ismember({'AnimalID','Region','BlockType'}, T.Properties.VariableNames))
        return;
    end

    % Per animal + Region + BlockType
    mask = (string(T.AnimalID) == animalID) & ...
           (string(T.Region)   == regionStr) & ...
           (string(T.BlockType)== blk);

    Tsub = T(mask,:);
    if isempty(Tsub)
        return;
    end

    % ---- Find Cols ----
    cleanCols = {'HitRate_Clean_Pct','FARate_Clean_Pct','OmissRate_Clean_Pct','nTrials_Clean'};
    distCols  = {'HitRate_Dist_Pct','FARate_Dist_Pct','OmissRate_Dist_Pct','nTrials_Dist'};

    if ~all(ismember(cleanCols, T.Properties.VariableNames)) || ...
       ~all(ismember(distCols,  T.Properties.VariableNames))
        return;
    end

    % ---- modeStr for Clean or Dist  ----
    switch modeStr
        case "clean"
            hitPctCol   = Tsub.HitRate_Clean_Pct;
            faPctCol    = Tsub.FARate_Clean_Pct;
            omissPctCol = Tsub.OmissRate_Clean_Pct;
            nCol        = Tsub.nTrials_Clean;
        case "dist"
            hitPctCol   = Tsub.HitRate_Dist_Pct;
            faPctCol    = Tsub.FARate_Dist_Pct;
            omissPctCol = Tsub.OmissRate_Dist_Pct;
            nCol        = Tsub.nTrials_Dist;
        otherwise
            return;
    end

    nCol        = double(nCol);
    hitPctCol   = double(hitPctCol);
    faPctCol    = double(faPctCol);
    omissPctCol = double(omissPctCol);

    nTotal = sum(nCol, 'omitnan');

    if nTotal > 0
        % Hit / FA / Omiss Pct
        hitPct   = sum(hitPctCol   .* nCol, 'omitnan') / nTotal;
        faPct    = sum(faPctCol    .* nCol, 'omitnan') / nTotal;
        omissPct = sum(omissPctCol .* nCol, 'omitnan') / nTotal;
    else
        hitPct = NaN;
        faPct  = NaN;
        omissPct = NaN;
    end

    stats = struct('nHit',NaN, 'nFA',NaN, ...
                   'nTotal',nTotal, ...
                   'hitPct',hitPct, ...
                   'faPct',faPct, ...
                   'omissPct',omissPct);
end

function yAligned = align_at_t0(t, y)
    if isempty(t) || isempty(y) || all(isnan(y))
        yAligned = y;
        return;
    end
    [~, idx0] = min(abs(t));
    if isempty(idx0) || isnan(y(idx0))
        yAligned = y;
    else
        yAligned = y - y(idx0);
    end
end

function add_sem_patch(ax, t, yMean, ySem, color)
    if all(isnan(ySem))
        return;
    end
    upper = yMean + ySem;
    lower = yMean - ySem;
    x = [t, fliplr(t)];
    y = [upper, fliplr(lower)];
    p = fill(ax, x, y, color, ...
        'FaceAlpha', 0.15, ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
    uistack(p, 'bottom');
end

function s = get_str_field(labels, fn, nTrial, defaultVal)
    if isfield(labels, fn) && ~isempty(labels.(fn))
        v = labels.(fn);
        if isstring(v)
            s = v(:);
        elseif iscell(v)
            s = string(v(:));
        else
            s = string(v(:));
        end
        if numel(s) ~= nTrial
            s = repmat(string(defaultVal), nTrial, 1);
        end
    else
        s = repmat(string(defaultVal), nTrial, 1);
    end
end

function [regionStr, ctxStr] = parse_region_context_from_key(key)
    % key examples:
    %   'WT_AUX_CleanOnly'
    %   'WT_AUX_Aud50_clean'
    %   'WT_AUX_Aud50_distractor'
    %   'WT_PFC_Vis50_clean'
    key = string(key);
    tokens = split(key, '_');

    regionStr = "";
    ctxStr    = "";

    if numel(tokens) >= 2
        regionStr = tokens(2);
    end

    if numel(tokens) == 3
        ctxStr = tokens(3);
    elseif numel(tokens) >= 4
        ctxStr = tokens(3) + "_" + tokens(4);
    end

    if regionStr == "", regionStr = "Region?"; end
    if ctxStr    == "", ctxStr    = "Context?"; end
end

function w = region_weight(region)
    region = string(region);
    switch upper(region)
        case "AUX"
            w = 1;
        case "PFC"
            w = 2;
        otherwise
            w = 9;
    end
end

function w = context_weight(ctx)
    % ctx examples:
    %   CleanOnly
    %   Aud50_clean, Aud50_distractor
    %   Vis50_clean, Vis50_distractor
    %   DistractorOnly
    ctx = string(ctx);

    if ctx == "CleanOnly"
        w = 10;
    elseif ctx == "Aud50_clean"
        w = 20;
    elseif ctx == "Aud50_distractor"
        w = 21;
    elseif ctx == "Vis50_clean"
        w = 30;
    elseif ctx == "Vis50_distractor"
        w = 31;
    elseif ctx == "AudDistractorOnly"
        w = 40;
    elseif ctx == "VisDistractorOnly"
        w = 41;
    elseif startsWith(ctx, "Aud50")
        w = 22;
    elseif startsWith(ctx, "Vis50")
        w = 32;
    else
        w = 90;
    end
end

function [nRows, nCols] = best_subplot_layout(~)
    % layout：2x3
    nRows = 2;
    nCols = 3;
end

function [hitColor, faColor] = get_hit_fa_colors(genoStr)
    % Hit / FA color
    genoStr = upper(string(genoStr));

    switch genoStr
        case "WT"
            % WT: cool palette
            hitColor = [0 0.25 0.8];    % Blue
            faColor  = [0 0.55 0.2];    % Green
        case "FX"
            % FX: warm palette
            hitColor = [0.85 0.33 0.10]; % Orange
            faColor  = [0.55 0.10 0.60]; % Purple
        otherwise
            % fallback greyscale
            hitColor = [0.2 0.2 0.2];
            faColor  = [0.6 0.6 0.6];
    end
end
