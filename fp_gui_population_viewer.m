function fp_gui_population_viewer(rootDir)
% FP_GUI_POPULATION_VIEWER
% Interactive viewer for fiber photometry population traces.
%
% Rebuilt entrypoint for the current repo layout:
%   - loads processed session outputs from Results/session/sub_*.mat
%   - groups sessions with fp_build_context_groups
%   - supports single-session, group-mean, and group-vs-group plotting
%   - computes quick AUC summaries over user-defined reaction/reward windows

    clc;

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(mfilename('fullpath'));
    end

    [allSubs, ~] = fp_collect_all_sub(rootDir);
    if isempty(allSubs)
        error('fp_gui_population_viewer:NoSubs', ...
            'No processed sessions found under %s.', fullfile(rootDir, 'Results', 'session'));
    end

    [ctxGroups, groupNames] = fp_build_context_groups(allSubs);
    if isempty(groupNames)
        error('fp_gui_population_viewer:NoContextGroups', ...
            'No context-based groups were built from the processed sessions.');
    end

    groupNames = cellstr(groupNames(:));
    canonKey = @(k) canonical_group_key(k);
    keyField = @(k) matlab.lang.makeValidName(canonKey(k));

    tRef = ctxGroups.(canonKey(groupNames{1}))(1).t(:)';
    defaultXLim = [-2 10];
    defaultYLim = [-1.5 0.5];
    groupNames2 = [{'<none>'}; groupNames(:)];

    state = struct();
    state.currentXLim = defaultXLim;
    state.currentYLim = defaultYLim;
    state.manualAxes = false;
    state.lastSummaryHeaders = {};
    state.lastSummaryData = {};

    fig = figure('Name', 'FP Population Viewer', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Units', 'normalized', ...
        'Position', [0.04 0.06 0.92 0.86]);

    autoColorMap = build_group_color_map(groupNames);
    setappdata(fig, 'autoColorMap', autoColorMap);
    setappdata(fig, 'groupColorMap', autoColorMap);

    plotPanel = uipanel(fig, ...
        'Units', 'normalized', ...
        'Position', [0.30 0.05 0.51 0.89], ...
        'BackgroundColor', 'w', ...
        'BorderType', 'none');

    rightPanel = uipanel(fig, ...
        'Units', 'normalized', ...
        'Position', [0.82 0.05 0.16 0.89], ...
        'BackgroundColor', 'w', ...
        'BorderType', 'none');

    mainAxes = build_plot_axes(1);

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.90 0.25 0.03], ...
        'String', 'Group 1 (Genotype_Region_Context)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupGroup1 = uicontrol(fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.86 0.25 0.04], ...
        'String', groupNames, ...
        'BackgroundColor', 'w', ...
        'Callback', @onGroup1Changed);

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.82 0.12 0.03], ...
        'String', 'Sessions', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    listSessions1 = uicontrol(fig, 'Style', 'listbox', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.62 0.25 0.20], ...
        'Max', 999, ...
        'Min', 0, ...
        'Tag', 'listSessions1', ...
        'BackgroundColor', 'w', ...
        'Callback', @onSplitModeChanged);

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.58 0.12 0.03], ...
        'String', 'Animals (G1)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    listAnimals1 = uitable(fig, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.43 0.25 0.15], ...
        'Tag', 'listAnimals1', ...
        'BackgroundColor', 'w', ...
        'Data', cell(0, 2), ...
        'ColumnName', {'Use', 'Animal'}, ...
        'ColumnEditable', [true false], ...
        'ColumnFormat', {'logical', 'char'}, ...
        'RowName', []);

    modeBG = uibuttongroup(fig, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.29 0.25 0.12], ...
        'Title', 'Mode', ...
        'BackgroundColor', 'w');

    rbSingle = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.67 0.9 0.25], ...
        'String', 'Single session', ...
        'Tag', 'single', ...
        'BackgroundColor', 'w');

    rbGroupMean = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.37 0.9 0.25], ...
        'String', 'Group mean', ...
        'Tag', 'groupmean', ...
        'BackgroundColor', 'w');

    rbGroup12 = uicontrol(modeBG, 'Style', 'radiobutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.07 0.9 0.25], ...
        'String', 'Group 1 vs Group 2', ...
        'Tag', 'group12', ...
        'BackgroundColor', 'w');

    modeBG.SelectedObject = rbGroup12;

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.25 0.25 0.03], ...
        'String', 'Group 2 (comparison)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupGroup2 = uicontrol(fig, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.21 0.25 0.04], ...
        'String', groupNames2, ...
        'Tag', 'popupGroup2', ...
        'BackgroundColor', 'w', ...
        'Value', min(2, numel(groupNames2)), ...
        'Callback', @onGroup2Changed);

    uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.17 0.12 0.03], ...
        'String', 'Animals (G2)', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    listAnimals2 = uitable(fig, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.04 0.25 0.13], ...
        'Tag', 'listAnimals2', ...
        'BackgroundColor', 'w', ...
        'Data', cell(0, 2), ...
        'ColumnName', {'Use', 'Animal'}, ...
        'ColumnEditable', [true false], ...
        'ColumnFormat', {'logical', 'char'}, ...
        'RowName', []);

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.95 0.88 0.04], ...
        'String', 'Trace Types', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    cbAll = uicontrol(rightPanel, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.91 0.26 0.04], ...
        'String', 'All', ...
        'Tag', 'cbAll', ...
        'Value', 0, ...
        'BackgroundColor', 'w');

    cbHit = uicontrol(rightPanel, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.36 0.91 0.26 0.04], ...
        'String', 'Hit', ...
        'Tag', 'cbHit', ...
        'Value', 1, ...
        'BackgroundColor', 'w');

    cbFA = uicontrol(rightPanel, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.66 0.91 0.26 0.04], ...
        'String', 'FA', ...
        'Tag', 'cbFA', ...
        'Value', 1, ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.84 0.88 0.04], ...
        'String', 'Split / Filter', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupSplitMode = uicontrol(rightPanel, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.80 0.88 0.05], ...
        'String', {'All trials', 'Tone (1..7)', 'Symmetric Octave (4 bins)'}, ...
        'Tag', 'popupSplitMode', ...
        'BackgroundColor', 'w', ...
        'Callback', @onSplitModeChanged);

    popupSplitIdx = uicontrol(rightPanel, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.74 0.88 0.05], ...
        'String', {'All selected'}, ...
        'Tag', 'popupSplitIdx', ...
        'BackgroundColor', 'w');

    cbTileSplit = uicontrol(rightPanel, 'Style', 'checkbox', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.69 0.88 0.04], ...
        'String', 'Tile split groups', ...
        'Tag', 'cbTileSplit', ...
        'Value', 0, ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.63 0.88 0.04], ...
        'String', 'Axes [Xmin Xmax ; Ymin Ymax]', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.59 0.08 0.04], ...
        'String', 'X', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editXmin = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.16 0.59 0.26 0.045], ...
        'String', num2str(defaultXLim(1)), ...
        'BackgroundColor', 'w');

    editXmax = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.59 0.26 0.045], ...
        'String', num2str(defaultXLim(2)), ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.54 0.08 0.04], ...
        'String', 'Y', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editYmin = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.16 0.54 0.26 0.045], ...
        'String', num2str(defaultYLim(1)), ...
        'BackgroundColor', 'w');

    editYmax = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.54 0.26 0.045], ...
        'String', num2str(defaultYLim(2)), ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.76 0.54 0.18 0.095], ...
        'String', 'Apply', ...
        'Callback', @onApplyAxes);

    uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.495 0.40 0.04], ...
        'String', 'Pick G1', ...
        'Callback', @onPickColorG1);

    uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.54 0.495 0.40 0.04], ...
        'String', 'Pick G2', ...
        'Callback', @onPickColorG2);

    uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.455 0.88 0.04], ...
        'String', 'Reset Colors', ...
        'Callback', @onResetColors);

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.405 0.88 0.04], ...
        'String', 'AUC Windows', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.365 0.36 0.04], ...
        'String', 'React [s]', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editReactStart = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.46 0.365 0.20 0.045], ...
        'String', '0', ...
        'Tag', 'editReactStart', ...
        'BackgroundColor', 'w');

    editReactEnd = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.72 0.365 0.20 0.045], ...
        'String', '2', ...
        'Tag', 'editReactEnd', ...
        'BackgroundColor', 'w');

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.315 0.36 0.04], ...
        'String', 'Reward [s]', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editRewardStart = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.46 0.315 0.20 0.045], ...
        'String', '2', ...
        'Tag', 'editRewardStart', ...
        'BackgroundColor', 'w');

    editRewardEnd = uicontrol(rightPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.72 0.315 0.20 0.045], ...
        'String', '5', ...
        'Tag', 'editRewardEnd', ...
        'BackgroundColor', 'w');

    btnPlot = uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.245 0.40 0.055], ...
        'String', 'Plot', ...
        'Tag', 'btnPlot', ...
        'FontWeight', 'bold', ...
        'Callback', @onPlot);

    uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.54 0.245 0.40 0.055], ...
        'String', 'Save Figure...', ...
        'Callback', @onSaveFigure);

    uicontrol(rightPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.195 0.88 0.04], ...
        'String', 'Summary', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    tableSummary = uitable(rightPanel, ...
        'Units', 'normalized', ...
        'Position', [0.06 0.045 0.88 0.145], ...
        'Tag', 'tableSummary', ...
        'Data', {}, ...
        'ColumnName', {'Scope', 'Split', 'Group', 'Outcome', 'NSess', 'NTrial', 'ReactAUC', 'RewardAUC'});

    btnExportSummary = uicontrol(rightPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.06 0.005 0.88 0.03], ...
        'String', 'Export Summary CSV...', ...
        'Tag', 'btnExportSummary', ...
        'Callback', @onExportSummary);

    defaultGroup1Idx = find_group_index(groupNames, 'WT_AUX_CleanOnly');
    if ~isempty(defaultGroup1Idx)
        set(popupGroup1, 'Value', defaultGroup1Idx);
    end

    defaultGroup2Idx = find_group_index(groupNames2, 'FX_AUX_CleanOnly');
    if ~isempty(defaultGroup2Idx)
        set(popupGroup2, 'Value', defaultGroup2Idx);
    end

    onGroup1Changed();
    onGroup2Changed();

    function onGroup1Changed(~, ~)
        key = canonKey(groupNames{popupGroup1.Value});
        sessions = ctxGroups.(key);

        sessionLabels = build_session_labels(sessions);
        animalLabels = unique_stable(get_session_animals(sessions));

        if isempty(sessionLabels)
            sessionLabels = {'<no session>'};
        end
        if isempty(animalLabels)
            animalLabels = {'<none>'};
        end

        set(listSessions1, 'String', sessionLabels, ...
            'Value', valid_multi_selection(numel(sessionLabels), true));
        set_animal_table(listAnimals1, animalLabels, true);

        onSplitModeChanged();
    end

    function onGroup2Changed(~, ~)
        [~, sessions] = get_group2_selection();
        animalLabels = unique_stable(get_session_animals(sessions));
        if isempty(animalLabels)
            animalLabels = {'<none>'};
        end

        set_animal_table(listAnimals2, animalLabels, true);
    end

    function onSplitModeChanged(~, ~)
        switch get(popupSplitMode, 'Value')
            case 1
                set(popupSplitIdx, 'String', {'All'}, 'Value', 1, 'Enable', 'off');
                set(cbTileSplit, 'Value', 0);
            case 2
                set(popupSplitIdx, 'String', [{'All'}, cellstr(compose('Tone %d', 1:7))], ...
                    'Value', 1, 'Enable', 'on');
            case 3
                set(popupSplitIdx, 'String', {'All', 'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'}, ...
                    'Value', 1, 'Enable', 'on');
        end
    end

    function onApplyAxes(~, ~)
        xmin = str2double(get(editXmin, 'String'));
        xmax = str2double(get(editXmax, 'String'));
        ymin = str2double(get(editYmin, 'String'));
        ymax = str2double(get(editYmax, 'String'));

        if any(isnan([xmin xmax ymin ymax])) || xmin >= xmax || ymin >= ymax
            return;
        end

        state.currentXLim = [xmin xmax];
        state.currentYLim = [ymin ymax];
        state.manualAxes = true;

        apply_axes_state(mainAxes);
    end

    function onPickColorG1(~, ~)
        key = canonKey(groupNames{popupGroup1.Value});
        cmap = getappdata(fig, 'groupColorMap');
        f = keyField(key);
        if ~isfield(cmap, f)
            cmap.(f) = get_base_color_from_key(key);
        end

        picked = uisetcolor(cmap.(f), sprintf('Pick color for Group 1: %s', key));
        if numel(picked) == 3
            cmap.(f) = picked;
            setappdata(fig, 'groupColorMap', cmap);
        end
    end

    function onPickColorG2(~, ~)
        idx = popupGroup2.Value;
        if idx <= 1
            return;
        end

        key = canonKey(groupNames2{idx});
        cmap = getappdata(fig, 'groupColorMap');
        f = keyField(key);
        if ~isfield(cmap, f)
            cmap.(f) = get_base_color_from_key(key);
        end

        picked = uisetcolor(cmap.(f), sprintf('Pick color for Group 2: %s', key));
        if numel(picked) == 3
            cmap.(f) = picked;
            setappdata(fig, 'groupColorMap', cmap);
        end
    end

    function onResetColors(~, ~)
        setappdata(fig, 'groupColorMap', getappdata(fig, 'autoColorMap'));
    end

    function onSaveFigure(~, ~)
        [fileName, filePath] = uiputfile({'*.png'; '*.pdf'; '*.fig'}, 'Save figure as');
        if isequal(fileName, 0)
            return;
        end

        outFile = fullfile(filePath, fileName);
        [~, ~, ext] = fileparts(outFile);
        if isempty(ext)
            outFile = [outFile '.png'];
            ext = '.png';
        end

        switch lower(ext)
            case '.fig'
                savefig(fig, outFile);
            otherwise
                saveas(fig, outFile);
        end
    end

    function onExportSummary(~, ~)
        if isempty(state.lastSummaryData)
            return;
        end

        [fileName, filePath] = uiputfile({'*.csv'}, 'Export summary CSV');
        if isequal(fileName, 0)
            return;
        end

        outFile = fullfile(filePath, fileName);
        if numel(outFile) < 4 || ~strcmpi(outFile(end-3:end), '.csv')
            outFile = [outFile '.csv'];
        end

        write_simple_csv(outFile, state.lastSummaryHeaders, state.lastSummaryData);
    end

    function onPlot(~, ~)
        showAll = logical(get(cbAll, 'Value'));
        showHit = logical(get(cbHit, 'Value'));
        showFA = logical(get(cbFA, 'Value'));
        if ~showAll && ~showHit && ~showFA
            return;
        end

        reactWin = parse_window(editReactStart, editReactEnd, [0 2]);
        rewardWin = parse_window(editRewardStart, editRewardEnd, [2 5]);

        modeTag = get(modeBG.SelectedObject, 'Tag');
        keyG1 = canonKey(groupNames{popupGroup1.Value});
        sessionsG1 = get_filtered_sessions(keyG1, listSessions1, listAnimals1);

        [keyG2, sessionsG2] = get_group2_selection();
        sessionsG2 = filter_sessions_by_animals(sessionsG2, listAnimals2);

        splitModeValue = get(popupSplitMode, 'Value');
        splitIdxValue = get(popupSplitIdx, 'Value');
        tileSplit = logical(get(cbTileSplit, 'Value')) && splitModeValue ~= 1;

        if tileSplit
            [splitLabels, splitIdxList] = split_bin_labels(splitModeValue);
        else
            splitLabels = {split_label(splitModeValue, splitIdxValue)};
            splitIdxList = splitIdxValue;
        end

        mainAxes = build_plot_axes(numel(splitLabels));
        add_plot_heading(compose_plot_heading(modeTag, keyG1, keyG2, splitModeValue, tileSplit), numel(splitLabels) > 1);

        summaryHeaders = {'Scope', 'Split', 'Group', 'Outcome', 'NSess', 'NTrial', 'ReactAUC', 'RewardAUC'};
        summaryRows = cell(0, numel(summaryHeaders));

        for iax = 1:numel(mainAxes)
            ax = mainAxes(iax);
            splitLabel = splitLabels{iax};
            splitIdxThis = splitIdxList(iax);
            sess1This = sessionsG1;
            sess2This = sessionsG2;
            showLegendThisAx = (numel(mainAxes) == 1) || (iax == 1);
            compactLegend = numel(mainAxes) > 1;

            configure_axis(ax);

            switch modeTag
                case 'single'
                    summaryRows = [summaryRows; ...
                        plot_single_mode(ax, sess1This, keyG1, splitLabel, splitModeValue, splitIdxThis, ...
                            showAll, showHit, showFA, reactWin, rewardWin, showLegendThisAx, compactLegend)]; %#ok<AGROW>

                case 'groupmean'
                    summaryRows = [summaryRows; ...
                        plot_groupmean_mode(ax, sess1This, keyG1, splitLabel, splitModeValue, splitIdxThis, ...
                            showAll, showHit, showFA, reactWin, rewardWin, showLegendThisAx, compactLegend)]; %#ok<AGROW>

                case 'group12'
                    summaryRows = [summaryRows; ...
                        plot_group12_mode(ax, sess1This, keyG1, sess2This, keyG2, splitLabel, splitModeValue, splitIdxThis, ...
                            showAll, showHit, showFA, reactWin, rewardWin, showLegendThisAx, compactLegend)]; %#ok<AGROW>
            end

            add_reference_lines(ax);
        end

        if isempty(summaryRows)
            summaryRows = {'No data', '', '', '', 0, 0, NaN, NaN};
        end

        state.lastSummaryHeaders = summaryHeaders;
        state.lastSummaryData = summaryRows;
        set(tableSummary, 'Data', summaryRows, 'ColumnName', summaryHeaders);
    end

    function ax = build_plot_axes(nAxes)
        delete(get(plotPanel, 'Children'));
        delete(findall(fig, 'Type', 'legend'));

        if nargin < 1 || isempty(nAxes) || nAxes < 1
            nAxes = 1;
        end

        positions = compute_axes_positions(nAxes);
        ax = gobjects(nAxes, 1);
        for ii = 1:nAxes
            ax(ii) = axes('Parent', plotPanel, ...
                'Units', 'normalized', ...
                'Position', positions(ii, :), ...
                'Box', 'on', ...
                'FontSize', 10);
        end
        apply_axes_state(ax);
    end

    function add_plot_heading(titleText, compactMode)
        if nargin < 2
            compactMode = false;
        end

        fontSize = 12;
        fontWeight = 'bold';
        yPos = 0.95;
        if compactMode
            fontSize = 11;
            yPos = 0.965;
        end

        uicontrol(plotPanel, 'Style', 'text', ...
            'Units', 'normalized', ...
            'Position', [0.03 yPos 0.94 0.04], ...
            'String', titleText, ...
            'HorizontalAlignment', 'center', ...
            'FontWeight', fontWeight, ...
            'FontSize', fontSize, ...
            'BackgroundColor', 'w');
    end

    function apply_axes_state(ax)
        for ii = 1:numel(ax)
            if ~ishandle(ax(ii))
                continue;
            end
            if state.manualAxes
                set(ax(ii), 'XLim', state.currentXLim, 'YLim', state.currentYLim);
            else
                set(ax(ii), 'XLim', defaultXLim, 'YLim', defaultYLim);
            end
            set(ax(ii), 'XLimMode', 'manual', 'YLimMode', 'manual');
        end
    end

    function configure_axis(ax)
        cla(ax, 'reset');
        hold(ax, 'on');
        grid(ax, 'on');
        box(ax, 'on');
        xlabel(ax, 'Time (s)');
        ylabel(ax, 'z (aligned at t=0)');
        apply_axes_state(ax);
    end

    function add_reference_lines(ax)
        yLimits = get(ax, 'YLim');
        xLimits = get(ax, 'XLim');
        line(ax, [0 0], yLimits, 'Color', [0.5 0.5 0.5], 'LineStyle', '--', 'HandleVisibility', 'off');
        line(ax, xLimits, [0 0], 'Color', [0.7 0.7 0.7], 'LineStyle', ':', 'HandleVisibility', 'off');
    end

    function rows = plot_single_mode(ax, sessions, keyG1Local, splitTitle, splitMode, splitIdx, showAllLocal, showHitLocal, showFALocal, reactWin, rewardWin, showLegend, compactLegend)
        rows = cell(0, 8);

        if isempty(sessions)
            title(ax, splitTitle, 'Interpreter', 'none', 'FontSize', 10);
            return;
        end

        baseColor = getGroupColor(keyG1Local);
        cmap = make_genotype_palette(baseColor, numel(sessions));
        legendHandles = [];
        legendLabels = {};

        for isess = 1:numel(sessions)
            sess = sessions(isess);
            sessLabel = build_session_label(sess, isess);
            thisColor = cmap(isess, :);

            if showAllLocal
                [traceMean, ~, nTrials] = session_trace(sess, 'All', splitMode, splitIdx);
                if nTrials > 0
                    y = align_at_t0(sess.t, traceMean);
                    h = plot(ax, sess.t, y, 'Color', thisColor, 'LineWidth', 1.4, 'LineStyle', '-');
                    legendHandles(end+1) = h; %#ok<AGROW>
                    legendLabels{end+1} = sprintf('%s - All %s', sessLabel, format_n_trials_label(nTrials)); %#ok<AGROW>
                    rows(end+1, :) = build_summary_row('single', splitTitle, sessLabel, 'All', sess, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
                end
            end

            if showHitLocal
                [traceMean, ~, nTrials] = session_trace(sess, 'Hit', splitMode, splitIdx);
                if nTrials > 0
                    h = plot(ax, sess.t, align_at_t0(sess.t, traceMean), ...
                        'Color', thisColor, 'LineWidth', 1.6, 'LineStyle', '-');
                    legendHandles(end+1) = h; %#ok<AGROW>
                    legendLabels{end+1} = sprintf('%s - Hit %s', sessLabel, format_n_trials_label(nTrials)); %#ok<AGROW>
                    rows(end+1, :) = build_summary_row('single', splitTitle, sessLabel, 'Hit', sess, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
                end
            end

            if showFALocal
                [traceMean, ~, nTrials] = session_trace(sess, 'FA', splitMode, splitIdx);
                if nTrials > 0
                    h = plot(ax, sess.t, align_at_t0(sess.t, traceMean), ...
                        'Color', make_lighter(thisColor), 'LineWidth', 1.6, 'LineStyle', '--');
                    legendHandles(end+1) = h; %#ok<AGROW>
                    legendLabels{end+1} = sprintf('%s - FA %s', sessLabel, format_n_trials_label(nTrials)); %#ok<AGROW>
                    rows(end+1, :) = build_summary_row('single', splitTitle, sessLabel, 'FA', sess, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
                end
            end
        end

        apply_plot_legend(ax, legendHandles, legendLabels, showLegend, compactLegend);
        title(ax, splitTitle, 'Interpreter', 'none', 'FontSize', 10);
    end

    function rows = plot_groupmean_mode(ax, sessions, keyG1Local, splitTitle, splitMode, splitIdx, showAllLocal, showHitLocal, showFALocal, reactWin, rewardWin, showLegend, compactLegend)
        rows = cell(0, 8);
        legendHandles = [];
        legendLabels = {};

        baseColor = getGroupColor(keyG1Local);
        faColor = make_lighter(baseColor);
        allColor = [0.35 0.35 0.35];

        if showAllLocal
            [mTrace, sTrace, nSess] = aggregate_trace(sessions, 'All', splitMode, splitIdx);
            if nSess > 0
                h = plot(ax, tRef, align_at_t0(tRef, mTrace), 'Color', allColor, 'LineWidth', 1.8);
                add_sem_patch(ax, tRef, align_at_t0(tRef, mTrace), sTrace, allColor);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - All %s', keyG1Local, format_n_animals_label(nSess)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('groupmean', splitTitle, keyG1Local, 'All', sessions, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        if showHitLocal
            [mTrace, sTrace, nSess] = aggregate_trace(sessions, 'Hit', splitMode, splitIdx);
            if nSess > 0
                h = plot(ax, tRef, align_at_t0(tRef, mTrace), 'Color', baseColor, 'LineWidth', 2.0);
                add_sem_patch(ax, tRef, align_at_t0(tRef, mTrace), sTrace, baseColor);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - Hit %s', keyG1Local, format_n_animals_label(nSess)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('groupmean', splitTitle, keyG1Local, 'Hit', sessions, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        if showFALocal
            [mTrace, sTrace, nSess] = aggregate_trace(sessions, 'FA', splitMode, splitIdx);
            if nSess > 0
                h = plot(ax, tRef, align_at_t0(tRef, mTrace), 'Color', faColor, 'LineWidth', 2.0, 'LineStyle', '--');
                add_sem_patch(ax, tRef, align_at_t0(tRef, mTrace), sTrace, faColor);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - FA %s', keyG1Local, format_n_animals_label(nSess)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('groupmean', splitTitle, keyG1Local, 'FA', sessions, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        apply_plot_legend(ax, legendHandles, legendLabels, showLegend, compactLegend);
        title(ax, splitTitle, 'Interpreter', 'none', 'FontSize', 10);
    end

    function rows = plot_group12_mode(ax, sessions1, keyG1Local, sessions2, keyG2Local, splitTitle, splitMode, splitIdx, ...
            showAllLocal, showHitLocal, showFALocal, reactWin, rewardWin, showLegend, compactLegend)
        rows = cell(0, 8);
        legendHandles = [];
        legendLabels = {};

        baseColor1 = getGroupColor(keyG1Local);
        if isempty(keyG2Local)
            baseColor2 = [0.5 0.5 0.5];
        else
            baseColor2 = getGroupColor(keyG2Local);
        end

        faColor1 = make_lighter(baseColor1);
        faColor2 = make_lighter(baseColor2);

        if showAllLocal
            [m1, s1, n1] = aggregate_trace(sessions1, 'All', splitMode, splitIdx);
            [m2, s2, n2] = aggregate_trace(sessions2, 'All', splitMode, splitIdx);
            if n1 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m1), 'Color', [0.35 0.35 0.35], 'LineWidth', 1.8);
                add_sem_patch(ax, tRef, align_at_t0(tRef, m1), s1, [0.35 0.35 0.35]);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - All %s', keyG1Local, format_n_animals_label(n1)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG1Local, 'All', sessions1, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
            if n2 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m2), 'Color', [0.60 0.60 0.60], 'LineWidth', 1.8);
                add_sem_patch(ax, tRef, align_at_t0(tRef, m2), s2, [0.60 0.60 0.60]);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - All %s', keyG2Local, format_n_animals_label(n2)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG2Local, 'All', sessions2, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        if showHitLocal
            [m1, s1, n1] = aggregate_trace(sessions1, 'Hit', splitMode, splitIdx);
            [m2, s2, n2] = aggregate_trace(sessions2, 'Hit', splitMode, splitIdx);
            if n1 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m1), 'Color', baseColor1, 'LineWidth', 2.0);
                add_sem_patch(ax, tRef, align_at_t0(tRef, m1), s1, baseColor1);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - Hit %s', keyG1Local, format_n_animals_label(n1)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG1Local, 'Hit', sessions1, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
            if n2 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m2), 'Color', baseColor2, 'LineWidth', 2.0);
                add_sem_patch(ax, tRef, align_at_t0(tRef, m2), s2, baseColor2);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - Hit %s', keyG2Local, format_n_animals_label(n2)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG2Local, 'Hit', sessions2, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        if showFALocal
            [m1, s1, n1] = aggregate_trace(sessions1, 'FA', splitMode, splitIdx);
            [m2, s2, n2] = aggregate_trace(sessions2, 'FA', splitMode, splitIdx);
            if n1 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m1), 'Color', faColor1, 'LineWidth', 2.0, 'LineStyle', '--');
                add_sem_patch(ax, tRef, align_at_t0(tRef, m1), s1, faColor1);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - FA %s', keyG1Local, format_n_animals_label(n1)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG1Local, 'FA', sessions1, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
            if n2 > 0
                h = plot(ax, tRef, align_at_t0(tRef, m2), 'Color', faColor2, 'LineWidth', 2.0, 'LineStyle', '--');
                add_sem_patch(ax, tRef, align_at_t0(tRef, m2), s2, faColor2);
                legendHandles(end+1) = h; %#ok<AGROW>
                legendLabels{end+1} = sprintf('%s - FA %s', keyG2Local, format_n_animals_label(n2)); %#ok<AGROW>
                rows(end+1, :) = build_summary_row('group12', splitTitle, keyG2Local, 'FA', sessions2, splitMode, splitIdx, reactWin, rewardWin); %#ok<AGROW>
            end
        end

        apply_plot_legend(ax, legendHandles, legendLabels, showLegend, compactLegend);

        if isempty(keyG2Local)
            title(ax, splitTitle, 'Interpreter', 'none', 'FontSize', 10);
        else
            title(ax, splitTitle, 'Interpreter', 'none', 'FontSize', 10);
        end
    end

    function rows = build_summary_row(scopeLabel, splitLabel, groupLabel, outcomeName, sessions, splitMode, splitIdx, reactWin, rewardWin)
        if isempty(sessions)
            rows = {scopeLabel, splitLabel, groupLabel, outcomeName, 0, 0, NaN, NaN};
            return;
        end

        [reactAUC, rewardAUC, nTrials] = compute_auc_summary(sessions, outcomeName, splitMode, splitIdx, reactWin, rewardWin);
        rows = {scopeLabel, splitLabel, groupLabel, outcomeName, numel(sessions), nTrials, reactAUC, rewardAUC};
    end

    function [keyOut, sessionsOut] = get_group2_selection()
        idx = popupGroup2.Value;
        if idx <= 1
            keyOut = '';
            sessionsOut = struct([]);
            return;
        end
        keyOut = canonKey(groupNames2{idx});
        sessionsOut = ctxGroups.(keyOut);
    end

    function sessionsOut = get_filtered_sessions(groupKey, sessionCtrl, animalCtrl)
        sessionsOut = ctxGroups.(groupKey);

        keepSession = false(1, numel(sessionsOut));
        idxSel = normalize_index_selection(sessionCtrl, numel(sessionsOut));
        keepSession(idxSel) = true;
        sessionsOut = sessionsOut(keepSession);

        sessionsOut = filter_sessions_by_animals(sessionsOut, animalCtrl);
    end

    function colorValue = getGroupColor(key)
        cmap = getappdata(fig, 'groupColorMap');
        key = canonKey(key);
        f = keyField(key);
        if isfield(cmap, f)
            colorValue = cmap.(f);
        else
            colorValue = get_base_color_from_key(key);
        end
    end

    function apply_plot_legend(ax, legendHandles, legendLabels, showLegend, compactLegend)
        if nargin < 4 || ~showLegend || isempty(legendHandles)
            return;
        end

        if nargin >= 5 && compactLegend
            lgd = legend(ax, legendHandles, legendLabels, ...
                'Interpreter', 'none', ...
                'Location', 'southoutside', ...
                'FontSize', 7, ...
                'Box', 'off');
            set(lgd, 'Units', 'normalized');
            panelPos = get(plotPanel, 'Position');
            set(lgd, 'Position', [panelPos(1) + 0.06 * panelPos(3), ...
                panelPos(2) + 0.01 * panelPos(4), ...
                0.88 * panelPos(3), ...
                0.035 * panelPos(4)]);
        else
            legend(ax, legendHandles, legendLabels, ...
                'Interpreter', 'none', ...
                'Location', 'best', ...
                'FontSize', 8);
        end
    end
