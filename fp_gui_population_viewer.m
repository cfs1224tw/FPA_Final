    function fp_gui_population_viewer(rootDir)
% FP_GUI_POPULATION_VIEWER (FINAL)
% - Context-based group viewer
% - Modes: Single / Group mean / Group1 vs Group2
% - Trace types: All / Hit / FA
% - Manual axes (no auto reset)
% - Align all traces so y(t=0)=0
% - Single session: NO across-session SEM
% - Save: exportgraphics(main plot only)
% - Color pickers for Group1/Group2 + Reset
% - Split mode:
%     1) All trials
%     2) Tone (1..7) + All
%     3) Symmetric Octave (4 bins) + All, built from Tone pairs:
%           Oct1: tones 1&7
%           Oct2/3: tones 2&6
%           Oct1/3: tones 3&5
%           Oct0: tone 4
% - Tile split bins:
%     * Tone mode -> 7 tiles (always show all 7 bins)
%     * Octave mode -> 4 tiles (always show all 4 bins)

    clc;
    if nargin < 1 || isempty(rootDir)
        rootDir = '/Users/foxking/Desktop/FPA_Final';
    end

    % ---------------- 1) Collect sessions and build context groups ----------------
    [allSubs, ~] = fp_collect_all_sub(rootDir);
    if isempty(allSubs)
        error('fp_gui_population_viewer_tone_1216:NoSubs', 'No sessions found.');
    end

    [ctxGroups, groupNames] = fp_build_context_groups(allSubs);
    if isempty(groupNames)
        error('fp_gui_population_viewer_tone_1216:NoContextGroups', 'No context-based groups found.');
    end

    groupNames  = cellstr(groupNames(:));
    groupNames2 = [{'<none>'}; groupNames(:)];

    canonKey = @(k) strtrim(char(string(k)));
    keyField = @(k) matlab.lang.makeValidName(canonKey(k)); % for struct field

    % Reference time base (from first group)
    firstKey = canonKey(groupNames{1});
    tRef = ctxGroups.(firstKey)(1).t(:)'; % row

    defaultXLim = [-2 10];
    defaultYLim = [-1.5 0.5];

    % ---------------- 2) Build GUI figure and controls ----------------
    fig = figure('Name', 'FP Population Viewer', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);

    % --- Container panel ---
    mainPanel = uipanel('Parent', fig, ...
        'Units','normalized', ...
        'Position',[0.31 0.10 0.48 0.80], ...
        'BorderType','none', ...
        'BackgroundColor','w');
    
    % --- Axes with safe margins ---
    axMargin = struct( ...
        'left',   0.10, ...  % leave room for ylabel
        'bottom', 0.10, ...  % leave room for xlabel
        'right',  0.03, ...
        'top',    0.06);     % leave room for title
    
    mainAx = axes('Parent', mainPanel, ...
        'Units','normalized', ...
        'Position',[
            axMargin.left, ...
            axMargin.bottom, ...
            1 - axMargin.left - axMargin.right, ...
            1 - axMargin.bottom - axMargin.top], ...
        'ActivePositionProperty','position');
    
    hold(mainAx,'on'); box(mainAx,'on'); grid(mainAx,'on');
    
    xlabel(mainAx,'Time (s)');
    ylabel(mainAx,'z (baseline-centered; aligned at t=0)');
    title(mainAx,'FP traces');
    
    mainAx.XLim = defaultXLim;
    mainAx.YLim = defaultYLim;
    set(mainAx,'XLimMode','manual','YLimMode','manual');

    % ---------- Top-right: Trace type checkboxes ----------
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.92 0.18 0.035], 'String', 'Trace type', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    cbAll = uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.80 0.885 0.06 0.04], 'String', 'All', 'BackgroundColor', 'w', 'Value', 0, ...
        'Tag', 'cbAll');
    cbHit = uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.87 0.885 0.06 0.04], 'String', 'Hit', 'BackgroundColor', 'w', 'Value', 1, ...
        'Tag', 'cbHit');
    cbFA  = uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.94 0.885 0.05 0.04], 'String', 'FA',  'BackgroundColor', 'w', 'Value', 1, ...
        'Tag', 'cbFA');

    % ---------- Split mode controls ----------
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.84 0.18 0.035], 'String', 'Split mode', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    popupSplitMode = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.80 0.81 0.18 0.035], ...
        'String', {'All trials', 'Tone (1..7)', 'Symmetric Octave (4 bins)'}, ...
        'BackgroundColor', 'w', 'Callback', @onSplitModeChanged, ...
        'Tag', 'popupSplitMode');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.77 0.18 0.03], 'String', 'Split selection', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    popupSplitIdx = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.80 0.74 0.18 0.035], ...
        'String', {'All'}, 'BackgroundColor', 'w', 'Tag', 'popupSplitIdx');

    cbTileSplit = uicontrol(fig, 'Style','checkbox', 'Units','normalized', ...
        'Position',[0.80 0.705 0.18 0.035], ...
        'String','Tile split bins', 'Value',0, 'BackgroundColor','w', 'Tag', 'cbTileSplit');

    % ---------- Axes settings ----------
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.67 0.18 0.035], ...
        'String', 'Axes limits [Xmin Xmax; Ymin Ymax]', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.645 0.04 0.03], 'String', 'X:', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    editXmin = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.84 0.645 0.06 0.035], 'String', num2str(defaultXLim(1)), 'BackgroundColor', 'w');
    editXmax = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.91 0.645 0.07 0.035], 'String', num2str(defaultXLim(2)), 'BackgroundColor', 'w');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.6 0.04 0.03], 'String', 'Y:', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    editYmin = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.84 0.6 0.06 0.035], 'String', num2str(defaultYLim(1)), 'BackgroundColor', 'w');
    editYmax = uicontrol(fig, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.91 0.6 0.07 0.035], 'String', num2str(defaultYLim(2)), 'BackgroundColor', 'w');

    btnApplyAxes = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.80 0.54 0.18 0.045], 'String', 'Apply Axes', 'Callback', @onApplyAxes);

    % ---------- Color controls ----------
    btnColorG1 = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.80 0.5 0.085 0.04], 'String', 'Pick G1', 'Callback', @onPickColorG1);
    btnColorG2 = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.895 0.5 0.085 0.04], 'String', 'Pick G2', 'Callback', @onPickColorG2);
    btnResetColors = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.80 0.45 0.18 0.04], 'String', 'Reset Colors', 'Callback', @onResetColors);

    % ---------- Plot / Save ----------
    btnPlot = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.80 0.40 0.18 0.055], 'String', 'Plot', 'FontWeight', 'bold', 'Callback', @onPlot, ...
        'Tag', 'btnPlot');
    btnSave = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.80 0.34 0.18 0.055], 'String', 'Save Figure...', 'Callback', @onSaveFigure);

    % ---------- Left panel: Group selection ----------
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02 0.90 0.25 0.035], 'String', 'Group 1 (Genotype_Region_Context)', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    popupGroup1 = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.02 0.86 0.25 0.04], 'String', groupNames, 'BackgroundColor', 'w', ...
        'Callback', @onGroup1Changed, 'Tag', 'popupGroup1');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02 0.82 0.25 0.03], 'String', 'Sessions in Group 1 (Single / optional subset)', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    listSessions1 = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
        'Position', [0.02 0.64 0.25 0.18], 'Max', 2, 'Min', 0, 'BackgroundColor', 'w', ...
        'Tag', 'listSessions1');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02 0.60 0.25 0.03], 'String', 'Animals in Group 1 (subset for Group mean / Group12)', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    listAnimals1 = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
        'Position', [0.02 0.50 0.25 0.10], 'Max', 2, 'Min', 0, 'BackgroundColor', 'w', ...
        'Tag', 'listAnimals1');

    modeBG = uibuttongroup(fig, 'Units', 'normalized', 'Position', [0.02 0.35 0.25 0.13], ...
        'Title', 'Mode', 'BackgroundColor', 'w');

    rbSingle    = uicontrol(modeBG, 'Style', 'radiobutton', 'Units', 'normalized', ...
        'Position', [0.05 0.66 0.9 0.30], 'String', 'Single session', 'Tag', 'single', 'BackgroundColor', 'w');
    rbGroupMean = uicontrol(modeBG, 'Style', 'radiobutton', 'Units', 'normalized', ...
        'Position', [0.05 0.36 0.9 0.30], 'String', 'Group mean', 'Tag', 'groupmean', 'BackgroundColor', 'w');
    rbGroup12   = uicontrol(modeBG, 'Style', 'radiobutton', 'Units', 'normalized', ...
        'Position', [0.05 0.06 0.9 0.30], 'String', 'Group 1 vs Group 2', 'Tag', 'group12', 'BackgroundColor', 'w');
    modeBG.SelectedObject = rbSingle;

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02 0.30 0.25 0.03], 'String', 'Group 2 (for comparison)', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    popupGroup2 = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.02 0.26 0.25 0.04], 'String', groupNames2, 'BackgroundColor', 'w', ...
        'Callback', @onGroup2Changed, 'Tag', 'popupGroup2');

    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.02 0.22 0.25 0.03], 'String', 'Animals in Group 2 (subset for Group12)', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'w');

    listAnimals2 = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
        'Position', [0.02 0.10 0.25 0.12], 'Max', 2, 'Min', 0, 'BackgroundColor', 'w', ...
        'Tag', 'listAnimals2');

    % ---------- State ----------
    manualAxes  = false;
    currentXLim = defaultXLim;
    currentYLim = defaultYLim;

    LW.single = 1.5;
    LW.group  = 2.0;

    % ---------- Color maps (AUTO + USER OVERRIDE) ----------
    autoColorMap  = build_group_color_map(groupNames);
    setappdata(fig, 'autoColorMap',  autoColorMap);
    setappdata(fig, 'groupColorMap', autoColorMap);

    % init
    onSplitModeChanged();
    onGroup1Changed();
    onGroup2Changed();

    % ============================ Callbacks ============================

    function onSplitModeChanged(~, ~)
        sanitize_popup_value(popupSplitMode);
        m = popupSplitMode.Value;
        switch m
            case 1 % All
                set(popupSplitIdx, 'String', {'All'}, 'Value', 1, 'Enable', 'off');
                set(cbTileSplit, 'Value', 0); % tile off when All trials
            case 2 % Tone
                items = [{'All'}, cellstr(compose('Tone %d', 1:7))];
                set(popupSplitIdx, 'String', items, 'Value', 1, 'Enable', 'on');
            case 3 % Octave
                items = {'All', 'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'};
                set(popupSplitIdx, 'String', items, 'Value', 1, 'Enable', 'on');
        end
    end

    function onGroup1Changed(~, ~)
        sanitize_popup_value(popupGroup1);
        key = canonKey(groupNames{popupGroup1.Value});
        sessions = ctxGroups.(key);

        labelsOut = cell(numel(sessions), 1);
        ids = strings(numel(sessions),1);

        for ii = 1:numel(sessions)
            m = sessions(ii).meta;

            id = '';
            if isfield(m,'ID') && ~isempty(m.ID)
                id = char(string(m.ID));
            elseif isfield(m,'AnimalID') && ~isempty(m.AnimalID)
                id = char(string(m.AnimalID));
            end
            ids(ii) = string(id);

            dt = '';
            if isfield(m,'date') && ~isempty(m.date)
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
        set_listbox_contents(listSessions1, labelsOut, 1);

        uIDs = unique(ids, 'stable');
        uIDs(uIDs=="") = [];
        if isempty(uIDs)
            set_listbox_contents(listAnimals1, {'<no animal>'}, 1);
        else
            set_listbox_contents(listAnimals1, cellstr(uIDs), []);
        end
    end

    function onGroup2Changed(~, ~)
        sanitize_popup_value(popupGroup2);
        idxG2 = popupGroup2.Value;
        if idxG2 <= 1
            set_listbox_contents(listAnimals2, {'<none>'}, 1);
            set(listAnimals2, 'Enable', 'off');
            return;
        end

        keyG2 = canonKey(groupNames2{idxG2});
        sessions = ctxGroups.(keyG2);

        ids = strings(numel(sessions),1);
        for ii = 1:numel(sessions)
            m = sessions(ii).meta;
            if isfield(m,'ID') && ~isempty(m.ID)
                ids(ii) = string(m.ID);
            elseif isfield(m,'AnimalID') && ~isempty(m.AnimalID)
                ids(ii) = string(m.AnimalID);
            else
                ids(ii) = "Unknown";
            end
        end

        uIDs = unique(ids, 'stable');
        if isempty(uIDs)
            set_listbox_contents(listAnimals2, {'<no animal>'}, 1);
            set(listAnimals2, 'Enable', 'on');
        else
            set_listbox_contents(listAnimals2, cellstr(uIDs), []);
            set(listAnimals2, 'Enable', 'on');
        end
    end

    function onPickColorG1(~, ~)
        key = canonKey(groupNames{popupGroup1.Value});
        cmap = getappdata(fig, 'groupColorMap');
        f = keyField(key);
        c0 = cmap.(f);

        c = uisetcolor(c0, sprintf('Pick color for Group 1: %s', key));
        if numel(c)==3
            cmap.(f) = c;
            setappdata(fig, 'groupColorMap', cmap);
        end
    end

    function onPickColorG2(~, ~)
        idxG2 = popupGroup2.Value;
        if idxG2 <= 1
            warndlg('Group 2 is <none>. Please select a real Group 2 first.', 'Group 2');
            return;
        end

        key = canonKey(groupNames2{idxG2});
        cmap = getappdata(fig, 'groupColorMap');
        f = keyField(key);
        c0 = cmap.(f);

        c = uisetcolor(c0, sprintf('Pick color for Group 2: %s', key));
        if numel(c)==3
            cmap.(f) = c;
            setappdata(fig, 'groupColorMap', cmap);
        end
    end

    function onResetColors(~, ~)
        auto = getappdata(fig, 'autoColorMap');
        setappdata(fig, 'groupColorMap', auto);
        warndlg('Colors reset to auto palette.', 'Colors');
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

        if ~isempty(mainAx) && isgraphics(mainAx)
            set(mainAx,'XLim',currentXLim,'YLim',currentYLim,'XLimMode','manual','YLimMode','manual');
        end
    end

    function onSaveFigure(~, ~)
        [file, path] = uiputfile({'*.png';'*.pdf'}, 'Save main plot');
        if isequal(file,0), return; end
        fullpath = fullfile(path, file);
        [~,~,ext] = fileparts(fullpath);

        hasTL = ~isempty(findall(mainPanel, 'Type','tiledlayout'));

        switch lower(ext)
            case '.png'
                if hasTL
                    exportgraphics(mainPanel, fullpath, 'Resolution',300);
                else
                    exportgraphics(mainAx, fullpath, 'Resolution',300);
                end
            case '.pdf'
                if hasTL
                    exportgraphics(mainPanel, fullpath, 'ContentType','vector');
                else
                    exportgraphics(mainAx, fullpath, 'ContentType','vector');
                end
            otherwise
                if hasTL
                    exportgraphics(mainPanel, [fullpath '.png'], 'Resolution',300);
                else
                    exportgraphics(mainAx, [fullpath '.png'], 'Resolution',300);
                end
        end
    end

    function onPlot(~, ~)
        sanitize_popup_value(popupSplitMode);
        sanitize_popup_value(popupSplitIdx);
        sanitize_popup_value(popupGroup1);
        sanitize_popup_value(popupGroup2);
        sanitize_listbox_value(listSessions1);
        sanitize_listbox_value(listAnimals1);
        sanitize_listbox_value(listAnimals2);

        splitMode = popupSplitMode.Value; % 1=All,2=Tone,3=Oct
        splitIdx  = popupSplitIdx.Value;  % includes 'All' at 1 for Tone/Oct
        doTile = (cbTileSplit.Value==1) && (splitMode~=1);

        showAll = logical(cbAll.Value);
        showHit = logical(cbHit.Value);
        showFA  = logical(cbFA.Value);
        if ~showAll && ~showHit && ~showFA
            warndlg('Please select at least one trace type (All/Hit/FA).', 'Trace type');
            return;
        end

        if doTile
            plot_tiled_split_bins(splitMode); % always tile all bins
            return;
        end

        % ---- SINGLE AXES MODE: rebuild plot area ----
        mainAx = reset_plot_area(false);

        % axis limits
        if manualAxes
            set(mainAx,'XLim',currentXLim,'YLim',currentYLim);
        else
            set(mainAx,'XLim',defaultXLim,'YLim',defaultYLim);
        end
        set(mainAx,'XLimMode','manual','YLimMode','manual');

        modeTag = modeBG.SelectedObject.Tag;

        keyG1  = canonKey(groupNames{popupGroup1.Value});
        sessG1 = ctxGroups.(keyG1);

        idxG2 = popupGroup2.Value;
        keyG2 = '';
        sessG2 = [];
        if idxG2>1
            keyG2 = canonKey(groupNames2{idxG2});
            sessG2 = ctxGroups.(keyG2);
        end

        cmap = getappdata(fig,'groupColorMap');
        getGroupColor = @(k) cmap.(keyField(k));

        ttl = sprintf('%s | %s', upper(modeTag), split_label(splitMode, splitIdx));
        if strcmp(modeTag,'group12')
            if isempty(keyG2), ttl = sprintf('%s vs <none> | %s', keyG1, split_label(splitMode, splitIdx));
            else, ttl = sprintf('%s vs %s | %s', keyG1, keyG2, split_label(splitMode, splitIdx));
            end
        else
            ttl = sprintf('%s: %s | %s', modeTag, keyG1, split_label(splitMode, splitIdx));
        end
        title(mainAx, ttl, 'Interpreter','none');

        legendHandles = [];
        legendLabels  = {};

        switch modeTag
            case 'single'
                sessIdx1 = listSessions1.Value;
                if isempty(sessIdx1) || sessIdx1(1)==0
                    sessIdx1 = 1:numel(sessG1);
                end
                baseColor = getGroupColor(keyG1);
                cmSess = make_genotype_palette(baseColor, numel(sessIdx1));

                for jj = 1:numel(sessIdx1)
                    s = sessG1(sessIdx1(jj));
                    subjID = get_session_id(s, sessIdx1(jj));

                    [Zuse,Luse] = select_trials_with_split(s, splitMode, splitIdx);
                    if isempty(Zuse), continue; end
                    hitFA = get_str_field(Luse,'hitFA',size(Zuse,1),"Other");

                    thisColor = cmSess(jj,:);

                    if showAll
                        y = align_at_t0(tRef, mean(Zuse,1,'omitnan'));
                        h = plot(mainAx, tRef, y, 'Color', make_lighter(thisColor), 'LineStyle','-', 'LineWidth', LW.single);
                        legendHandles(end+1) = h;
                        legendLabels{end+1} = sprintf('%s | All', subjID);
                    end

                    if showHit
                        m = hitFA=="Hit";
                        if any(m)
                            y = align_at_t0(tRef, mean(Zuse(m,:),1,'omitnan'));
                            h = plot(mainAx, tRef, y, 'Color', thisColor, 'LineStyle','-', 'LineWidth', LW.single);
                            legendHandles(end+1) = h;
                            legendLabels{end+1} = sprintf('%s | Hit', subjID);
                        end
                    end

                    if showFA
                        m = hitFA=="FA";
                        if any(m)
                            y = align_at_t0(tRef, mean(Zuse(m,:),1,'omitnan'));
                            h = plot(mainAx, tRef, y, '--', 'Color', make_lighter(thisColor), 'LineWidth', LW.single);
                            legendHandles(end+1) = h;
                            legendLabels{end+1} = sprintf('%s | FA', subjID);
                        end
                    end
                end

            case 'groupmean'
                sessIdx1 = sessions_from_selected_animals(sessG1, listAnimals1);
                if isempty(sessIdx1), sessIdx1 = 1:numel(sessG1); end

                c1 = getGroupColor(keyG1);
                cFA1 = make_lighter(c1);
                cAll1 = [0.4 0.4 0.4];

                if showAll
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'All', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y = align_at_t0(tRef, m1);
                        h = plot(mainAx, tRef, y, 'Color', cAll1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y, s1, cAll1);
                        legendHandles(end+1)=h; legendLabels{end+1}=sprintf('%s | All', keyG1);
                    end
                end
                if showHit
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'Hit', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y = align_at_t0(tRef, m1);
                        h = plot(mainAx, tRef, y, 'Color', c1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y, s1, c1);
                        legendHandles(end+1)=h; legendLabels{end+1}=sprintf('%s | Hit', keyG1);
                    end
                end
                if showFA
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'FA', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y = align_at_t0(tRef, m1);
                        h = plot(mainAx, tRef, y, '--', 'Color', cFA1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y, s1, cFA1);
                        legendHandles(end+1)=h; legendLabels{end+1}=sprintf('%s | FA', keyG1);
                    end
                end

            case 'group12'
                sessIdx1 = sessions_from_selected_animals(sessG1, listAnimals1);
                if isempty(sessIdx1), sessIdx1 = 1:numel(sessG1); end

                sessIdx2 = [];
                if ~isempty(sessG2)
                    sessIdx2 = sessions_from_selected_animals(sessG2, listAnimals2);
                    if isempty(sessIdx2), sessIdx2 = 1:numel(sessG2); end
                end

                c1 = getGroupColor(keyG1);
                c2 = [0.5 0.5 0.5];
                if ~isempty(sessG2), c2 = getGroupColor(keyG2); end

                cAll1 = make_lighter(make_lighter(c1));
                cAll2 = make_lighter(make_lighter(c2));
                cFA1  = make_lighter(c1);
                cFA2  = make_lighter(c2);

                if showAll
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'All', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y1 = align_at_t0(tRef, m1);
                        h1 = plot(mainAx, tRef, y1, 'Color', cAll1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, s1, cAll1);
                        legendHandles(end+1)=h1; legendLabels{end+1}=sprintf('%s | All', keyG1);
                    end
                    if ~isempty(sessG2)
                        [m2,s2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'All', splitMode, splitIdx);
                        if ~all(isnan(m2))
                            y2 = align_at_t0(tRef, m2);
                            h2 = plot(mainAx, tRef, y2, 'Color', cAll2, 'LineWidth', LW.group);
                            add_sem_patch(mainAx, tRef, y2, s2, cAll2);
                            legendHandles(end+1)=h2; legendLabels{end+1}=sprintf('%s | All', keyG2);
                        end
                    end
                end

                if showHit
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'Hit', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y1 = align_at_t0(tRef, m1);
                        h1 = plot(mainAx, tRef, y1, 'Color', c1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, s1, c1);
                        legendHandles(end+1)=h1; legendLabels{end+1}=sprintf('%s | Hit', keyG1);
                    end
                    if ~isempty(sessG2)
                        [m2,s2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'Hit', splitMode, splitIdx);
                        if ~all(isnan(m2))
                            y2 = align_at_t0(tRef, m2);
                            h2 = plot(mainAx, tRef, y2, 'Color', c2, 'LineWidth', LW.group);
                            add_sem_patch(mainAx, tRef, y2, s2, c2);
                            legendHandles(end+1)=h2; legendLabels{end+1}=sprintf('%s | Hit', keyG2);
                        end
                    end
                end

                if showFA
                    [m1,s1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'FA', splitMode, splitIdx);
                    if ~all(isnan(m1))
                        y1 = align_at_t0(tRef, m1);
                        h1 = plot(mainAx, tRef, y1, '--', 'Color', cFA1, 'LineWidth', LW.group);
                        add_sem_patch(mainAx, tRef, y1, s1, cFA1);
                        legendHandles(end+1)=h1; legendLabels{end+1}=sprintf('%s | FA', keyG1);
                    end
                    if ~isempty(sessG2)
                        [m2,s2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'FA', splitMode, splitIdx);
                        if ~all(isnan(m2))
                            y2 = align_at_t0(tRef, m2);
                            h2 = plot(mainAx, tRef, y2, '--', 'Color', cFA2, 'LineWidth', LW.group);
                            add_sem_patch(mainAx, tRef, y2, s2, cFA2);
                            legendHandles(end+1)=h2; legendLabels{end+1}=sprintf('%s | FA', keyG2);
                        end
                    end
                end
        end

        if ~isempty(legendHandles)
            legend(mainAx, legendHandles, legendLabels, 'Interpreter','none', 'Location','best');
        end
    end

    % ============================ Tile Plot ============================

    function plot_tiled_split_bins(splitMode)
        % splitMode: 2=Tone(1..7), 3=Oct(4)
        reset_plot_area(true); % creates tiledlayout

        showAll = logical(cbAll.Value);
        showHit = logical(cbHit.Value);
        showFA  = logical(cbFA.Value);

        modeTag = modeBG.SelectedObject.Tag;

        keyG1  = canonKey(groupNames{popupGroup1.Value});
        sessG1 = ctxGroups.(keyG1);

        idxG2 = popupGroup2.Value;
        keyG2 = ''; sessG2 = [];
        if idxG2>1
            keyG2 = canonKey(groupNames2{idxG2});
            sessG2 = ctxGroups.(keyG2);
        end

        cmap = getappdata(fig,'groupColorMap');
        getGroupColor = @(k) cmap.(keyField(k));
        c1 = getGroupColor(keyG1);
        c2 = [0.5 0.5 0.5];
        if ~isempty(sessG2), c2 = getGroupColor(keyG2); end

        if splitMode==2
            nBin=7; nRow=3; nCol=3;
            binLabel = @(k) sprintf('Tone %d', k);
        else
            nBin=4; nRow=2; nCol=2;
            bn = {'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'};
            binLabel = @(k) bn{k};
        end

        tl = tiledlayout(mainPanel, nRow, nCol, 'Padding','compact', 'TileSpacing','compact');

        if strcmp(modeTag,'group12')
            if isempty(keyG2), title(tl, sprintf('%s vs <none> | Tiled', keyG1), 'Interpreter','none');
            else, title(tl, sprintf('%s vs %s | Tiled', keyG1, keyG2), 'Interpreter','none');
            end
        else
            title(tl, sprintf('%s: %s | Tiled', modeTag, keyG1), 'Interpreter','none');
        end

        % session selection
        switch modeTag
            case 'single'
                sessIdx1 = listSessions1.Value;
                if isempty(sessIdx1) || sessIdx1(1)==0, sessIdx1 = 1:numel(sessG1); end
            otherwise
                sessIdx1 = sessions_from_selected_animals(sessG1, listAnimals1);
                if isempty(sessIdx1), sessIdx1 = 1:numel(sessG1); end
        end

        sessIdx2 = [];
        if strcmp(modeTag,'group12') && ~isempty(sessG2)
            sessIdx2 = sessions_from_selected_animals(sessG2, listAnimals2);
            if isempty(sessIdx2), sessIdx2 = 1:numel(sessG2); end
        end

        for b = 1:nBin
            ax = nexttile(tl);
            hold(ax,'on'); box(ax,'on'); grid(ax,'on');
            xlabel(ax,'t (s)'); ylabel(ax,'z');
            title(ax, binLabel(b), 'Interpreter','none');

            if manualAxes
                set(ax,'XLim',currentXLim,'YLim',currentYLim);
            else
                set(ax,'XLim',defaultXLim,'YLim',defaultYLim);
            end
            set(ax,'XLimMode','manual','YLimMode','manual');

            switch modeTag
                case 'single'
                    cmSess = make_genotype_palette(c1, numel(sessIdx1));
                    for ii = 1:numel(sessIdx1)
                        s = sessG1(sessIdx1(ii));
                        [Zuse,Luse] = select_trials_with_split(s, splitMode, b+1); % +1 because selection list has 'All' at 1
                        if isempty(Zuse), continue; end
                        hitFA = get_str_field(Luse,'hitFA',size(Zuse,1),"Other");

                        if showAll
                            y = align_at_t0(tRef, mean(Zuse,1,'omitnan'));
                            plot(ax, tRef, y, 'Color', make_lighter(cmSess(ii,:)), 'LineWidth', LW.single);
                        end
                        if showHit
                            m = hitFA=="Hit";
                            if any(m)
                                y = align_at_t0(tRef, mean(Zuse(m,:),1,'omitnan'));
                                plot(ax, tRef, y, 'Color', cmSess(ii,:), 'LineWidth', LW.single);
                            end
                        end
                        if showFA
                            m = hitFA=="FA";
                            if any(m)
                                y = align_at_t0(tRef, mean(Zuse(m,:),1,'omitnan'));
                                plot(ax, tRef, y, '--', 'Color', make_lighter(cmSess(ii,:)), 'LineWidth', LW.single);
                            end
                        end
                    end

                otherwise
                    % G1
                    [mA1,sA1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'All', splitMode, b+1);
                    [mH1,sH1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'Hit', splitMode, b+1);
                    [mF1,sF1] = compute_agg_trace_with_split(sessG1, sessIdx1, 'FA',  splitMode, b+1);

                    if showAll && ~all(isnan(mA1))
                        y = align_at_t0(tRef, mA1);
                        cc = make_lighter(make_lighter(c1));
                        plot(ax, tRef, y, 'Color', cc, 'LineWidth', LW.group);
                        add_sem_patch(ax, tRef, y, sA1, cc);
                    end
                    if showHit && ~all(isnan(mH1))
                        y = align_at_t0(tRef, mH1);
                        plot(ax, tRef, y, 'Color', c1, 'LineWidth', LW.group);
                        add_sem_patch(ax, tRef, y, sH1, c1);
                    end
                    if showFA && ~all(isnan(mF1))
                        y = align_at_t0(tRef, mF1);
                        cc = make_lighter(c1);
                        plot(ax, tRef, y, '--', 'Color', cc, 'LineWidth', LW.group);
                        add_sem_patch(ax, tRef, y, sF1, cc);
                    end

                    % G2 (only in group12)
                    if strcmp(modeTag,'group12') && ~isempty(sessG2)
                        [mA2,sA2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'All', splitMode, b+1);
                        [mH2,sH2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'Hit', splitMode, b+1);
                        [mF2,sF2] = compute_agg_trace_with_split(sessG2, sessIdx2, 'FA',  splitMode, b+1);

                        if showAll && ~all(isnan(mA2))
                            y = align_at_t0(tRef, mA2);
                            cc = make_lighter(make_lighter(c2));
                            plot(ax, tRef, y, 'Color', cc, 'LineWidth', LW.group);
                            add_sem_patch(ax, tRef, y, sA2, cc);
                        end
                        if showHit && ~all(isnan(mH2))
                            y = align_at_t0(tRef, mH2);
                            plot(ax, tRef, y, 'Color', c2, 'LineWidth', LW.group);
                            add_sem_patch(ax, tRef, y, sH2, c2);
                        end
                        if showFA && ~all(isnan(mF2))
                            y = align_at_t0(tRef, mF2);
                            cc = make_lighter(c2);
                            plot(ax, tRef, y, '--', 'Color', cc, 'LineWidth', LW.group);
                            add_sem_patch(ax, tRef, y, sF2, cc);
                        end
                    end
            end
        end
    end

    % ============================ Plot area reset (THE FIX) ============================

    function axOrEmpty = reset_plot_area(makeTile)
        % Destroys any existing tiledlayout/axes in mainPanel and recreates
        % either a single full-size axes OR leaves space for tiledlayout.
        delete(findall(mainPanel, 'Type','tiledlayout'));
        delete(findall(mainPanel, 'Type','axes'));

        if makeTile
            axOrEmpty = [];
            % tiledlayout will be created by caller
            return;
        end

        axOrEmpty = axes('Parent', mainPanel, ...
            'Units','normalized', ...
            'Position',[0.08 0.08 0.9 0.88], ...
            'ActivePositionProperty','position');
        hold(axOrEmpty,'on'); box(axOrEmpty,'on'); grid(axOrEmpty,'on');
        xlabel(axOrEmpty,'Time (s)');
        ylabel(axOrEmpty,'z (baseline-centered; aligned at t=0)');
        set(axOrEmpty,'XLimMode','manual','YLimMode','manual');
    end

    % ============================ Split helpers ============================

    function [Zuse, Luse] = select_trials_with_split(sessionEntry, splitMode, splitIdx)
        Z0 = sessionEntry.Z;
        L0 = sessionEntry.labels;

        if isempty(Z0)
            Zuse = [];
            Luse = L0;
            return;
        end

        nTrial = size(Z0,1);

        % splitIdx meaning:
        % - Mode1: only "All"
        % - Tone/Oct: popupSplitIdx has 'All' at 1; bins start at 2
        if splitMode == 1
            idx = 1:nTrial;

        elseif splitMode == 2
            if splitIdx == 1
                idx = 1:nTrial;  % All tones
            else
                toneK = splitIdx - 1; % 1..7
                idx = idx_tone(sessionEntry, toneK);
            end

        else % splitMode == 3
            if splitIdx == 1
                idx = 1:nTrial; % All oct bins
            else
                octK = splitIdx - 1; % 1..4
                idx = idx_octave_from_tones(sessionEntry, octK);
            end
        end

        if isempty(idx)
            Zuse = [];
            Luse = L0;
            return;
        end

        Zuse = Z0(idx, :);
        Luse = subset_labels(L0, idx, nTrial);
    end

    function idx = idx_tone(sessionEntry, toneK)
        L = sessionEntry.labels;
        idx = [];

        toneID = get_num_field(L, {'toneID','tone_id','ToneID','Tone'}, []);
        if ~isempty(toneID)
            idx = find(toneID == toneK);
            return;
        end

        if isfield(sessionEntry,'Split') && ~isempty(sessionEntry.Split)
            idx = idx_from_split_struct(sessionEntry.Split, 2, toneK);
        end
    end

    function idx = idx_octave_from_tones(sessionEntry, octK)
        L = sessionEntry.labels;
        idx = [];

        toneID = get_num_field(L, {'toneID','tone_id','ToneID','Tone'}, []);
        if isempty(toneID)
            if isfield(sessionEntry,'Split') && ~isempty(sessionEntry.Split)
                idx = idx_octave_from_splitTone(sessionEntry.Split, octK);
            end
            return;
        end

        switch octK
            case 1, tones = [1 7];
            case 2, tones = [2 6];
            case 3, tones = [3 5];
            case 4, tones = 4;
            otherwise, tones = [];
        end
        if isempty(tones), return; end
        idx = find(ismember(toneID, tones));
    end

    function idx = idx_octave_from_splitTone(Split, octK)
        idx = [];
        toneCells = try_get_cell_idx_all(Split, {'Tone','tone','toneID','ToneID'});
        if isempty(toneCells) || numel(toneCells) < 7, return; end

        switch octK
            case 1, ks = [1 7];
            case 2, ks = [2 6];
            case 3, ks = [3 5];
            case 4, ks = 4;
            otherwise, ks = [];
        end
        if isempty(ks), return; end

        tmp = [];
        for kk = ks
            if kk<=numel(toneCells) && ~isempty(toneCells{kk})
                tmp = [tmp; toneCells{kk}(:)]; 
            end
        end
        idx = unique(tmp);
    end

    function idx = idx_from_split_struct(Split, splitMode, splitIdx)
        idx = [];
        try
            if splitMode == 2
                idx = try_get_cell_idx(Split, {'Tone','tone','toneID','ToneID'}, splitIdx);
            elseif splitMode == 3
                idx = try_get_cell_idx(Split, {'Octave','OctSym','octSym','octSymID','OctSymID'}, splitIdx);
            end
        catch
            idx = [];
        end
    end

    function idx = try_get_cell_idx(Split, fieldCandidates, k)
        idx = [];
        for ii = 1:numel(fieldCandidates)
            fn = fieldCandidates{ii};
            if isfield(Split, fn)
                S = Split.(fn);
                if isstruct(S) && isfield(S,'All') && iscell(S.All) && numel(S.All) >= k
                    idx = S.All{k}; return;
                end
                if iscell(S) && numel(S) >= k
                    idx = S{k}; return;
                end
            end
        end
    end

    function cells = try_get_cell_idx_all(Split, fieldCandidates)
        cells = {};
        for ii = 1:numel(fieldCandidates)
            fn = fieldCandidates{ii};
            if isfield(Split, fn)
                S = Split.(fn);
                if isstruct(S) && isfield(S,'All') && iscell(S.All)
                    cells = S.All; return;
                end
                if iscell(S)
                    cells = S; return;
                end
            end
        end
    end

    function v = get_num_field(L, candidates, defaultVal)
        v = defaultVal;
        for ii = 1:numel(candidates)
            fn = candidates{ii};
            if isfield(L, fn) && ~isempty(L.(fn))
                v = double(L.(fn)(:));
                return;
            end
        end
    end

    function L2 = subset_labels(L, idx, nTrial)
        L2 = L;
        fns = fieldnames(L2);
        for ff = 1:numel(fns)
            fn = fns{ff};
            v  = L2.(fn);
            try
                if isvector(v) && numel(v) == nTrial
                    L2.(fn) = v(idx);
                elseif ismatrix(v) && size(v,1) == nTrial
                    L2.(fn) = v(idx, :);
                end
            catch
            end
        end
    end

    function lbl = split_label(splitMode, splitIdx)
        switch splitMode
            case 1
                lbl = 'All trials';
            case 2
                if splitIdx==1, lbl='All tones';
                else, lbl = sprintf('Tone %d', splitIdx-1);
                end
            case 3
                if splitIdx==1
                    lbl='All octaves';
                else
                    names = {'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'};
                    k = splitIdx-1;
                    if k>=1 && k<=4, lbl = names{k};
                    else, lbl = sprintf('Oct %d', k);
                    end
                end
            otherwise
                lbl = 'All trials';
        end
    end

    % ============================ Core helpers ============================

    function sessIdx = sessions_from_selected_animals(sessions, listHandle)
        sessIdx = [];
        names = string(get(listHandle,'String'));
        sel   = sanitize_listbox_value(listHandle);

        if isempty(names) || isempty(sel) || any(sel==0), return; end
        if numel(names)==1 && (names=="<none>" || names=="<no animal>"), return; end

        selIDs = names(sel);

        ids = strings(numel(sessions),1);
        for kk = 1:numel(sessions)
            m = sessions(kk).meta;
            if isfield(m,'ID') && ~isempty(m.ID)
                ids(kk) = string(m.ID);
            elseif isfield(m,'AnimalID') && ~isempty(m.AnimalID)
                ids(kk) = string(m.AnimalID);
            else
                ids(kk) = "Unknown";
            end
        end

        sessIdx = find(ismember(ids, selIDs));
    end

    function sid = get_session_id(s, idxSess)
        if isfield(s.meta,'ID') && ~isempty(s.meta.ID)
            sid = char(string(s.meta.ID));
        elseif isfield(s.meta,'AnimalID') && ~isempty(s.meta.AnimalID)
            sid = char(string(s.meta.AnimalID));
        else
            sid = sprintf('Sess%d', idxSess);
        end
    end

    function [mTrace, sTrace] = compute_agg_trace_with_split(sessions, sessIdx, outcomeName, splitMode, splitIdx)
        nSessSel = numel(sessIdx);
        if nSessSel == 0
            mTrace = nan(size(tRef));
            sTrace = nan(size(tRef));
            return;
        end

        allSessMean = nan(nSessSel, numel(tRef));

        for jj = 1:nSessSel
            s = sessions(sessIdx(jj));
            [Zuse, Luse] = select_trials_with_split(s, splitMode, splitIdx);
            if isempty(Zuse), continue; end

            nTrial = size(Zuse,1);
            hitFA = get_str_field(Luse, 'hitFA', nTrial, "Other");

            switch outcomeName
                case 'All', mask = true(nTrial,1);
                case 'Hit', mask = (hitFA=="Hit");
                case 'FA',  mask = (hitFA=="FA");
                otherwise,  mask = true(nTrial,1);
            end

            if ~any(mask), continue; end
            allSessMean(jj,:) = mean(Zuse(mask,:), 1, 'omitnan');
        end

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
        if all(isnan(ySem)), return; end
        upper = yMean + ySem;
        lower = yMean - ySem;
        x = [t, fliplr(t)];
        y = [upper, fliplr(lower)];
        p = fill(ax, x, y, color, 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        uistack(p, 'bottom');
    end

    function s = get_str_field(labels, fn, nTrial, defaultVal)
        if isfield(labels, fn) && ~isempty(labels.(fn))
            v = labels.(fn);
            if isstring(v), s = v(:);
            elseif iscell(v), s = string(v(:));
            else, s = string(v(:));
            end
            if numel(s) ~= nTrial
                s = repmat(string(defaultVal), nTrial, 1);
            end
        else
            s = repmat(string(defaultVal), nTrial, 1);
        end
    end

    function cLight = make_lighter(cBase)
        alpha = 0.5;
        cLight = (1-alpha)*cBase + alpha*[1 1 1];
    end

    function cmap = make_genotype_palette(baseColor, n)
        if n <= 1
            cmap = baseColor;
            return;
        end
        cmap = zeros(n,3);
        for k = 1:n
            a = (k-1) / max(1, (n-1));
            cmap(k,:) = (1-a)*[1 1 1] + a*baseColor;
        end
    end

    function cmapStruct = build_group_color_map(gNames)
        gNames = cellstr(gNames(:));
        wtIdx = []; fxIdx = []; unkIdx = [];

        for i = 1:numel(gNames)
            k = canonKey(gNames{i});
            if startsWith(k,'WT_')
                wtIdx(end+1) = i; 
            elseif startsWith(k,'FX_')
                fxIdx(end+1) = i; 
            else
                unkIdx(end+1) = i; 
            end
        end

        cmapStruct = struct();

        if ~isempty(wtIdx)
            hues = linspace(0.55, 0.75, numel(wtIdx));
            sats = linspace(0.75, 0.95, numel(wtIdx));
            vals = linspace(0.85, 0.70, numel(wtIdx));
            for ii = 1:numel(wtIdx)
                k = canonKey(gNames{wtIdx(ii)});
                cmapStruct.(matlab.lang.makeValidName(k)) = hsv2rgb([hues(ii), sats(ii), vals(ii)]);
            end
        end

        if ~isempty(fxIdx)
            hues = linspace(0.02, 0.12, numel(fxIdx));
            sats = linspace(0.80, 0.98, numel(fxIdx));
            vals = linspace(0.90, 0.75, numel(fxIdx));
            for ii = 1:numel(fxIdx)
                k = canonKey(gNames{fxIdx(ii)});
                cmapStruct.(matlab.lang.makeValidName(k)) = hsv2rgb([hues(ii), sats(ii), vals(ii)]);
            end
        end

        if ~isempty(unkIdx)
            vals = linspace(0.35, 0.75, numel(unkIdx));
            for ii = 1:numel(unkIdx)
                k = canonKey(gNames{unkIdx(ii)});
                cmapStruct.(matlab.lang.makeValidName(k)) = [1 1 1]*vals(ii);
            end
        end

        for i = 1:numel(gNames)
            k = canonKey(gNames{i});
            fn = matlab.lang.makeValidName(k);
            if ~isfield(cmapStruct, fn)
                cmapStruct.(fn) = [0.3 0.3 0.3];
            end
        end
    end

    function val = sanitize_popup_value(h)
        items = get(h, 'String');
        n = control_length(items);
        if n < 1
            set(h, 'String', {''}, 'Value', 1);
            val = 1;
            return;
        end

        val = get(h, 'Value');
        if isempty(val) || ~isscalar(val) || ~isfinite(val)
            val = 1;
        end

        val = max(1, min(n, round(double(val))));
        if get(h, 'Value') ~= val
            set(h, 'Value', val);
        end
    end

    function val = sanitize_listbox_value(h)
        items = get(h, 'String');
        n = control_length(items);
        val = get(h, 'Value');

        if n < 1
            set(h, 'String', {''}, 'Value', 1);
            val = 1;
            return;
        end

        if isempty(val)
            val = [];
            return;
        end

        val = unique(round(double(val(:)')));
        val = val(isfinite(val) & val >= 1 & val <= n);

        if isempty(val)
            set(h, 'Value', []);
            return;
        end

        set(h, 'Value', val);
    end

    function set_listbox_contents(h, items, defaultValue)
        if nargin < 3
            defaultValue = [];
        end

        if isempty(items)
            items = {''};
            defaultValue = 1;
        end

        set(h, 'String', items);

        if isempty(defaultValue)
            set(h, 'Value', []);
        else
            n = control_length(items);
            set(h, 'Value', max(1, min(n, defaultValue)));
        end
    end

    function n = control_length(items)
        if ischar(items)
            n = size(items, 1);
        elseif isstring(items) || iscell(items)
            n = numel(items);
        else
            n = numel(items);
        end
    end

end
