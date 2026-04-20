function test_fp_gui_population_viewer_smoke(rootDir)
% TEST_FP_GUI_POPULATION_VIEWER_SMOKE
% Regression smoke test for fp_gui_population_viewer, including
% tone/octave split modes and tiled split plotting.

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(fileparts(mfilename('fullpath')));
    end

    close all force;
    lastwarn('');

    cleanupObj = onCleanup(@close_all_figures);

    addpath(genpath(rootDir));
    fp_gui_population_viewer(rootDir);
    drawnow;

    fig = findall(0, 'Type', 'figure', 'Name', 'FP Population Viewer');
    assert(~isempty(fig), 'Viewer figure was not created.');
    fig = fig(1);

    btnPlot = findobj(fig, 'Tag', 'btnPlot');
    popupSplitMode = findobj(fig, 'Tag', 'popupSplitMode');
    popupSplitIdx = findobj(fig, 'Tag', 'popupSplitIdx');
    popupGroup2 = findobj(fig, 'Tag', 'popupGroup2');
    cbAll = findobj(fig, 'Tag', 'cbAll');
    cbHit = findobj(fig, 'Tag', 'cbHit');
    cbFA = findobj(fig, 'Tag', 'cbFA');
    cbTileSplit = findobj(fig, 'Tag', 'cbTileSplit');
    editReactStart = findobj(fig, 'Tag', 'editReactStart');
    editReactEnd = findobj(fig, 'Tag', 'editReactEnd');
    editRewardStart = findobj(fig, 'Tag', 'editRewardStart');
    editRewardEnd = findobj(fig, 'Tag', 'editRewardEnd');
    tableSummary = findobj(fig, 'Tag', 'tableSummary');
    btnExportSummary = findobj(fig, 'Tag', 'btnExportSummary');
    listSessions1 = findobj(fig, 'Tag', 'listSessions1');
    listAnimals1 = findobj(fig, 'Tag', 'listAnimals1');
    listAnimals2 = findobj(fig, 'Tag', 'listAnimals2');
    modeBG = findall(fig, 'Type', 'uibuttongroup', 'Title', 'Mode');

    assert(~isempty(btnPlot), 'Plot button not found.');
    assert(~isempty(popupSplitMode), 'Split mode popup not found.');
    assert(~isempty(popupSplitIdx), 'Split selection popup not found.');
    assert(~isempty(popupGroup2), 'Group 2 popup not found.');
    assert(~isempty(modeBG), 'Mode button group not found.');
    assert(~isempty(editReactStart) && ~isempty(editReactEnd), 'React AUC window controls not found.');
    assert(~isempty(editRewardStart) && ~isempty(editRewardEnd), 'Reward AUC window controls not found.');
    assert(~isempty(tableSummary), 'Summary table not found.');
    assert(~isempty(btnExportSummary), 'Export summary button not found.');

    set(cbAll, 'Value', 1);
    set(cbHit, 'Value', 1);
    set(cbFA, 'Value', 1);
    set(cbTileSplit, 'Value', 0);
    set(editReactStart, 'String', '0');
    set(editReactEnd, 'String', '1.5');
    set(editRewardStart, 'String', '2');
    set(editRewardEnd, 'String', '5');
    drawnow;

    assert(~isempty(get(listSessions1, 'String')), 'Session list is empty.');
    assert(~isempty(get(listAnimals1, 'Data')), 'Animal list for Group 1 is empty.');
    assert(~isempty(get(listAnimals2, 'Data')), 'Animal list for Group 2 is empty.');

    run_plot(btnPlot, modeBG, 'single');
    run_plot(btnPlot, modeBG, 'groupmean');

    if control_length(get(popupGroup2, 'String')) >= 2
        set(popupGroup2, 'Value', 2);
        fire_callback(popupGroup2);
        drawnow;
        run_plot(btnPlot, modeBG, 'group12');
    end

    splitModeItems = get_as_cellstr(get(popupSplitMode, 'String'));
    assert(any(strcmp(splitModeItems, 'Tone (1..7)')), 'Tone split mode was not populated.');
    assert(any(strcmp(splitModeItems, 'Symmetric Octave (4 bins)')), 'Octave split mode was not populated.');

    set(popupSplitMode, 'Value', find(strcmp(splitModeItems, 'Tone (1..7)'), 1, 'first'));
    fire_callback(popupSplitMode);
    drawnow;

    toneItems = get_as_cellstr(get(popupSplitIdx, 'String'));
    assert(control_length(toneItems) >= 8, 'Tone split index popup did not populate all tone bins.');
    set(popupSplitIdx, 'Value', 2);
    drawnow;
    run_plot(btnPlot, modeBG, 'single');

    aucSummary = get(tableSummary, 'Data');
    assert(~isempty(aucSummary), 'AUC summary table did not populate after plotting.');

    set(cbTileSplit, 'Value', 1);
    drawnow;
    run_plot(btnPlot, modeBG, 'groupmean');
    assert(count_plot_axes(fig) >= 7, 'Tone tiled mode did not render the expected number of plot axes.');

    set(popupSplitMode, 'Value', find(strcmp(splitModeItems, 'Symmetric Octave (4 bins)'), 1, 'first'));
    fire_callback(popupSplitMode);
    drawnow;
    octaveItems = get_as_cellstr(get(popupSplitIdx, 'String'));
    assert(control_length(octaveItems) >= 5, 'Octave split index popup did not populate all octave bins.');
    set(popupSplitIdx, 'Value', 2);
    set(cbTileSplit, 'Value', 1);
    drawnow;
    run_plot(btnPlot, modeBG, 'groupmean');
    assert(count_plot_axes(fig) >= 4, 'Octave tiled mode did not render the expected number of plot axes.');

    [warnMsg, warnId] = lastwarn;
    assert(isempty(warnMsg), 'Viewer emitted warning: %s (%s)', warnMsg, warnId);

    disp('fp_gui_population_viewer smoke test passed');

    clear cleanupObj;
end

function run_plot(btnPlot, modeBG, modeTag)
    target = findall(modeBG, 'Tag', modeTag);
    assert(~isempty(target), 'Mode button "%s" not found.', modeTag);
    modeBG.SelectedObject = target(1);
    drawnow;
    fire_callback(btnPlot);
    drawnow;
    ax = findall(0, 'Type', 'axes');
    assert(~isempty(ax), 'No axes found after plotting mode "%s".', modeTag);
end

function fire_callback(h)
    cb = get(h, 'Callback');
    if isa(cb, 'function_handle')
        cb(h, []);
    elseif iscell(cb)
        feval(cb{1}, h, [], cb{2:end});
    else
        error('Unsupported callback type for control with tag "%s".', get(h, 'Tag'));
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

function items = get_as_cellstr(rawItems)
    if iscell(rawItems)
        items = rawItems;
    elseif isstring(rawItems)
        items = cellstr(rawItems);
    elseif ischar(rawItems)
        items = cellstr(rawItems);
    else
        items = cellstr(string(rawItems));
    end
end

function n = count_plot_axes(fig)
    allAxes = findall(fig, 'Type', 'axes');
    n = 0;
    for ii = 1:numel(allAxes)
        tag = '';
        try
            tag = get(allAxes(ii), 'Tag');
        catch
        end
        if isempty(tag) || ~strcmpi(tag, 'legend')
            n = n + 1;
        end
    end
end

function close_all_figures()
    close all force;
end