end

function sessionLabels = build_session_labels(sessions)
    sessionLabels = cell(numel(sessions), 1);
    for ii = 1:numel(sessions)
        sessionLabels{ii} = build_session_label(sessions(ii), ii);
    end
end

function label = build_session_label(sess, idx)
    idStr = get_session_id(sess);
    dateStr = '';
    if isfield(sess.meta, 'date') && ~isempty(sess.meta.date)
        dateStr = char(string(sess.meta.date));
    end

    if isempty(idStr)
        idStr = sprintf('Session%d', idx);
    end

    if isempty(dateStr)
        label = idStr;
    else
        label = sprintf('%s | %s', idStr, dateStr);
    end
end

function animals = get_session_animals(sessions)
    animals = cell(numel(sessions), 1);
    for ii = 1:numel(sessions)
        animals{ii} = get_session_id(sessions(ii));
    end
end

function idStr = get_session_id(sess)
    idStr = '';
    if isfield(sess, 'meta') && isfield(sess.meta, 'ID') && ~isempty(sess.meta.ID)
        idStr = char(string(sess.meta.ID));
    elseif isfield(sess, 'meta') && isfield(sess.meta, 'AnimalID') && ~isempty(sess.meta.AnimalID)
        idStr = char(string(sess.meta.AnimalID));
    end
