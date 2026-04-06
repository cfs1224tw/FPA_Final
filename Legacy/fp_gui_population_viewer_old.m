function fp_gui_population_viewer(rootDir)
% FP_GUI_POPULATION_VIEWER
% GUI for fiber photometry population viewing (context-based groups).
%
% Group key examples (from fp_build_context_groups):
%   'WT_AUX_CleanOnly'
%   'WT_AUX_Aud50_clean'
%   'WT_AUX_Aud50_distractor'
%   'WT_PFC_Vis50_clean'
%   ...
%
% GUI layout:
%   - Left panel: Group1 / Group2 / Mode / Session list
%   - Top-right: Trace type checkboxes (All / Hit / FA) arranged horizontally
%   - Mid-right: X/Y axis limit controls + Apply button
%   - Center: Main plot axes (mainAx)
%
% Modes:
%   1) Single session
%      - Select one session: plot that session's All/Hit/FA mean traces
%      - Select multiple sessions: plot each session’s mean trace
%        (no across-session SEM)
%        * Each session uses a different shade of the genotype palette
%        * Hit = solid line; FA = dashed line; All = solid line (same color)
%
%   2) Group mean
%      - For sessions selected in Group 1, plot group mean ± SEM
%      - Colors by genotype:
%        * WT = cool color (blue family)
%        * FX = warm color (red/orange family)
%        * Hit = solid line; FA = dashed line with a lighter color
%
%   3) Group 1 vs Group 2
%      - Plot group mean ± SEM for Group 1 and Group 2, comparing All/Hit/FA
%      - Colors by each group’s genotype
%      - If both groups are the same genotype (WT vs WT or FX vs FX):
%        * The distractor-containing group uses an alternate color within the
%          same genotype color family
%
% Special rules:
%   - Default axis limits: XLim = [-1 10], YLim = [-1 0.5]
%   - XLimMode and YLimMode are always 'manual'
%   - Before every Plot, the axes are reset (no overlay from previous plots)
%   - All traces are aligned so that y(t=0) = 0 before plotting (align_at_t0)
%
% Usage:
%   cd('/Users/foxking/Desktop/FP_Project');
%   fp_gui_population_viewer;
%   fp_gui_population_viewer('/some/other/path');

    clc;
    if nargin < 1 || isempty(rootDir)
        rootDir = '/Users/foxking/Desktop/FP_Project';
    end

    % ---------------- 1) Collect sessions and build context groups ----------------
    [allSubs, ~] = fp_collect_all_sub(rootDir);
    if isempty(allSubs)
        error('fp_gui_population_viewer:NoSubs', 'No sessions found.');
    end

    [ctxGroups, groupNames] = fp_build_context_groups(allSubs);
    if isempty(groupNames)
        error('fp_gui_population_viewer:NoContextGroups', ...
            'No context-based groups found.');
    end

    groupNames2 = ['<none>'; groupNames];  % Group2 can be "<none>"

    % Use the first group's first session time vector as the reference time base
    firstKey = groupNames{1};
    tRef = ctxGroups.(firstKey)(1).t;
    defaultXLim = [-1 10];
    defaultYLim = [-1 0.5];

    % ---------------- 2) Build GUI figure and controls ----------------
    fig = figure('Name', 'FP Population Viewer (context-based)', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.05 0.9 0.85]);

    % ---------- Main plot axes ----------
    mainAx = axes('Parent', fig, ...
        'Units', 'normalized', ...
        'Position', [0.31 0.1 0.48 0.8]);
    hold(mainAx, 'on');
    box(mainAx, 'on');
    grid(mainAx, 'on');
    xlabel(mainAx, 'Time (s)');
    ylabel(mainAx, 'z (baseline-centered; aligned at t=0)');
    title(mainAx, 'FP traces');

    % Initialize with default axis limits and force manual mode
    mainAx.XLim = defaultXLim;
    mainAx.YLim = defaultYLim;
    set(mainAx, 'XLimMode', 'manual', 'YLimMode', 'manual');

    % ---------- Top-right: Trace type checkboxes (horizontal) ----------
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.90 0.18 0.04], ...
        'String', 'Trace type', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    cbAll = uicontrol(fig, 'Style', 'checkbox', ...
        'Units', 'normalized', ... 
        'Position', [0.80 0.86 0.06 0.04], ...
        'String', 'All', ...
        'BackgroundColor', 'w', ...
        'Value', 0);   % Typically do not show All by default

    cbHit = uicontrol(fig, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.87 0.86 0.06 0.04], ...
        'String', 'Hit', ...
        'BackgroundColor', 'w', ...
        'Value', 1);   % Default: Hit is most important

    cbFA = uicontrol(fig, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.94 0.86 0.05 0.04], ...
        'String', 'FA', ...
        'BackgroundColor', 'w', ...
        'Value', 1);

    % ---------- Mid-right: Axes settings ----------
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.78 0.18 0.04], ...
        'String', 'Axes limits [Xmin Xmax; Ymin Ymax]', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.74 0.04 0.04], ...
        'String', 'X:', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editXmin = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.84 0.74 0.06 0.04], ...
        'String', '-1', ...
        'BackgroundColor', 'w');

    editXmax = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.91 0.74 0.07 0.04], ...
        'String', '10', ...
        'BackgroundColor', 'w');

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.69 0.04 0.04], ...
        'String', 'Y:', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editYmin = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.84 0.69 0.06 0.04], ...
        'String', '-1', ...
        'BackgroundColor', 'w');

    editYmax = uicontrol(fig, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.91 0.69 0.07 0.04], ...
        'String', '0.5', ...
        'BackgroundColor', 'w');

    btnApplyAxes = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.63 0.18 0.05], ...
        'String', 'Apply Axes', ...
        'Callback', @onApplyAxes);

    % ---------- Bottom-right: Plot / Save ----------
    btnPlot = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.54 0.18 0.06], ...
        'String', 'Plot', ...
        'FontWeight', 'bold', ...
        'Callback', @onPlot);

    btnSave = uicontrol(fig, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.46 0.18 0.06], ...
        'String', 'Save Figure...', ...
        'Callback', @onSaveFigure);

    % ---------- Left panel: Group and Session selection ----------
    % Group 1
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.86 0.25 0.04], ...
        'String', 'Group 1 (Genotype_Region_Context)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupGroup1 = uicontrol(fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.82 0.25 0.04], ...
        'String', groupNames, ...
        'BackgroundColor', 'w', ...
        'Callback', @onGroup1Changed);

    % Sessions in Group 1
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.78 0.25 0.03], ...
        'String', 'Sessions in Group 1', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    listSessions1 = uicontrol(fig, 'Style', 'listbox', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.62 0.25 0.16], ...
        'Max', 2, 'Min', 0, ...
        'BackgroundColor', 'w');

    % Mode: Single / Group mean / Group 1 vs Group 2
    modeBG = uibuttongroup(fig, 'Units', 'normalized', ...
        'Position', [0.02 0.48 0.25 0.12], ...
        'Title', 'Mode', ...
        'BackgroundColor', 'w');

    rbSingle = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.63 0.9 0.3], ...
        'String', 'Single session', ...
        'Tag', 'single', ...
        'BackgroundColor', 'w');

    rbGroupMean = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.33 0.9 0.3], ...
        'String', 'Group mean', ...
        'Tag', 'groupmean', ...
        'BackgroundColor', 'w');

    rbGroup12 = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.03 0.9 0.3], ...
        'String', 'Group 1 vs Group 2', ...
        'Tag', 'group12', ...
        'BackgroundColor', 'w');

    modeBG.SelectedObject = rbSingle;

    % Group 2 (for group comparison)
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.42 0.25 0.03], ...
        'String', 'Group 2 (for comparison)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupGroup2 = uicontrol(fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.38 0.25 0.04], ...
        'String', groupNames2, ...
        'BackgroundColor', 'w');

    % Sessions in Group 2 (reserved for future subset mode; disabled for now)
    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.34 0.25 0.03], ...
        'String', 'Sessions in Group 2 (for subset mode)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    listSessions2 = uicontrol(fig, 'Style', 'listbox', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.22 0.25 0.12], ...
        'Max', 2, 'Min', 0, ...
        'BackgroundColor', 'w', ...
        'Enable', 'off');

    % State: whether axes have been manually set by the user
    manualAxes  = false;
    currentXLim = defaultXLim;
    currentYLim = defaultYLim;

    % Line width settings
    LW.single = 1.5;   % single mode
    LW.group  = 2.0;   % group mean / group1 vs group2

    % Initialize Group 1 session list
    onGroup1Changed();

    % ---------------- Callbacks ----------------
    function onGroup1Changed(~, ~)
        idx = popupGroup1.Value;
        key = groupNames{idx};
        sessions = ctxGroups.(key);

        % Build session labels: ID | date
        labelsOut = cell(numel(sessions), 1);
        for ii = 1:numel(sessions)
            m = sessions(ii).meta;

            id = '';
            if isfield(m, 'ID')
                id = char(string(m.ID));
            end

            dt = '';
            if isfield(m, 'date') && ~isempty(m.date)
                dt = char(string(m.date));
            end

            if ~isempty(dt)
                labelsOut{ii} = sprintf('%s | %s', id, dt);
            else
                labelsOut{ii} = id;
            end
        end

        if isempty(labelsOut)
            labelsOut = {'<no session>'};
        end
        set(listSessions1, 'String', labelsOut, 'Value', 1);
    end

    function onApplyAxes(~, ~)
        xmin = str2double(editXmin.String);
        xmax = str2double(editXmax.String);
        ymin = str2double(editYmin.String);
        ymax = str2double(editYmax.String);

        if isnan(xmin) || isnan(xmax) || isnan(ymin) || isnan(ymax) || xmin >= xmax || ymin >= ymax
            warndlg('Invalid axis limits.', 'Axis');
            return;
        end

        currentXLim = [xmin xmax];
        currentYLim = [ymin ymax];
        manualAxes  = true;

        mainAx.XLim = currentXLim;
        mainAx.YLim = currentYLim;
    end

    function onSaveFigure(~, ~)
        [file, path] = uiputfile({'*.png';'*.pdf';'*.fig'}, 'Save figure as');
        if isequal(file,0)
            return;
        end
        fullpath = fullfile(path, file);
        [~,~,ext] = fileparts(fullpath);
        switch lower(ext)
            case '.png'
                saveas(fig, fullpath);
            case '.pdf'
                saveas(fig, fullpath);
            case '.fig'
                savefig(fig, fullpath);
            otherwise
                saveas(fig, [fullpath '.png']);
        end
    end

    function onPlot(~, ~)
        % Clear the axes before plotting, but keep manual axis limits
        cla(mainAx, 'reset');
        hold(mainAx, 'on');
        box(mainAx, 'on');
        grid(mainAx, 'on');
        xlabel(mainAx, 'Time (s)');
        ylabel(mainAx, 'z (baseline-centered; aligned at t=0)');
        title(mainAx, 'FP traces');

        % Axis limits: use manual values if set; otherwise use defaults
        if manualAxes
            mainAx.XLim = currentXLim;
            mainAx.YLim = currentYLim;
        else
            mainAx.XLim = defaultXLim;
            mainAx.YLim = defaultYLim;
        end
        set(mainAx, 'XLimMode', 'manual', 'YLimMode', 'manual');

        % Trace type toggles
        showAll = logical(cbAll.Value);
        showHit = logical(cbHit.Value);
        showFA  = logical(cbFA.Value);

        if ~showAll && ~showHit && ~showFA
            warndlg('Please select at least one trace type (All/Hit/FA).', 'Trace type');
            return;
        end

        % Mode
        modeTag = modeBG.SelectedObject.Tag;  % 'single' / 'groupmean' / 'group12'

        % Group 1
        idxG1  = popupGroup1.Value;
        keyG1  = groupNames{idxG1};
        sessG1 = ctxGroups.(keyG1);

        % Selected sessions in Group 1
        sessIdx1 = listSessions1.Value;
        if isempty(sessIdx1) || sessIdx1(1) == 0
            sessIdx1 = 1:numel(sessG1);
        end

        legendHandles = [];
        legendLabels  = {};

        switch modeTag
            case 'single'
                % ---- Single session mode ----
                nSessSel = numel(sessIdx1);
                if nSessSel == 0
                    return;
                end

                baseColor = get_base_color_from_key(keyG1);
                cmap = make_genotype_palette(baseColor, nSessSel);

                for jj = 1:nSessSel
                    idxSess = sessIdx1(jj);
                    s = sessG1(idxSess);
                    Z = s.Z;
                    L = s.labels;
                    nTrial = size(Z,1);

                    % Session ID for legend
                    subjID = '';
                    if isfield(s.meta, 'ID') && ~isempty(s.meta.ID)
                        subjID = char(string(s.meta.ID));
                    elseif isfield(s.meta, 'AnimalID') && ~isempty(s.meta.AnimalID)
                        subjID = char(string(s.meta.AnimalID));
                    else
                        subjID = sprintf('Sess%d', idxSess);
                    end

                    thisColor = cmap(jj, :);
                    hitFA = get_str_field(L, 'hitFA', nTrial, "Other");

                    % Show only one legend entry per session (priority: Hit > FA > All)
                    thisLegendHandle = [];

                    % All
                    if showAll
                        mask = true(nTrial,1);
                        if any(mask)
                            mTrace = mean(Z(mask,:), 1, 'omitnan');
                            y = align_at_t0(tRef, mTrace);
                            h = plot(mainAx, tRef, y, ...
                                'Color', thisColor, 'LineStyle', '-', 'LineWidth', LW.single);
                            if isempty(thisLegendHandle)
                                thisLegendHandle = h;
                                legendHandles(end+1) = h; %#ok<AGROW>
                                legendLabels{end+1}  = sprintf('%s (%s) - All', subjID, keyG1); %#ok<AGROW>
                            else
                                set(h, 'HandleVisibility', 'off');
                            end
                        end
                    end

                    % Hit
                    if showHit
                        mask = (hitFA == "Hit");
                        if any(mask)
                            mTrace = mean(Z(mask,:), 1, 'omitnan');
                            y = align_at_t0(tRef, mTrace);
                            h = plot(mainAx, tRef, y, ...
                                'Color', thisColor, 'LineStyle', '-', 'LineWidth', LW.single);
                            if isempty(thisLegendHandle)
                                thisLegendHandle = h;
                                legendHandles(end+1) = h;
                                legendLabels{end+1}  = sprintf('%s (%s) - Hit', subjID, keyG1);
                            else
                                set(h, 'HandleVisibility', 'off');
                            end
                        end
                    end

                    % FA
                    if showFA
                        mask = (hitFA == "FA");
                        if any(mask)
                            mTrace = mean(Z(mask,:), 1, 'omitnan');
                            y = align_at_t0(tRef, mTrace);
                            h = plot(mainAx, tRef, y, ...
                                'Color', thisColor, 'LineStyle', '--', 'LineWidth', LW.single);
                            if isempty(thisLegendHandle)
                                thisLegendHandle = h;
                                legendHandles(end+1) = h;
                                legendLabels{end+1}  = sprintf('%s (%s) - FA', subjID, keyG1);
                            else
                                set(h, 'HandleVisibility', 'off');
                            end
                        end
                    end
                end

            case 'groupmean'
                % ---- Group mean (subset in Group 1): mean ± SEM ----
                [mAll1, sAll1] = compute_agg_trace(sessG1, sessIdx1, 'All');
                [mHit1, sHit1] = compute_agg_trace(sessG1, sessIdx1, 'Hit');
                [mFA1,  sFA1 ] = compute_agg_trace(sessG1, sessIdx1, 'FA');

                baseColorG1 = get_base_color_from_key(keyG1);
                faColorG1   = make_lighter(baseColorG1);
                colorAll1   = [0.4 0.4 0.4];

                if showAll && ~all(isnan(mAll1))
                    y = align_at_t0(tRef, mAll1);
                    h = plot(mainAx, tRef, y, 'Color', colorAll1, 'LineStyle', '-', 'LineWidth', LW.group);
                    add_sem_patch(mainAx, tRef, y, sAll1, colorAll1);
                    legendHandles(end+1) = h;
                    legendLabels{end+1}  = sprintf('%s - All (group mean)', keyG1);
                end

                if showHit && ~all(isnan(mHit1))
                    y = align_at_t0(tRef, mHit1);
                    h = plot(mainAx, tRef, y, 'Color', baseColorG1, 'LineStyle', '-', 'LineWidth', LW.group);
                    add_sem_patch(mainAx, tRef, y, sHit1, baseColorG1);
                    legendHandles(end+1) = h;
                    legendLabels{end+1}  = sprintf('%s - Hit (group mean)', keyG1);
                end

                if showFA && ~all(isnan(mFA1))
                    y = align_at_t0(tRef, mFA1);
                    h = plot(mainAx, tRef, y, 'Color', faColorG1, 'LineStyle', '--', 'LineWidth', LW.group);
                    add_sem_patch(mainAx, tRef, y, sFA1, faColorG1);
                    legendHandles(end+1) = h;
                    legendLabels{end+1}  = sprintf('%s - FA (group mean)', keyG1);
                end

            case 'group12'
                % ---- Group 1 vs Group 2 ----
                [mAll1, sAll1] = compute_agg_trace(sessG1, 1:numel(sessG1), 'All');
                [mHit1, sHit1] = compute_agg_trace(sessG1, 1:numel(sessG1), 'Hit');
                [mFA1,  sFA1 ] = compute_agg_trace(sessG1, 1:numel(sessG1), 'FA');

                idxG2 = popupGroup2.Value;
                keyG2 = '';
                sessG2 = [];
                if idxG2 > 1
                    keyG2 = groupNames2{idxG2};
                    sessG2 = ctxGroups.(keyG2);
                end

                [mAll2, sAll2] = deal(nan(size(tRef)));
                [mHit2, sHit2] = deal(nan(size(tRef)));
                [mFA2,  sFA2 ] = deal(nan(size(tRef)));

                if ~isempty(sessG2)
                    [mAll2, sAll2] = compute_agg_trace(sessG2, 1:numel(sessG2), 'All');
                    [mHit2, sHit2] = compute_agg_trace(sessG2, 1:numel(sessG2), 'Hit');
                    [mFA2,  sFA2 ] = compute_agg_trace(sessG2, 1:numel(sessG2), 'FA');
                end

                baseColorG1 = get_base_color_from_key(keyG1);
                if isempty(sessG2)
                    baseColorG2 = [0.5 0.5 0.5];
                else
                    baseColorG2 = get_base_color_from_key(keyG2);

                    % If same genotype: assign an alternate color to the distractor group
                    if same_genotype_from_keys(keyG1, keyG2)
                        if has_distractor_ctx(keyG1) && ~has_distractor_ctx(keyG2)
                            baseColorG1 = get_alt_color_same_genotype(keyG1);
                        elseif has_distractor_ctx(keyG2) && ~has_distractor_ctx(keyG1)
                            baseColorG2 = get_alt_color_same_genotype(keyG2);
                        else
                            baseColorG2 = get_alt_color_same_genotype(keyG2);
                        end
                    end
                end

                faColorG1 = make_lighter(baseColorG1);
                faColorG2 = make_lighter(baseColorG2);

                colorAll1 = [0.4 0.4 0.4];
                colorAll2 = [0.6 0.6 0.6];

                % All
                if showAll
                    if ~all(isnan(mAll1))
                        y1 = align_at_t0(tRef, mAll1);
                        h1 = plot(mainAx, tRef, y1, 'Color', colorAll1, 'LineStyle', '-', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, sAll1, colorAll1);
                        legendHandles(end+1) = h1;
                        legendLabels{end+1}  = sprintf('%s - All', keyG1);
                    end
                    if ~isempty(sessG2) && ~all(isnan(mAll2))
                        y2 = align_at_t0(tRef, mAll2);
                        h2 = plot(mainAx, tRef, y2, 'Color', colorAll2, 'LineStyle', '-', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y2, sAll2, colorAll2);
                        legendHandles(end+1) = h2;
                        legendLabels{end+1}  = sprintf('%s - All', keyG2);
                    end
                end

                % Hit
                if showHit
                    if ~all(isnan(mHit1))
                        y1 = align_at_t0(tRef, mHit1);
                        h1 = plot(mainAx, tRef, y1, 'Color', baseColorG1, 'LineStyle', '-', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, sHit1, baseColorG1);
                        legendHandles(end+1) = h1;
                        legendLabels{end+1}  = sprintf('%s - Hit', keyG1);
                    end
                    if ~isempty(sessG2) && ~all(isnan(mHit2))
                        y2 = align_at_t0(tRef, mHit2);
                        h2 = plot(mainAx, tRef, y2, 'Color', baseColorG2, 'LineStyle', '-', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y2, sHit2, baseColorG2);
                        legendHandles(end+1) = h2;
                        legendLabels{end+1}  = sprintf('%s - Hit', keyG2);
                    end
                end

                % FA
                if showFA
                    if ~all(isnan(mFA1))
                        y1 = align_at_t0(tRef, mFA1);
                        h1 = plot(mainAx, tRef, y1, 'Color', faColorG1, 'LineStyle', '--', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, sFA1, faColorG1);
                        legendHandles(end+1) = h1;
                        legendLabels{end+1}  = sprintf('%s - FA', keyG1);
                    end
                    if ~isempty(sessG2) && ~all(isnan(mFA2))
                        y2 = align_at_t0(tRef, mFA2);
                        h2 = plot(mainAx, tRef, y2, 'Color', faColorG2, 'LineStyle', '--', 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y2, sFA2, faColorG2);
                        legendHandles(end+1) = h2;
                        legendLabels{end+1}  = sprintf('%s - FA', keyG2);
                    end
                end
        end

        if ~isempty(legendHandles)
            legend(mainAx, legendHandles, legendLabels, 'Interpreter', 'none', 'Location', 'best');
        end
    end

    % ---------------- Local helper functions ----------------
    function [mTrace, sTrace] = compute_agg_trace(sessions, sessIdx, outcomeName)
        % Compute group mean ± SEM across sessions:
        %   1) Compute session-level mean trace (average across trials)
        %   2) Then compute mean ± SEM across selected sessions
        %
        % outcomeName = 'All' / 'Hit' / 'FA'

        nSessSel = numel(sessIdx);
        if nSessSel == 0
            mTrace = nan(size(tRef));
            sTrace = nan(size(tRef));
            return;
        end

        allSessMean = nan(nSessSel, numel(tRef));

        for jj = 1:nSessSel
            s = sessions(sessIdx(jj));
            Z = s.Z;
            L = s.labels;
            nTrial = size(Z,1);

            hitFA = get_str_field(L, 'hitFA', nTrial, "Other");

            switch outcomeName
                case 'All'
                    mask = true(nTrial,1);
                case 'Hit'
                    mask = (hitFA == "Hit");
                case 'FA'
                    mask = (hitFA == "FA");
                otherwise
                    mask = true(nTrial,1);
            end

            idx = find(mask);
            if isempty(idx)
                continue;
            end

            Zsub = Z(idx, :);
            allSessMean(jj, :) = mean(Zsub, 1, 'omitnan');
        end

        % Remove all-NaN sessions
        validRow = ~all(isnan(allSessMean), 2);
        if ~any(validRow)
            mTrace = nan(size(tRef));
            sTrace = nan(size(tRef));
            return;
        end

        allSessMean = allSessMean(validRow, :);

        mTrace = mean(allSessMean, 1, 'omitnan');
        sTrace = std(allSessMean, 0, 1, 'omitnan') ./ sqrt(size(allSessMean,1));
    end

    function yAligned = align_at_t0(t, y)
        % Shift the trace so that y(t=0) becomes 0.
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
        % Draw SEM shading (excluded from legend)
        if all(isnan(ySem))
            return;
        end
        upper = yMean + ySem;
        lower = yMean - ySem;
        x = [t, fliplr(t)];
        y = [upper, fliplr(lower)];
        p = fill(ax, x, y, color, ...
            'FaceAlpha', 0.2, ...
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

    function cBase = get_base_color_from_key(keyStr)
        % Base color determined by genotype prefix (WT_/FX_)
        if startsWith(keyStr, 'WT_')
            cBase = [0 0.4470 0.7410];       % cool (blue)
        elseif startsWith(keyStr, 'FX_')
            cBase = [0.8500 0.3250 0.0980];  % warm (red/orange)
        else
            cBase = [0.3 0.3 0.3];           % fallback gray
        end
    end

    function cAlt = get_alt_color_same_genotype(keyStr)
        % Alternate color within the same genotype family
        if startsWith(keyStr, 'WT_')
            cAlt = [0.3010 0.7450 0.9330];   % alternate cool (cyan/blue)
        elseif startsWith(keyStr, 'FX_')
            cAlt = [0.9290 0.6940 0.1250];   % alternate warm (yellow/orange)
        else
            cAlt = [0.6 0.6 0.6];
        end
    end

    function tf = same_genotype_from_keys(k1, k2)
        g1 = get_genotype_label(k1);
        g2 = get_genotype_label(k2);
        tf = ~isempty(g1) && strcmp(g1, g2);
    end

    function g = get_genotype_label(keyStr)
        if startsWith(keyStr, 'WT_')
            g = 'WT';
        elseif startsWith(keyStr, 'FX_')
            g = 'FX';
        else
            g = '';
        end
    end

    function tf = has_distractor_ctx(keyStr)
        % If the key contains 'distractor' or 'distractoronly', treat it as a distractor context
        k = lower(keyStr);
        tf = contains(k, 'distractor');
    end

    function cLight = make_lighter(cBase)
        % Blend the color toward white (used for FA / lighter variants)
        alpha = 0.5;  % larger -> closer to white
        cLight = (1-alpha)*cBase + alpha*[1 1 1];
    end

    function cmap = make_genotype_palette(baseColor, n)
        % For single mode: create n shades from light -> baseColor
        if n <= 1
            cmap = baseColor;
            return;
        end
        cmap = zeros(n,3);
        for k = 1:n
            alpha = (k-1) / max(1, (n-1));  % 0 ~ 1
            cmap(k,:) = (1-alpha)*[1 1 1] + alpha*baseColor;
        end
    end
end