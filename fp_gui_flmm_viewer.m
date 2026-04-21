function fp_gui_flmm_viewer(rootDir)
% FP_GUI_FLMM_VIEWER
% Standalone GUI for pairwise FLMM comparisons driven by the exported
% FLMM-ready trial table and a generic R/fastFMM backend.

    clc;

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(mfilename('fullpath'));
    end

    tablePath = fullfile(rootDir, 'FLMM_Export_CSV', 'all_sessions_flmm_table.csv');
    timeAxisPath = fullfile(rootDir, 'FLMM_Export_CSV', 'time_axis.csv');
    backendPath = fullfile(rootDir, 'FLMM', 'FLMM_run_pairwise_generic.R');
    outputRootDir = fullfile(rootDir, 'FLMM_Results', 'GUI');
    rscriptPath = locate_rscript();

    if ~isfile(tablePath)
        error('fp_gui_flmm_viewer:MissingTable', ...
            'Could not find %s', tablePath);
    end
    if ~isfile(timeAxisPath)
        error('fp_gui_flmm_viewer:MissingTimeAxis', ...
            'Could not find %s', timeAxisPath);
    end
    if ~isfile(backendPath)
        error('fp_gui_flmm_viewer:MissingBackend', ...
            'Could not find %s', backendPath);
    end
    if isempty(rscriptPath)
        warning('fp_gui_flmm_viewer:MissingRscript', ...
            ['Could not find Rscript automatically. The Run button will fail until Rscript is ', ...
             'installed or the helper locate_rscript() is updated with the correct path.']);
    end

    meta = read_flmm_metadata(tablePath);
    if isempty(meta)
        error('fp_gui_flmm_viewer:NoMetadata', ...
            'FLMM metadata table is empty: %s', tablePath);
    end

    valueCatalog = struct();
    valueCatalog.region = unique_nonmissing(meta.region);
    valueCatalog.genotype = unique_nonmissing(meta.genotype_label);
    valueCatalog.condition = unique_nonmissing(meta.condition);
    valueCatalog.outcome = unique_nonmissing(meta.outcome);

    compareVars = {'genotype', 'outcome', 'condition', 'region'};
    compareVarLabels = {'Genotype', 'Outcome', 'Condition', 'Region'};

    defaultXLim = [-2 10];
    defaultYLim = [-1.5 1.5];
    defaultDs = 100;

    state = struct();
    state.lastRunName = '';
    state.lastRunDir = outputRootDir;
    state.lastPreview = cell(0, 3);
    state.currentCfg = struct();
    state.currentCoefTbl = table();

    fig = figure('Name', 'FP FLMM Viewer', ...
        'NumberTitle', 'off', ...
        'Tag', 'figFlmmViewer', ...
        'Color', 'w', ...
        'Units', 'normalized', ...
        'Position', [0.03 0.06 0.94 0.86]);

    controlPanel = uipanel(fig, ...
        'Units', 'normalized', ...
        'Position', [0.01 0.04 0.27 0.92], ...
        'BackgroundColor', 'w', ...
        'Title', 'FLMM Controls');

    plotPanel = uipanel(fig, ...
        'Units', 'normalized', ...
        'Position', [0.30 0.31 0.69 0.65], ...
        'BackgroundColor', 'w', ...
        'Title', 'FLMM Coefficients');

    infoPanel = uipanel(fig, ...
        'Units', 'normalized', ...
        'Position', [0.30 0.04 0.69 0.23], ...
        'BackgroundColor', 'w', ...
        'Title', 'Run Summary');

    axIntercept = axes('Parent', plotPanel, ...
        'Units', 'normalized', ...
        'Position', [0.06 0.14 0.40 0.74], ...
        'Tag', 'axIntercept', ...
        'Box', 'off');
    axEffect = axes('Parent', plotPanel, ...
        'Units', 'normalized', ...
        'Position', [0.54 0.14 0.40 0.74], ...
        'Tag', 'axEffect', ...
        'Box', 'off');

    title(axIntercept, 'Intercept');
    title(axEffect, 'Effect');
    xlabel(axIntercept, 'Time from cue onset (s)');
    xlabel(axEffect, 'Time from cue onset (s)');
    ylabel(axIntercept, 'Estimate');
    ylabel(axEffect, 'Estimate');

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.94 0.40 0.04], ...
        'String', 'Compare variable', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupCompareVar = uicontrol(controlPanel, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.945 0.47 0.045], ...
        'String', compareVarLabels, ...
        'Tag', 'popupCompareVar', ...
        'BackgroundColor', 'w', ...
        'Callback', @onConfigChanged);

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.89 0.40 0.04], ...
        'String', 'Reference level', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupReference = uicontrol(controlPanel, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.895 0.47 0.045], ...
        'String', {'-'}, ...
        'Tag', 'popupReference', ...
        'BackgroundColor', 'w', ...
        'Callback', @onConfigChanged);

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.84 0.40 0.04], ...
        'String', 'Contrast level', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    popupContrast = uicontrol(controlPanel, 'Style', 'popupmenu', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.845 0.47 0.045], ...
        'String', {'-'}, ...
        'Tag', 'popupContrast', ...
        'BackgroundColor', 'w', ...
        'Callback', @onConfigChanged);

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.78 0.90 0.04], ...
        'String', 'Fixed filters (<all> keeps every level)', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    filterChoices = struct();
    filterChoices.region = [{'<all>'}; cellstr(valueCatalog.region)];
    filterChoices.genotype = [{'<all>'}; cellstr(valueCatalog.genotype)];
    filterChoices.condition = [{'<all>'}; cellstr(valueCatalog.condition)];
    filterChoices.outcome = [{'<all>'}; cellstr(valueCatalog.outcome)];

    [popupRegion, popupGenotype, popupCondition, popupOutcome] = deal([]);

    popupRegion = add_filter_popup(controlPanel, 0.73, 'Region', filterChoices.region);
    set(popupRegion, 'Tag', 'popupRegion');
    popupGenotype = add_filter_popup(controlPanel, 0.68, 'Genotype', filterChoices.genotype);
    set(popupGenotype, 'Tag', 'popupGenotype');
    popupCondition = add_filter_popup(controlPanel, 0.63, 'Condition', filterChoices.condition);
    set(popupCondition, 'Tag', 'popupCondition');
    popupOutcome = add_filter_popup(controlPanel, 0.58, 'Outcome', filterChoices.outcome);
    set(popupOutcome, 'Tag', 'popupOutcome');

    filterPopups = struct();
    filterPopups.region = popupRegion;
    filterPopups.genotype = popupGenotype;
    filterPopups.condition = popupCondition;
    filterPopups.outcome = popupOutcome;

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.52 0.40 0.04], ...
        'String', 'Downsample by', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editDs = uicontrol(controlPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.48 0.525 0.20 0.045], ...
        'String', num2str(defaultDs), ...
        'Tag', 'editDs', ...
        'BackgroundColor', 'w');

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.46 0.90 0.04], ...
        'String', 'Axes [Xmin Xmax ; Ymin Ymax]', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.42 0.08 0.04], ...
        'String', 'X', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editXmin = uicontrol(controlPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.16 0.425 0.22 0.045], ...
        'String', num2str(defaultXLim(1)), ...
        'Tag', 'editXmin', ...
        'BackgroundColor', 'w');

    editXmax = uicontrol(controlPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.42 0.425 0.22 0.045], ...
        'String', num2str(defaultXLim(2)), ...
        'Tag', 'editXmax', ...
        'BackgroundColor', 'w');

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.37 0.08 0.04], ...
        'String', 'Y', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    editYmin = uicontrol(controlPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.16 0.375 0.22 0.045], ...
        'String', num2str(defaultYLim(1)), ...
        'Tag', 'editYmin', ...
        'BackgroundColor', 'w');

    editYmax = uicontrol(controlPanel, 'Style', 'edit', ...
        'Units', 'normalized', ...
        'Position', [0.42 0.375 0.22 0.045], ...
        'String', num2str(defaultYLim(2)), ...
        'Tag', 'editYmax', ...
        'BackgroundColor', 'w');

    btnApplyAxes = uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.69 0.375 0.26 0.045], ...
        'String', 'Apply Axes', ...
        'Tag', 'btnApplyAxes', ...
        'Callback', @onApplyAxes);

    btnRun = uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.69 0.425 0.26 0.125], ...
        'String', 'Run FLMM', ...
        'Tag', 'btnRunFlmm', ...
        'FontWeight', 'bold', ...
        'Callback', @onRunFLMM);

    uicontrol(controlPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.30 0.90 0.04], ...
        'String', 'Preview counts (before running)', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    tablePreview = uitable(controlPanel, ...
        'Units', 'normalized', ...
        'Position', [0.05 0.16 0.90 0.15], ...
        'Tag', 'tablePreview', ...
        'Data', cell(0, 3), ...
        'ColumnName', {'Level', 'NTrial', 'NAnimal'}, ...
        'RowName', []);

    btnSaveFigures = uicontrol(controlPanel, 'Style', 'pushbutton', ...
        'Units', 'normalized', ...
        'Position', [0.05 0.09 0.90 0.05], ...
        'String', 'Save Figures...', ...
        'Tag', 'btnSaveFigures', ...
        'Callback', @onSaveFigures);

    uicontrol(infoPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.02 0.83 0.20 0.10], ...
        'String', 'Counts used in model', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    tableCounts = uitable(infoPanel, ...
        'Units', 'normalized', ...
        'Position', [0.02 0.40 0.22 0.40], ...
        'Tag', 'tableCounts', ...
        'Data', cell(0, 3), ...
        'ColumnName', {'Level', 'NTrial', 'NAnimal'}, ...
        'RowName', []);

    uicontrol(infoPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.27 0.83 0.30 0.10], ...
        'String', 'Significant windows', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    tableWindows = uitable(infoPanel, ...
        'Units', 'normalized', ...
        'Position', [0.27 0.14 0.35 0.66], ...
        'Tag', 'tableWindows', ...
        'Data', cell(0, 5), ...
        'ColumnName', {'Coef', 'Start', 'End', 'N', 'Dir'}, ...
        'RowName', []);

    uicontrol(infoPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.65 0.83 0.30 0.10], ...
        'String', 'Progress', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    progressAxes = axes('Parent', infoPanel, ...
        'Units', 'normalized', ...
        'Position', [0.65 0.68 0.30 0.10], ...
        'Tag', 'axesProgress', ...
        'Box', 'on', ...
        'XLim', [0 1], ...
        'YLim', [0 1], ...
        'XTick', [], ...
        'YTick', [], ...
        'Color', [0.96 0.96 0.96]);
    progressPatch = patch(progressAxes, ...
        'XData', [0 0 0 0], ...
        'YData', [0 0 1 1], ...
        'FaceColor', [0.18 0.52 0.86], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.95);

    progressText = uicontrol(infoPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.65 0.58 0.30 0.08], ...
        'String', 'Idle', ...
        'Tag', 'textProgress', ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');

    uicontrol(infoPanel, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.65 0.46 0.30 0.08], ...
        'String', 'Status', ...
        'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', 'w');

    statusBox = uicontrol(infoPanel, 'Style', 'listbox', ...
        'Units', 'normalized', ...
        'Position', [0.65 0.06 0.30 0.38], ...
        'String', {'Ready.'}, ...
        'Tag', 'statusBox', ...
        'BackgroundColor', 'w', ...
        'Max', 2, ...
        'Min', 0);

    refresh_compare_controls();
    refresh_preview_table();

    function popup = add_filter_popup(parent, y, labelText, items)
        uicontrol(parent, 'Style', 'text', ...
            'Units', 'normalized', ...
            'Position', [0.05 y 0.40 0.04], ...
            'String', labelText, ...
            'HorizontalAlignment', 'left', ...
            'BackgroundColor', 'w');

        popup = uicontrol(parent, 'Style', 'popupmenu', ...
            'Units', 'normalized', ...
            'Position', [0.48 y + 0.005 0.47 0.045], ...
            'String', items, ...
            'BackgroundColor', 'w', ...
            'Callback', @onConfigChanged);
    end

    function onConfigChanged(~, ~)
        refresh_compare_controls();
        refresh_preview_table();
    end

    function refresh_compare_controls()
        compareVar = current_compare_var();
        levels = cellstr(valueCatalog.(compareVar));

        if isempty(levels)
            levels = {'<none>'};
        end

        set(popupReference, 'String', levels);
        set(popupContrast, 'String', levels);

        if numel(levels) >= 1
            set(popupReference, 'Value', min(get(popupReference, 'Value'), numel(levels)));
            set(popupContrast, 'Value', min(max(2, get(popupContrast, 'Value')), numel(levels)));
        end

        if numel(levels) >= 2 && get(popupReference, 'Value') == get(popupContrast, 'Value')
            if get(popupReference, 'Value') == 1
                set(popupContrast, 'Value', 2);
            else
                set(popupContrast, 'Value', 1);
            end
        end

        allFilterNames = fieldnames(filterPopups);
        for i = 1:numel(allFilterNames)
            fName = allFilterNames{i};
            set(filterPopups.(fName), 'Enable', 'on');
        end

        set(filterPopups.(compareVar), 'Value', 1, 'Enable', 'off');
    end

    function refresh_preview_table()
        cfg = collect_config(false);
        previewRows = build_preview_rows(cfg);
        state.lastPreview = previewRows;
        set(tablePreview, 'Data', previewRows);
    end

    function previewRows = build_preview_rows(cfg)
        compField = compare_source_field(cfg.compareVar);
        levelA = cfg.referenceLevel;
        levelB = cfg.contrastLevel;

        T = meta;
        filterNames = fieldnames(cfg.filters);
        for i = 1:numel(filterNames)
            fName = filterNames{i};
            fVal = cfg.filters.(fName);
            if isempty(fVal)
                continue;
            end

            srcField = compare_source_field(fName);
            T = T(T.(srcField) == string(fVal), :);
        end

        T = T(ismember(T.(compField), string({levelA, levelB})), :);

        previewRows = cell(2, 3);
        previewLevels = {levelA, levelB};
        for i = 1:2
            mask = T.(compField) == string(previewLevels{i});
            previewRows{i, 1} = previewLevels{i};
            previewRows{i, 2} = sum(mask);
            previewRows{i, 3} = numel(unique(T.id(mask), 'stable'));
        end
    end

    function onRunFLMM(~, ~)
        try
            cfg = collect_config(true);
        catch ME
            append_status(ME.message);
            errordlg(ME.message, 'Invalid FLMM settings');
            return;
        end

        if isempty(cfg.referenceLevel) || isempty(cfg.contrastLevel)
            append_status('Select two levels before running.');
            return;
        end
        if strcmp(cfg.referenceLevel, cfg.contrastLevel)
            append_status('Reference and contrast levels must be different.');
            return;
        end
        if isempty(state.lastPreview)
            append_status('Preview table is empty. Adjust the settings and try again.');
            return;
        end
        if any(cell2mat(state.lastPreview(:, 2)) == 0)
            append_status('One selected level has zero trials after filtering. Adjust the filters or comparison.');
            return;
        end

        cfg.runName = build_run_folder_name(cfg);
        cfg.runDir = fullfile(outputRootDir, cfg.runName);
        state.lastRunName = cfg.runName;
        state.lastRunDir = cfg.runDir;

        args = {
            ['--table_path=' shell_quote(tablePath)]
            ['--time_axis_path=' shell_quote(timeAxisPath)]
            ['--output_dir=' shell_quote(cfg.runDir)]
            ['--compare_var=' shell_quote(cfg.compareVar)]
            ['--reference_level=' shell_quote(cfg.referenceLevel)]
            ['--contrast_level=' shell_quote(cfg.contrastLevel)]
            ['--filter_region=' shell_quote(normalize_filter_arg(cfg.filters.region))]
            ['--filter_genotype=' shell_quote(normalize_filter_arg(cfg.filters.genotype))]
            ['--filter_condition=' shell_quote(normalize_filter_arg(cfg.filters.condition))]
            ['--filter_outcome=' shell_quote(normalize_filter_arg(cfg.filters.outcome))]
            ['--ds_by=' shell_quote(num2str(cfg.dsBy))]
            ['--plot_xmin=' shell_quote(num2str(cfg.xLim(1)))]
            ['--plot_xmax=' shell_quote(num2str(cfg.xLim(2)))]
            ['--plot_ymin=' shell_quote(num2str(cfg.yLim(1)))]
            ['--plot_ymax=' shell_quote(num2str(cfg.yLim(2)))]
        };

        if isempty(rscriptPath)
            append_status('Rscript was not found. Update locate_rscript() with your local R path.');
            errordlg('Rscript was not found. Please install R or update locate_rscript().', ...
                'Rscript not found');
            return;
        end

        cmd = strjoin([{[shell_quote(rscriptPath) ' ' shell_quote(backendPath)]}; args], ' ');

        set(btnRun, 'Enable', 'off');
        set(fig, 'Pointer', 'watch');
        start_progress_indicator(progressAxes, progressPatch, progressText, ...
            ['Running ' cfg.runName]);
        append_status(['Running FLMM: ' cfg.runName]);
        drawnow;

        try
            [statusCode, cmdout] = run_shell_command_with_progress( ...
                cmd, progressAxes, progressPatch, progressText);
        catch ME
            stop_progress_indicator(progressAxes, progressPatch, progressText, 'Run failed');
            set(fig, 'Pointer', 'arrow');
            set(btnRun, 'Enable', 'on');
            append_status(['FLMM launch failed: ' ME.message]);
            rethrow(ME);
        end

        set(fig, 'Pointer', 'arrow');
        set(btnRun, 'Enable', 'on');

        if ~isempty(strtrim(cmdout))
            append_status(cmdout);
        end

        if statusCode ~= 0
            stop_progress_indicator(progressAxes, progressPatch, progressText, ...
                sprintf('Failed (exit %d)', statusCode));
            append_status('FLMM run failed.');
            errordlg(cmdout, 'FLMM run failed');
            return;
        end

        try
            render_run_outputs(cfg);
            stop_progress_indicator(progressAxes, progressPatch, progressText, 'Completed');
            append_status(['Finished: ' cfg.runName]);
        catch ME
            stop_progress_indicator(progressAxes, progressPatch, progressText, ...
                'Completed with GUI load error');
            append_status(['Run completed but GUI could not load outputs: ' ME.message]);
            rethrow(ME);
        end
    end

    function render_run_outputs(cfg)
        tablesDir = fullfile(cfg.runDir, 'Tables');
        coefPath = fullfile(tablesDir, 'coefficients_long.csv');
        countsPath = fullfile(tablesDir, 'summary_counts.csv');
        windowsPath = fullfile(tablesDir, 'significance_windows.csv');

        coefTbl = readtable(coefPath, 'TextType', 'string');
        countsTbl = readtable(countsPath, 'TextType', 'string');

        if isfile(windowsPath)
            windowsTbl = readtable(windowsPath, 'TextType', 'string');
        else
            windowsTbl = table();
        end

        state.currentCfg = cfg;
        state.currentCoefTbl = coefTbl;

        set(tableCounts, 'Data', table_to_cell(countsTbl(:, {'level', 'n_trials', 'n_animals'})));
        set(tableWindows, 'Data', windows_table_cells(windowsTbl));

        plot_coefficient(axIntercept, coefTbl(coefTbl.coefficient_index == 1, :), cfg);
        plot_coefficient(axEffect, coefTbl(coefTbl.coefficient_index == 2, :), cfg);

        append_status(['Outputs written to ' cfg.runDir]);
    end

    function onApplyAxes(~, ~)
        try
            cfg = collect_config(true);
        catch ME
            append_status(ME.message);
            errordlg(ME.message, 'Invalid axes settings');
            return;
        end

        if ~isempty(state.currentCfg)
            cfg.compareVar = state.currentCfg.compareVar;
            cfg.referenceLevel = state.currentCfg.referenceLevel;
            cfg.contrastLevel = state.currentCfg.contrastLevel;
            cfg.filters = state.currentCfg.filters;
            if isfield(state.currentCfg, 'runName')
                cfg.runName = state.currentCfg.runName;
            end
            if isfield(state.currentCfg, 'runDir')
                cfg.runDir = state.currentCfg.runDir;
            end
        end

        if ~isempty(state.currentCoefTbl) && height(state.currentCoefTbl) > 0
            plot_coefficient(axIntercept, state.currentCoefTbl(state.currentCoefTbl.coefficient_index == 1, :), cfg);
            plot_coefficient(axEffect, state.currentCoefTbl(state.currentCoefTbl.coefficient_index == 2, :), cfg);
            state.currentCfg = cfg;
            append_status(sprintf('Applied axes: X=[%g, %g], Y=[%g, %g]', ...
                cfg.xLim(1), cfg.xLim(2), cfg.yLim(1), cfg.yLim(2)));
        else
            xlim(axIntercept, cfg.xLim);
            ylim(axIntercept, cfg.yLim);
            xlim(axEffect, cfg.xLim);
            ylim(axEffect, cfg.yLim);
            append_status('Applied axes to empty plot panels. Run FLMM to draw data.');
        end
    end

    function plot_coefficient(ax, coefTbl, cfg)
        cla(ax);
        hold(ax, 'on');
        ax.Layer = 'top';
        ax.Clipping = 'on';

        x = coefTbl.time;
        beta = coefTbl.beta;

        if all(ismember(["lower_joint", "upper_joint", "lower", "upper"], coefTbl.Properties.VariableNames))
            patch(ax, ...
                [x; flipud(x)], ...
                [coefTbl.lower_joint; flipud(coefTbl.upper_joint)], ...
                [0.85 0.85 0.85], ...
                'EdgeColor', 'none', ...
                'FaceAlpha', 1.0, ...
                'Clipping', 'on');

            patch(ax, ...
                [x; flipud(x)], ...
                [coefTbl.lower; flipud(coefTbl.upper)], ...
                [0.55 0.55 0.55], ...
                'EdgeColor', 'none', ...
                'FaceAlpha', 0.95, ...
                'Clipping', 'on');
        end

        plot(ax, x, zeros(size(x)), '--', 'Color', [0.75 0.1 0.1], 'LineWidth', 1.0);
        plot(ax, x, beta, 'k-', 'LineWidth', 2.0);

        xlim(ax, cfg.xLim);
        ylim(ax, cfg.yLim);

        if ismember('sig_joint', coefTbl.Properties.VariableNames)
            sigMask = parse_logical_like(coefTbl.sig_joint);
            if any(sigMask)
                yBottom = cfg.yLim(1);
                ySpan = cfg.yLim(2) - cfg.yLim(1);
                ySig = yBottom + 0.06 * ySpan;
                plot(ax, x(sigMask), repmat(ySig, sum(sigMask), 1), ...
                    'ks', 'MarkerFaceColor', 'k', 'MarkerSize', 4);
            end
        end

        title(ax, char(coefTbl.coefficient_title(1)), 'Interpreter', 'none');
        xlabel(ax, 'Time from cue onset (s)');
        ylabel(ax, 'Estimate');
        box(ax, 'off');
    end

    function onSaveFigures(~, ~)
        if isempty(state.currentCoefTbl) || height(state.currentCoefTbl) == 0
            append_status('No plotted FLMM result is loaded yet.');
            errordlg('No plotted FLMM result is loaded yet.', 'Save Figures');
            return;
        end

        defaultBase = 'flmm_coefficients';
        if isfield(state.currentCfg, 'runName') && ~isempty(state.currentCfg.runName)
            defaultBase = [state.currentCfg.runName '_coefficients'];
        end

        [fileName, filePath] = uiputfile( ...
            {'*.png'; '*.pdf'; '*.jpg'; '*.tif'}, ...
            'Save FLMM figure as', ...
            defaultBase);

        if isequal(fileName, 0) || isequal(filePath, 0)
            return;
        end

        outFile = fullfile(filePath, fileName);
        [~, ~, ext] = fileparts(outFile);
        if isempty(ext)
            outFile = [outFile '.png'];
        end

        exportFig = figure( ...
            'Visible', 'off', ...
            'Color', 'w', ...
            'Units', 'pixels', ...
            'Position', [100 100 1600 650]);

        cleanupFig = onCleanup(@() delete_valid_figure(exportFig));

        ax1 = copyobj(axIntercept, exportFig);
        ax2 = copyobj(axEffect, exportFig);
        set(ax1, 'Units', 'normalized', 'Position', [0.08 0.16 0.38 0.74]);
        set(ax2, 'Units', 'normalized', 'Position', [0.56 0.16 0.38 0.74]);

        exportgraphics(exportFig, outFile, 'Resolution', 300);
        append_status(['Saved figure to ' outFile]);
        clear cleanupFig;
    end

    function cfg = collect_config(validateNumbers)
        if nargin < 1
            validateNumbers = true;
        end

        cfg = struct();
        cfg.compareVar = current_compare_var();
        cfg.referenceLevel = get_popup_string(popupReference);
        cfg.contrastLevel = get_popup_string(popupContrast);
        cfg.filters = struct();
        cfg.filters.region = popup_value_or_empty(popupRegion);
        cfg.filters.genotype = popup_value_or_empty(popupGenotype);
        cfg.filters.condition = popup_value_or_empty(popupCondition);
        cfg.filters.outcome = popup_value_or_empty(popupOutcome);

        cfg.dsBy = str2double(get(editDs, 'String'));
        cfg.xLim = [str2double(get(editXmin, 'String')), str2double(get(editXmax, 'String'))];
        cfg.yLim = [str2double(get(editYmin, 'String')), str2double(get(editYmax, 'String'))];

        if validateNumbers
            if isnan(cfg.dsBy) || cfg.dsBy < 1
                error('Downsampling must be a positive number.');
            end
            if any(isnan(cfg.xLim)) || cfg.xLim(1) >= cfg.xLim(2)
                error('X limits are invalid.');
            end
            if any(isnan(cfg.yLim)) || cfg.yLim(1) >= cfg.yLim(2)
                error('Y limits are invalid.');
            end
        end

        cfg.dsBy = max(1, round(cfg.dsBy));
    end

    function out = current_compare_var()
        out = compareVars{get(popupCompareVar, 'Value')};
    end

    function val = popup_value_or_empty(h)
        val = get_popup_string(h);
        if strcmp(val, '<all>')
            val = '';
        end
    end

    function str = get_popup_string(h)
        items = get(h, 'String');
        idx = get(h, 'Value');
        if ischar(items)
            items = cellstr(items);
        end
        if isempty(items)
            str = '';
            return;
        end
        idx = min(max(1, idx), numel(items));
        str = items{idx};
    end

    function srcField = compare_source_field(name)
        switch lower(name)
            case 'genotype'
                srcField = 'genotype_label';
            otherwise
                srcField = lower(name);
        end
    end

    function out = normalize_filter_arg(val)
        if isempty(val)
            out = 'ALL';
        else
            out = val;
        end
    end

    function out = build_run_folder_name(cfg)
        parts = {'FLMM_GUI'};

        filterNames = {'region', 'genotype', 'condition', 'outcome'};
        for i = 1:numel(filterNames)
            fName = filterNames{i};
            fVal = cfg.filters.(fName);
            if ~isempty(fVal)
                parts{end+1} = sprintf('%s_%s', fName, fVal); %#ok<AGROW>
            end
        end

        parts{end+1} = sprintf('compare_%s', cfg.compareVar);
        parts{end+1} = sprintf('%s_vs_%s', cfg.referenceLevel, cfg.contrastLevel);

        out = sanitize_name(strjoin(parts, '_'));
    end

    function out = sanitize_name(in)
        out = regexprep(in, '[^A-Za-z0-9]+', '_');
        out = regexprep(out, '_+', '_');
        out = regexprep(out, '^_|_$', '');
    end

    function append_status(msg)
        if isempty(msg)
            return;
        end

        oldLines = get(statusBox, 'String');
        if ischar(oldLines)
            oldLines = cellstr(oldLines);
        end
        if isempty(oldLines)
            oldLines = {};
        end

        newLines = splitlines(string(msg));
        newLines = newLines(strlength(strtrim(newLines)) > 0);
        oldLines = [oldLines; cellstr(newLines)]; %#ok<AGROW>

        if numel(oldLines) > 200
            oldLines = oldLines(end-199:end);
        end

        set(statusBox, 'String', oldLines, 'Value', numel(oldLines));
        drawnow;
    end

    function out = shell_quote(in)
        in = char(string(in));
        out = ['''' strrep(in, '''', '''"''"''') ''''];
    end

    function cells = windows_table_cells(T)
        if isempty(T) || height(T) == 0
            cells = {'Effect', 'n.s.', '', '', ''};
            return;
        end

        keepVars = {'coefficient_title', 'window_start', 'window_end', 'n_timepoints', 'direction'};
        keepVars = keepVars(ismember(keepVars, T.Properties.VariableNames));
        T = T(:, keepVars);

        if ismember('coefficient_title', T.Properties.VariableNames)
            T.Properties.VariableNames{'coefficient_title'} = 'Coef';
        end
        if ismember('window_start', T.Properties.VariableNames)
            T.Properties.VariableNames{'window_start'} = 'Start';
        end
        if ismember('window_end', T.Properties.VariableNames)
            T.Properties.VariableNames{'window_end'} = 'End';
        end
        if ismember('n_timepoints', T.Properties.VariableNames)
            T.Properties.VariableNames{'n_timepoints'} = 'N';
        end
        if ismember('direction', T.Properties.VariableNames)
            T.Properties.VariableNames{'direction'} = 'Dir';
        end

        cells = table_to_cell(T);
    end
end

function T = read_flmm_metadata(tablePath)
    opts = detectImportOptions(tablePath);
    wanted = {'id', 'genotype_label', 'region', 'condition', 'outcome'};
    opts.SelectedVariableNames = wanted(ismember(wanted, opts.VariableNames));
    opts = setvartype(opts, opts.SelectedVariableNames, 'string');
    T = readtable(tablePath, opts);
end

function vals = unique_nonmissing(x)
    x = string(x);
    x = strtrim(x);
    x = x(strlength(x) > 0 & ~ismissing(x));
    vals = unique(x, 'stable');
end

function cells = table_to_cell(T)
    if isempty(T) || height(T) == 0
        cells = cell(0, width(T));
        return;
    end

    cells = table2cell(T);
    for i = 1:numel(cells)
        if isstring(cells{i}) && isscalar(cells{i})
            cells{i} = char(cells{i});
        end
    end
end

function delete_valid_figure(figHandle)
    if ~isempty(figHandle) && ishghandle(figHandle)
        delete(figHandle);
    end
end

function mask = parse_logical_like(values)
    if islogical(values)
        mask = values;
        return;
    end

    if isnumeric(values)
        mask = values ~= 0;
        return;
    end

    values = string(values);
    values = lower(strtrim(values));
    mask = values == "true" | values == "1" | values == "yes";
end

function start_progress_indicator(ax, patchHandle, textHandle, label)
    if nargin < 4 || isempty(label)
        label = 'Running...';
    end

    set(ax, 'Visible', 'on');
    set(patchHandle, 'XData', [0 0 0 0], 'Visible', 'on');
    set(textHandle, 'String', label);
    drawnow;
end

function update_progress_indicator(ax, patchHandle, textHandle, fraction, label)
    fraction = max(0, min(1, fraction));
    set(ax, 'Visible', 'on');
    set(patchHandle, 'XData', [0 fraction fraction 0], 'Visible', 'on');
    if nargin >= 5 && ~isempty(label)
        set(textHandle, 'String', label);
    end
    drawnow limitrate;
end

function stop_progress_indicator(ax, patchHandle, textHandle, label)
    if nargin < 4 || isempty(label)
        label = 'Idle';
    end

    set(ax, 'Visible', 'on');
    set(patchHandle, 'XData', [0 0 0 0], 'Visible', 'on');
    set(textHandle, 'String', label);
    drawnow;
end

function [statusCode, cmdout] = run_shell_command_with_progress(cmd, ax, patchHandle, textHandle)
    logPath = [tempname '.log'];
    quotedLogPath = shell_single_quote(logPath);
    wrappedCmd = sprintf('%s > %s 2>&1', cmd, quotedLogPath);

    if usejava('jvm')
        pb = java.lang.ProcessBuilder({'/bin/zsh', '-lc', wrappedCmd});
        pb.redirectErrorStream(true);
        proc = pb.start();

        tStart = tic;
        pulseWidth = 0.22;

        while proc.isAlive()
            elapsed = toc(tStart);
            anchor = mod(elapsed * 0.42, 1 + pulseWidth) - pulseWidth;
            left = max(0, anchor);
            right = min(1, anchor + pulseWidth);

            if right <= left
                frac = 0.05;
            else
                frac = right;
            end

            update_progress_indicator( ...
                ax, patchHandle, textHandle, frac, ...
                sprintf('Running... %0.0f s', elapsed));
            pause(0.10);
        end

        statusCode = proc.waitFor();
    else
        tStart = tic;
        update_progress_indicator(ax, patchHandle, textHandle, 0.35, 'Running...');
        [statusCode, ~] = system(wrappedCmd);
        update_progress_indicator( ...
            ax, patchHandle, textHandle, 0.95, ...
            sprintf('Finishing... %0.0f s', toc(tStart)));
    end

    if isfile(logPath)
        cmdout = fileread(logPath);
        delete(logPath);
    else
        cmdout = '';
    end
end

function out = shell_single_quote(in)
    in = char(string(in));
    out = ['''' strrep(in, '''', '''"''"''') ''''];
end

function rscriptPath = locate_rscript()
    rscriptPath = '';

    [status, cmdout] = system('command -v Rscript');
    if status == 0
        candidate = strtrim(cmdout);
        if ~isempty(candidate) && isfile(candidate)
            rscriptPath = candidate;
            return;
        end
    end

    candidates = {
        '/usr/local/bin/Rscript'
        '/opt/homebrew/bin/Rscript'
        '/Library/Frameworks/R.framework/Resources/bin/Rscript'
    };

    for i = 1:numel(candidates)
        if isfile(candidates{i})
            rscriptPath = candidates{i};
            return;
        end
    end
end