end

function out = unique_stable(items)
    if isempty(items)
        out = {};
        return;
    end
    items = items(:);
    keep = ~cellfun(@isempty, items);
    items = items(keep);
    if isempty(items)
        out = {};
        return;
    end
    [~, ia] = unique(items, 'stable');
    out = items(sort(ia));
end

function idx = find_group_index(items, target)
    idx = [];
    if isempty(items)
        return;
    end

    items = cellstr(string(items(:)));
    target = canonical_group_key(target);
    for ii = 1:numel(items)
        if strcmp(canonical_group_key(items{ii}), target)
            idx = ii;
            return;
        end
    end
end

function set_animal_table(tbl, animalLabels, checkedByDefault)
    if nargin < 3
        checkedByDefault = true;
    end

    if isempty(animalLabels)
        animalLabels = {'<none>'};
        checkedFlags = false;
    else
        checkedFlags = repmat(logical(checkedByDefault), numel(animalLabels), 1);
    end

    data = cell(numel(animalLabels), 2);
    for ii = 1:numel(animalLabels)
        data{ii, 1} = checkedFlags(min(ii, numel(checkedFlags)));
        data{ii, 2} = animalLabels{ii};
    end
    set(tbl, 'Data', data);
end

function selectedAnimals = get_checked_animals(ctrl)
    selectedAnimals = {};

    if isempty(ctrl) || ~ishandle(ctrl)
        return;
    end

    try
        data = get(ctrl, 'Data');
        if iscell(data) && ~isempty(data)
            for ii = 1:size(data, 1)
                isChecked = false;
                if size(data, 2) >= 1 && ~isempty(data{ii, 1})
                    isChecked = logical(data{ii, 1});
                end
                if isChecked && size(data, 2) >= 2
                    label = char(string(data{ii, 2}));
                    if ~isempty(label) && ~strcmp(label, '<none>')
                        selectedAnimals{end+1} = label; %#ok<AGROW>
                    end
                end
            end
            return;
        end
    catch
    end

    animalStrings = get(ctrl, 'String');
    if isempty(animalStrings)
        return;
    end
    if ischar(animalStrings)
        animalStrings = cellstr(animalStrings);
    end

    idxSel = normalize_index_selection(ctrl, numel(animalStrings));
    selectedAnimals = animalStrings(idxSel);
