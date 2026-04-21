function test_fp_gui_flmm_viewer_smoke(rootDir)
% TEST_FP_GUI_FLMM_VIEWER_SMOKE
% Smoke test for the standalone FLMM viewer. Verifies that the GUI opens,
% exposes the expected controls, runs one valid FLMM comparison, and
% populates the result panels without emitting warnings.

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(fileparts(mfilename('fullpath')));
    end

    close all force;
    lastwarn('');

    cleanupObj = onCleanup(@close_all_figures);

    addpath(genpath(rootDir));
    fp_gui_flmm_viewer(rootDir);
    drawnow;

    fig = findall(0, 'Type', 'figure', 'Tag', 'figFlmmViewer');
    assert(~isempty(fig), 'FLMM viewer figure was not created.');
    fig = fig(1);

    popupCompareVar = findobj(fig, 'Tag', 'popupCompareVar');
    popupReference = findobj(fig, 'Tag', 'popupReference');
    popupContrast = findobj(fig, 'Tag', 'popupContrast');
    popupRegion = findobj(fig, 'Tag', 'popupRegion');
    popupCondition = findobj(fig, 'Tag', 'popupCondition');
    popupOutcome = findobj(fig, 'Tag', 'popupOutcome');
    editDs = findobj(fig, 'Tag', 'editDs');
    editXmin = findobj(fig, 'Tag', 'editXmin');
    editXmax = findobj(fig, 'Tag', 'editXmax');
    editYmin = findobj(fig, 'Tag', 'editYmin');
    editYmax = findobj(fig, 'Tag', 'editYmax');
    btnRun = findobj(fig, 'Tag', 'btnRunFlmm');
    tablePreview = findobj(fig, 'Tag', 'tablePreview');
    tableCounts = findobj(fig, 'Tag', 'tableCounts');
    tableWindows = findobj(fig, 'Tag', 'tableWindows');
    statusBox = findobj(fig, 'Tag', 'statusBox');
    progressText = findobj(fig, 'Tag', 'textProgress');
    axIntercept = findobj(fig, 'Tag', 'axIntercept');
    axEffect = findobj(fig, 'Tag', 'axEffect');

    assert(~isempty(popupCompareVar), 'Compare variable popup not found.');
    assert(~isempty(popupReference), 'Reference popup not found.');
    assert(~isempty(popupContrast), 'Contrast popup not found.');
    assert(~isempty(popupRegion), 'Region popup not found.');
    assert(~isempty(popupCondition), 'Condition popup not found.');
    assert(~isempty(popupOutcome), 'Outcome popup not found.');
    assert(~isempty(editDs), 'Downsampling edit box not found.');
    assert(~isempty(editXmin) && ~isempty(editXmax), 'X limit controls not found.');
    assert(~isempty(editYmin) && ~isempty(editYmax), 'Y limit controls not found.');
    assert(~isempty(btnRun), 'Run FLMM button not found.');
    assert(~isempty(tablePreview), 'Preview table not found.');
    assert(~isempty(tableCounts), 'Counts table not found.');
    assert(~isempty(tableWindows), 'Windows table not found.');
    assert(~isempty(statusBox), 'Status box not found.');
    assert(~isempty(progressText), 'Progress text not found.');
    assert(~isempty(axIntercept) && ~isempty(axEffect), 'Coefficient axes not found.');

    set_popup_to_label(popupCompareVar, 'Genotype');
    fire_callback(popupCompareVar);
    drawnow;

    set_popup_to_label(popupReference, 'WT');
    set_popup_to_label(popupContrast, 'FX');
    set_popup_to_label(popupRegion, 'AUX');
    set_popup_to_label(popupCondition, 'CleanOnly');
    set_popup_to_label(popupOutcome, 'Hit');
    fire_callback(popupReference);
    fire_callback(popupContrast);
    fire_callback(popupRegion);
    fire_callback(popupCondition);
    fire_callback(popupOutcome);

    set(editDs, 'String', '100');
    set(editXmin, 'String', '-2');
    set(editXmax, 'String', '10');
    set(editYmin, 'String', '-1.5');
    set(editYmax, 'String', '1.5');
    drawnow;

    previewData = get(tablePreview, 'Data');
    assert(~isempty(previewData), 'Preview table did not populate.');
    assert(size(previewData, 1) == 2, 'Preview table should contain two comparison levels.');
    assert(all(cell2mat(previewData(:, 2)) > 0), 'Preview table contains a zero-trial comparison level.');

    fire_callback(btnRun);
    drawnow;

    countsData = get(tableCounts, 'Data');
    assert(~isempty(countsData), 'Counts table did not populate after Run FLMM.');
    assert(size(countsData, 1) == 2, 'Counts table should contain two modeled levels.');

    windowsData = get(tableWindows, 'Data');
    assert(~isempty(windowsData), 'Significant windows table did not populate.');

    statusLines = get_as_cellstr(get(statusBox, 'String'));
    assert(any(contains(string(statusLines), "Finished:")), ...
        'Status box did not report a successful FLMM finish.');
    assert(~any(contains(lower(string(statusLines)), "failed")), ...
        'Status box reported a failed FLMM run.');

    progressLabel = string(get(progressText, 'String'));
    assert(contains(progressLabel, "Completed") || contains(progressLabel, "Idle"), ...
        'Progress indicator did not return to a completed/idle state.');

    assert(count_line_objects(axIntercept) >= 2, ...
        'Intercept axis did not render the expected FLMM traces.');
    assert(count_line_objects(axEffect) >= 2, ...
        'Effect axis did not render the expected FLMM traces.');

    [warnMsg, warnId] = lastwarn;
    assert(isempty(warnMsg), 'FLMM viewer emitted warning: %s (%s)', warnMsg, warnId);

    disp('fp_gui_flmm_viewer smoke test passed');

    clear cleanupObj;
end

function set_popup_to_label(h, targetLabel)
    items = get_as_cellstr(get(h, 'String'));
    idx = find(strcmp(items, targetLabel), 1, 'first');
    assert(~isempty(idx), 'Popup label "%s" was not found.', targetLabel);
    set(h, 'Value', idx);
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

function n = count_line_objects(ax)
    n = numel(findall(ax, 'Type', 'line'));
end

function close_all_figures()
    close all force;
end
