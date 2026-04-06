function test_fp_gui_population_viewer_smoke(rootDir)
% TEST_FP_GUI_POPULATION_VIEWER_SMOKE
% Basic regression smoke test for fp_gui_population_viewer.

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
    listSessions1 = findobj(fig, 'Tag', 'listSessions1');
    listAnimals1 = findobj(fig, 'Tag', 'listAnimals1');
    listAnimals2 = findobj(fig, 'Tag', 'listAnimals2');
    modeBG = findall(fig, 'Type', 'uibuttongroup', 'Title', 'Mode');

    assert(~isempty(btnPlot), 'Plot button not found.');
    assert(~isempty(popupSplitMode), 'Split mode popup not found.');
    assert(~isempty(popupSplitIdx), 'Split selection popup not found.');
    assert(~isempty(popupGroup2), 'Group 2 popup not found.');
    assert(~isempty(modeBG), 'Mode button group not found.');

    set(cbAll, 'Value', 1);
    set(cbHit, 'Value', 1);
    set(cbFA, 'Value', 1);
    set(cbTileSplit, 'Value', 0);
    drawnow;

    assert(~isempty(get(listSessions1, 'String')), 'Session list is empty.');
    assert(~isempty(get(listAnimals1, 'String')), 'Animal list for Group 1 is empty.');
    assert(~isempty(get(listAnimals2, 'String')), 'Animal list for Group 2 is empty.');

    run_plot(btnPlot, modeBG, 'single');
    run_plot(btnPlot, modeBG, 'groupmean');

    if control_length(get(popupGroup2, 'String')) >= 2
        set(popupGroup2, 'Value', 2);
        fire_callback(popupGroup2);
        drawnow;
        run_plot(btnPlot, modeBG, 'group12');
    end

    set(popupSplitMode, 'Value', min(2, control_length(get(popupSplitMode, 'String'))));
    fire_callback(popupSplitMode);
    drawnow;
    set(popupSplitIdx, 'Value', min(2, control_length(get(popupSplitIdx, 'String'))));
    drawnow;
    run_plot(btnPlot, modeBG, 'single');

    set(cbTileSplit, 'Value', 1);
    drawnow;
    run_plot(btnPlot, modeBG, 'groupmean');

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

function close_all_figures()
    close all force;
end