end

function value = valid_multi_selection(nItems, selectAll)
    if nargin < 2
        selectAll = false;
    end
    if nItems <= 0
        value = 1;
    elseif selectAll
        value = 1:nItems;
    else
        value = 1;
    end
end

function idxSel = normalize_index_selection(ctrl, nItems)
    if nItems <= 0
        idxSel = [];
        return;
    end
    idxSel = get(ctrl, 'Value');
    idxSel = idxSel(idxSel >= 1 & idxSel <= nItems);
    if isempty(idxSel)
        idxSel = 1:nItems;
    end
end

function splitItems = build_split_items(sessions, splitModeValue)
    switch splitModeValue
        case 2
            splitItems = unique_stable(get_session_animals(sessions));
        case 3
            splitItems = build_session_labels(sessions);
        otherwise
            splitItems = {'All selected'};
    end
end

function label = format_n_trials_label(nTrials)
    label = sprintf('(n=%d)', nTrials);
end

function label = format_n_animals_label(nAnimals)
    label = sprintf('(n=%d)', nAnimals);
end

function [labels, idxList] = split_bin_labels(splitMode)
    switch splitMode
        case 2
            labels = cell(1, 7);
            idxList = 2:8;
            for ii = 1:7
                labels{ii} = sprintf('Tone %d', ii);
            end
        case 3
            labels = {'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'};
            idxList = 2:5;
        otherwise
            labels = {'All trials'};
            idxList = 1;
    end
end

function splitLabels = get_active_split_labels(sessions, splitModeValue, splitCtrl, tileSplit)
    if splitModeValue == 1
        splitLabels = {'All selected'};
        return;
    end

    allSplit = build_split_items(sessions, splitModeValue);
    if isempty(allSplit)
        splitLabels = {'All selected'};
        return;
    end

    if tileSplit
        splitLabels = allSplit;
    else
        idxSel = normalize_index_selection(splitCtrl, numel(allSplit));
        splitLabels = {allSplit{idxSel(1)}};
    end
end

function lbl = split_label(splitMode, splitIdx)
    switch splitMode
        case 1
            lbl = 'All trials';
        case 2
            if splitIdx == 1
                lbl = 'All tones';
            else
                lbl = sprintf('Tone %d', splitIdx - 1);
            end
        case 3
            if splitIdx == 1
                lbl = 'All octaves';
            else
                names = {'Oct 1 (1&7)', 'Oct 2/3 (2&6)', 'Oct 1/3 (3&5)', 'Oct 0 (4)'};
                kk = splitIdx - 1;
                if kk >= 1 && kk <= numel(names)
                    lbl = names{kk};
                else
                    lbl = sprintf('Oct %d', kk);
                end
            end
        otherwise
            lbl = 'All trials';
    end
end

function [sessionsOut, titleLabel] = apply_split_filter(sessionsIn, splitModeValue, splitLabel)
    sessionsOut = sessionsIn;
    titleLabel = splitLabel;

    if isempty(sessionsIn)
        return;
    end

    switch splitModeValue
        case 2
            mask = false(1, numel(sessionsIn));
            for ii = 1:numel(sessionsIn)
                mask(ii) = strcmp(get_session_id(sessionsIn(ii)), splitLabel);
            end
            sessionsOut = sessionsIn(mask);
            if isempty(titleLabel)
                titleLabel = 'Animal split';
            end

        case 3
            labels = build_session_labels(sessionsIn);
            mask = strcmp(labels, splitLabel);
            sessionsOut = sessionsIn(mask);
            if isempty(titleLabel)
                titleLabel = 'Session split';
            end

        otherwise
            titleLabel = 'All selected';
    end
end

function sessionsOut = filter_sessions_by_animals(sessionsIn, animalCtrl)
    sessionsOut = sessionsIn;
    if isempty(sessionsIn) || isempty(animalCtrl) || ~ishandle(animalCtrl)
        return;
    end

    selectedAnimals = get_checked_animals(animalCtrl);
    if isempty(selectedAnimals)
        return;
    end

    keep = false(1, numel(sessionsIn));
    for ii = 1:numel(sessionsIn)
        keep(ii) = any(strcmp(get_session_id(sessionsIn(ii)), selectedAnimals));
    end
    sessionsOut = sessionsIn(keep);
end

function [traceMean, traceSem, nTrials] = session_trace(sess, outcomeName, splitMode, splitIdx)
    if nargin < 3
        splitMode = 1;
        splitIdx = 1;
    end
    [Zsel, ~, ~] = select_trials_for_outcome(sess, outcomeName, splitMode, splitIdx);
    nTrials = size(Zsel, 1);
    if nTrials == 0
        traceMean = nan(size(sess.t));
        traceSem = nan(size(sess.t));
        return;
    end

    traceMean = mean(Zsel, 1, 'omitnan');
    traceSem = std(Zsel, 0, 1, 'omitnan') ./ sqrt(nTrials);
end

function [mTrace, sTrace, nSessions] = aggregate_trace(sessions, outcomeName, splitMode, splitIdx)
    if isempty(sessions)
        mTrace = nan(1, 0);
        sTrace = nan(1, 0);
        nSessions = 0;
        return;
    end

    tRef = sessions(1).t(:)';
    perSession = nan(numel(sessions), numel(tRef));

    for ii = 1:numel(sessions)
        [traceMean, ~, nTrials] = session_trace(sessions(ii), outcomeName, splitMode, splitIdx);
        if nTrials > 0 && numel(traceMean) == numel(tRef)
            perSession(ii, :) = traceMean;
        end
    end

    valid = ~all(isnan(perSession), 2);
    perSession = perSession(valid, :);
    nSessions = size(perSession, 1);

    if nSessions == 0
        mTrace = nan(size(tRef));
        sTrace = nan(size(tRef));
        return;
    end

    mTrace = mean(perSession, 1, 'omitnan');
    sTrace = std(perSession, 0, 1, 'omitnan') ./ sqrt(nSessions);
end

function [reactAUC, rewardAUC, nTrials] = compute_auc_summary(sessions, outcomeName, splitMode, splitIdx, reactWin, rewardWin)
    reactAll = [];
    rewardAll = [];
    nTrials = 0;

    for ii = 1:numel(sessions)
        [Zsel, labelsSel, metaSel] = select_trials_for_outcome(sessions(ii), outcomeName, splitMode, splitIdx);
        if isempty(Zsel)
            continue;
        end

        data = struct();
        data.z = Zsel;
        data.t = sessions(ii).t(:)';
        data.meta = metaSel;
        data.labels = labelsSel;

        cfg = struct();
        cfg.winNames = {'React', 'Reward'};
        cfg.winRanges = [reactWin; rewardWin];
        cfg.winAreaMode = {'positive-only', 'negative-only'};

        metrics = fp_calc_metrics_auc_peak(data, cfg);
        reactAll = [reactAll; metrics.AUC_trial(:, 1)]; %#ok<AGROW>
        rewardAll = [rewardAll; metrics.AUC_trial(:, 2)]; %#ok<AGROW>
        nTrials = nTrials + size(Zsel, 1);
    end

    reactAUC = mean(reactAll, 'omitnan');
    rewardAUC = mean(rewardAll, 'omitnan');
end

function [Zsel, labelsSel, metaSel] = select_trials_for_outcome(sess, outcomeName, splitMode, splitIdx)
    if nargin < 3
        splitMode = 1;
        splitIdx = 1;
    end

    [Z, labelsWork] = select_trials_with_split(sess, splitMode, splitIdx);
    nTrial = size(Z, 1);
    hitFA = get_label_field(labelsWork, 'hitFA', nTrial, 'Other');

    switch outcomeName
        case 'Hit'
            mask = strcmp(hitFA, 'Hit');
        case 'FA'
            mask = strcmp(hitFA, 'FA');
        otherwise
            mask = true(nTrial, 1);
    end

    Zsel = Z(mask, :);
    labelsSel = subset_labels(labelsWork, mask, nTrial);
    metaSel = sess.meta;
end

function [Zuse, labelsUse] = select_trials_with_split(sessionEntry, splitMode, splitIdx)
    Z0 = sessionEntry.Z;
    labels0 = sessionEntry.labels;

    if isempty(Z0)
        Zuse = [];
        labelsUse = labels0;
        return;
    end

    nTrial = size(Z0, 1);

    switch splitMode
        case 1
            idx = 1:nTrial;
        case 2
            if splitIdx == 1
                idx = 1:nTrial;
            else
                idx = idx_tone(sessionEntry, splitIdx - 1);
            end
        case 3
            if splitIdx == 1
                idx = 1:nTrial;
            else
                idx = idx_octave_from_tones(sessionEntry, splitIdx - 1);
            end
        otherwise
            idx = 1:nTrial;
    end

    if isempty(idx)
        Zuse = [];
        labelsUse = labels0;
        return;
    end

    Zuse = Z0(idx, :);
    labelsUse = subset_labels(labels0, idx, nTrial);
end

function idx = idx_tone(sessionEntry, toneK)
    idx = [];
    labelsIn = sessionEntry.labels;

    toneID = get_num_field(labelsIn, {'toneID', 'tone_id', 'ToneID', 'Tone'}, []);
    if ~isempty(toneID)
        idx = find(toneID == toneK);
        return;
    end

    if isfield(sessionEntry, 'Split') && ~isempty(sessionEntry.Split)
        idx = idx_from_split_struct(sessionEntry.Split, 2, toneK);
    end
end

function idx = idx_octave_from_tones(sessionEntry, octK)
    idx = [];
    labelsIn = sessionEntry.labels;

    toneID = get_num_field(labelsIn, {'toneID', 'tone_id', 'ToneID', 'Tone'}, []);
    if isempty(toneID)
        if isfield(sessionEntry, 'Split') && ~isempty(sessionEntry.Split)
            idx = idx_octave_from_splitTone(sessionEntry.Split, octK);
        end
        return;
    end

    switch octK
        case 1
            tones = [1 7];
        case 2
            tones = [2 6];
        case 3
            tones = [3 5];
        case 4
            tones = 4;
        otherwise
            tones = [];
    end

    if isempty(tones)
        return;
    end
    idx = find(ismember(toneID, tones));
end

function idx = idx_octave_from_splitTone(splitStruct, octK)
    idx = [];
    toneCells = try_get_cell_idx_all(splitStruct, {'Tone', 'tone', 'toneID', 'ToneID'});
    if isempty(toneCells) || numel(toneCells) < 7
        return;
    end

    switch octK
        case 1
            ks = [1 7];
        case 2
            ks = [2 6];
        case 3
            ks = [3 5];
        case 4
            ks = 4;
        otherwise
            ks = [];
    end

    if isempty(ks)
        return;
    end

    gathered = [];
    for ii = 1:numel(ks)
        kk = ks(ii);
        if kk <= numel(toneCells) && ~isempty(toneCells{kk})
            gathered = [gathered; toneCells{kk}(:)]; %#ok<AGROW>
        end
    end
    idx = unique(gathered);
end

function idx = idx_from_split_struct(splitStruct, splitMode, splitIdx)
    idx = [];
    try
        if splitMode == 2
            idx = try_get_cell_idx(splitStruct, {'Tone', 'tone', 'toneID', 'ToneID'}, splitIdx);
        elseif splitMode == 3
            idx = try_get_cell_idx(splitStruct, {'Octave', 'OctSym', 'octSym', 'octSymID', 'OctSymID'}, splitIdx);
        end
    catch
        idx = [];
    end
end

function idx = try_get_cell_idx(splitStruct, fieldCandidates, k)
    idx = [];
    for ii = 1:numel(fieldCandidates)
        fn = fieldCandidates{ii};
        if isfield(splitStruct, fn)
            value = splitStruct.(fn);
            if isstruct(value) && isfield(value, 'All') && iscell(value.All) && numel(value.All) >= k
                idx = value.All{k};
                return;
            end
            if iscell(value) && numel(value) >= k
                idx = value{k};
                return;
            end
        end
    end
end

function cells = try_get_cell_idx_all(splitStruct, fieldCandidates)
    cells = {};
    for ii = 1:numel(fieldCandidates)
        fn = fieldCandidates{ii};
        if isfield(splitStruct, fn)
            value = splitStruct.(fn);
            if isstruct(value) && isfield(value, 'All') && iscell(value.All)
                cells = value.All;
                return;
            end
            if iscell(value)
                cells = value;
                return;
            end
        end
    end
end

function values = get_num_field(labelsStruct, candidates, defaultVal)
    values = defaultVal;
    for ii = 1:numel(candidates)
        fn = candidates{ii};
        if isfield(labelsStruct, fn) && ~isempty(labelsStruct.(fn))
            values = double(labelsStruct.(fn)(:));
            return;
        end
    end
end

function labelsOut = subset_labels(labelsIn, mask, nTrial)
    labelsOut = labelsIn;
    fns = fieldnames(labelsIn);
    for ii = 1:numel(fns)
        fn = fns{ii};
        value = labelsIn.(fn);
        try
            if isvector(value) && numel(value) == nTrial
                labelsOut.(fn) = value(mask);
            elseif size(value, 1) == nTrial
                labelsOut.(fn) = value(mask, :);
            end
        catch
        end
    end
end

function labels = get_label_field(labelsStruct, fieldName, nTrial, defaultValue)
    if isfield(labelsStruct, fieldName) && ~isempty(labelsStruct.(fieldName))
        raw = labelsStruct.(fieldName);
        if iscell(raw)
            labels = raw(:);
        else
            labels = cellstr(string(raw(:)));
        end
        if numel(labels) ~= nTrial
            labels = repmat({defaultValue}, nTrial, 1);
        end
    else
        labels = repmat({defaultValue}, nTrial, 1);
    end
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

function add_sem_patch(ax, t, yMean, ySem, colorValue)
    if isempty(yMean) || isempty(ySem) || all(isnan(ySem))
        return;
    end

    upper = yMean + ySem;
    lower = yMean - ySem;
    patch(ax, [t fliplr(t)], [upper fliplr(lower)], colorValue, ...
        'FaceAlpha', 0.18, ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
end

function colorValue = get_base_color_from_key(keyStr)
    keyStr = canonical_group_key(keyStr);
    if isempty(keyStr)
        colorValue = [0.3 0.3 0.3];
    elseif strncmp(keyStr, 'WT_', 3)
        colorValue = [0.00 0.45 0.74];
    elseif strncmp(keyStr, 'FX_', 3)
        colorValue = [0.85 0.33 0.10];
    else
        colorValue = [0.3 0.3 0.3];
    end
end

function colorValue = get_alt_color_same_genotype(keyStr)
    keyStr = canonical_group_key(keyStr);
    if isempty(keyStr)
        colorValue = [0.55 0.55 0.55];
    elseif strncmp(keyStr, 'WT_', 3)
        colorValue = [0.30 0.75 0.93];
    elseif strncmp(keyStr, 'FX_', 3)
        colorValue = [0.93 0.69 0.13];
    else
        colorValue = [0.55 0.55 0.55];
    end
end

function tf = same_genotype_from_keys(key1, key2)
    key1 = canonical_group_key(key1);
    key2 = canonical_group_key(key2);
    if isempty(key1) || isempty(key2)
        tf = false;
        return;
    end
    tf = (strncmp(key1, 'WT_', 3) && strncmp(key2, 'WT_', 3)) || ...
         (strncmp(key1, 'FX_', 3) && strncmp(key2, 'FX_', 3));
end

function lighter = make_lighter(baseColor)
    lighter = 0.55 * [1 1 1] + 0.45 * baseColor;
end

function cmap = make_genotype_palette(baseColor, n)
    if n <= 1
        cmap = baseColor;
        return;
    end
    cmap = zeros(n, 3);
    for ii = 1:n
        alpha = (ii - 1) / max(1, n - 1);
        cmap(ii, :) = (1 - alpha) * [0.95 0.95 0.95] + alpha * baseColor;
    end
end

function cmapStruct = build_group_color_map(gNames)
    gNames = cellstr(gNames(:));
    wtIdx = [];
    fxIdx = [];
    unkIdx = [];

    for ii = 1:numel(gNames)
        key = canonical_group_key(gNames{ii});
        if strncmp(key, 'WT_', 3)
            wtIdx(end+1) = ii; %#ok<AGROW>
        elseif strncmp(key, 'FX_', 3)
            fxIdx(end+1) = ii; %#ok<AGROW>
        else
            unkIdx(end+1) = ii; %#ok<AGROW>
        end
    end

    cmapStruct = struct();

    if ~isempty(wtIdx)
        hues = linspace(0.55, 0.75, numel(wtIdx));
        sats = linspace(0.75, 0.95, numel(wtIdx));
        vals = linspace(0.85, 0.70, numel(wtIdx));
        for ii = 1:numel(wtIdx)
            key = canonical_group_key(gNames{wtIdx(ii)});
            cmapStruct.(matlab.lang.makeValidName(key)) = hsv2rgb([hues(ii), sats(ii), vals(ii)]);
        end
    end

    if ~isempty(fxIdx)
        hues = linspace(0.02, 0.12, numel(fxIdx));
        sats = linspace(0.80, 0.98, numel(fxIdx));
        vals = linspace(0.90, 0.75, numel(fxIdx));
        for ii = 1:numel(fxIdx)
            key = canonical_group_key(gNames{fxIdx(ii)});
            cmapStruct.(matlab.lang.makeValidName(key)) = hsv2rgb([hues(ii), sats(ii), vals(ii)]);
        end
    end

    if ~isempty(unkIdx)
        vals = linspace(0.35, 0.75, numel(unkIdx));
        for ii = 1:numel(unkIdx)
            key = canonical_group_key(gNames{unkIdx(ii)});
            cmapStruct.(matlab.lang.makeValidName(key)) = [1 1 1] * vals(ii);
        end
    end

    for ii = 1:numel(gNames)
        key = canonical_group_key(gNames{ii});
        f = matlab.lang.makeValidName(key);
        if ~isfield(cmapStruct, f)
            cmapStruct.(f) = [0.3 0.3 0.3];
        end
    end
end

function key = canonical_group_key(value)
    key = strtrim(char(string(value)));
end

function positions = compute_axes_positions(nAxes)
    nCols = ceil(sqrt(nAxes));
    nRows = ceil(nAxes / nCols);

    if nAxes == 7
        nCols = 3;
        nRows = 3;
    elseif nAxes == 4
        nCols = 2;
        nRows = 2;
    end

    left = 0.07;
    bottom = 0.08;
    width = 0.88;
    height = 0.80;
    gapX = 0.04;
    gapY = 0.09;

    if nAxes > 1
        bottom = 0.15;
        height = 0.69;
        gapY = 0.08;
    end

    cellW = (width - gapX * (nCols - 1)) / nCols;
    cellH = (height - gapY * (nRows - 1)) / nRows;

    positions = zeros(nAxes, 4);
    idx = 1;
    for row = 1:nRows
        for col = 1:nCols
            if idx > nAxes
                return;
            end
            x = left + (col - 1) * (cellW + gapX);
            y = bottom + (nRows - row) * (cellH + gapY);
            positions(idx, :) = [x y cellW cellH];
            idx = idx + 1;
        end
    end
end

function titleText = compose_plot_heading(modeTag, keyG1, keyG2, splitMode, tileSplit)
    splitName = split_mode_name(splitMode);
    if tileSplit
        splitPart = [splitName ' tiles'];
    else
        splitPart = splitName;
    end

    switch modeTag
        case 'single'
            titleText = sprintf('Single session: %s | %s', keyG1, splitPart);
        case 'groupmean'
            titleText = sprintf('Group mean: %s | %s', keyG1, splitPart);
        case 'group12'
            if isempty(keyG2)
                titleText = sprintf('%s vs <none> | %s', keyG1, splitPart);
            else
                titleText = sprintf('%s vs %s | %s', keyG1, keyG2, splitPart);
            end
        otherwise
            titleText = sprintf('%s | %s', keyG1, splitPart);
    end
end

function name = split_mode_name(splitMode)
    switch splitMode
        case 1
            name = 'All trials';
        case 2
            name = 'Tone';
        case 3
            name = 'Octave';
        otherwise
            name = 'Split';
    end
end

function win = parse_window(startCtrl, endCtrl, fallback)
    win = [str2double(get(startCtrl, 'String')), str2double(get(endCtrl, 'String'))];
    if any(isnan(win)) || win(1) >= win(2)
        win = fallback;
    end
end

function write_simple_csv(filePath, headers, rows)
    fid = fopen(filePath, 'w');
    if fid < 0
        error('fp_gui_population_viewer:ExportFailed', 'Unable to open %s for writing.', filePath);
    end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, '%s\n', csv_join(headers));
    for ii = 1:size(rows, 1)
        fprintf(fid, '%s\n', csv_join(rows(ii, :)));
    end
    clear cleaner;
end

function outLine = csv_join(values)
    escaped = cell(1, numel(values));
    for ii = 1:numel(values)
        value = values{ii};
        if isnumeric(value)
            if isscalar(value)
                if isnan(value)
                    token = '';
                else
                    token = num2str(value, '%.6g');
                end
            else
                token = '';
            end
        else
            token = char(string(value));
        end
        token = strrep(token, '"', '""');
        escaped{ii} = ['"' token '"'];
    end
    outLine = strjoin(escaped, ',');
end
