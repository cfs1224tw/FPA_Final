function Tall = fp_run_all_sessions_flmm(rootDir)
% FP_RUN_ALL_SESSIONS_FLMM_FROM_NATIVE
%   Use native event-locked pipeline (non-PASTa) to export FLMM-ready tables.
%
% Output:
%   Tall : merged FLMM wide table
%
% Files written to FLMM_Export_CSV:
%   - one per-session FLMM table in peranimal/
%   - all_sessions_flmm_table.csv
%   - time_axis.csv
%   - pipeline_failures.csv (if any session fails)

    if nargin < 1 || isempty(rootDir)
        rootDir = '/Users/foxking/Desktop/FPA_Final';
    end

    if ~exist('TDTbin2mat', 'file')
        error('TDTbin2mat not on path. addpath(genpath(''/path/to/TDTMatlabSDK'')) first.');
    end

    sessionKeyFile = fullfile(rootDir, 'SessionKey.xlsx');
    if ~isfile(sessionKeyFile)
        error('SessionKey.xlsx not found at: %s', sessionKeyFile);
    end

    SessionKey = readtable(sessionKeyFile);

    outRoot = fullfile(rootDir, 'FLMM_Export_CSV');
    if ~isfolder(outRoot)
        mkdir(outRoot);
    end
    perAnimalRoot = fullfile(outRoot, 'peranimal');
    if ~isfolder(perAnimalRoot)
        mkdir(perAnimalRoot);
    end
    timePath = fullfile(outRoot, 'time_axis.csv');

    nSess = height(SessionKey);
    fprintf('Found %d sessions in SessionKey.\n', nSess);

    failLog = {};
    timeAxis = [];
    timeAxisSet = false;

    for i = 1:nSess
        try
            if ismember('IncludeFlag', SessionKey.Properties.VariableNames)
                if ~SessionKey.IncludeFlag(i)
                    fprintf('[%3d/%3d] Skipping (IncludeFlag=0)\n', i, nSess);
                    continue;
                end
            end

            row = SessionKey(i,:);

            AnimalID   = strtrim(string(row.AnimalID));
            Genotype   = strtrim(string(row.Genotype));
            Region     = strtrim(string(row.Region));
            BlockType  = strtrim(string(row.BlockType));
            TankPath   = strtrim(string(row.TankPath));
            TankFolder = strtrim(string(row.TankFolderName));

            DateStr    = "";
            if ismember('DateStr', SessionKey.Properties.VariableNames)
                DateStr = strtrim(string(row.DateStr));
            end

            BehaviorPath = "";
            if ismember('BehaviorPath', SessionKey.Properties.VariableNames)
                BehaviorPath = strtrim(string(row.BehaviorPath));
            end

            fprintf('\n[%3d/%3d] %s | %s | %s | %s\n', ...
                i, nSess, AnimalID, Region, BlockType, TankFolder);

            safeID     = safe_str(AnimalID);
            safeRegion = safe_str(Region);
            safeBlock  = safe_str(BlockType);
            safeTank   = safe_str(TankFolder);

            outName = sprintf('%s_%s_%s_%s_flmm_table.csv', ...
                safeID, safeRegion, safeBlock, safeTank);
            outPath = fullfile(perAnimalRoot, outName);

            if isfile(outPath)
                fprintf('  Skipping existing peranimal FLMM table: %s\n', outName);
                continue;
            end

            if ~isfolder(TankPath)
                warning('TankPath not found: %s. Skipping session.', TankPath);
                continue;
            end

            if BehaviorPath == "" || ~isfile(char(BehaviorPath))
                warning('Behavior file missing for this session. Skipping.');
                continue;
            end

            B = load(char(BehaviorPath));
            if ~isfield(B, 'dayofdata')
                warning('Behavior MAT has no variable "dayofdata". Skipping.');
                continue;
            end
            dayofdata = B.dayofdata;

            meta = struct();
            meta.ID         = AnimalID;
            meta.genotype   = Genotype;
            meta.region     = Region;
            meta.block_type = BlockType;
            meta.date       = DateStr;
            meta.tankPath   = TankPath;
            meta.behavPath  = BehaviorPath;
            meta.session    = TankFolder;

            [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
                TankPath, meta, ...
                'BaqScalingType','OLS', ...
                'FilterType','bandpass', ...
                'HighpassCutoff',0.0051, ...
                'LowpassCutoff',2.2860, ...
                'FilterOrder',3, ...
                'Padding',true, ...
                'PaddingPerc',0.1);

            if ~timeAxisSet
                timeAxis = t(:);
                timeAxisSet = true;
            else
                if numel(t) ~= numel(timeAxis) || any(abs(t(:) - timeAxis) > 1e-10)
                    warning(['Time axis differs from previous sessions. ' ...
                             'Using the first valid time axis for export.']);
                end
            end

            labels = fp_build_labels_from_dayofdata(dayofdata, BlockType);

            sub = fp_build_sub_for_flmm_native(z_eventlocked, t, meta, labels);
            T   = fp_sub_to_flmm_table_native(sub);

            writetable(T, outPath);

            fprintf('  Saved FLMM table: %s\n', outName);

        catch ME
            failLog(end+1,1:3) = {i, char(TankFolder), ME.message};
            warning('Error in session %d: %s', i, ME.message);
        end
    end

    if timeAxisSet
        Ttime = table((1:numel(timeAxis))', timeAxis, ...
            'VariableNames', {'time_index', 'time_sec'});
        writetable(Ttime, timePath);
    elseif isfile(timePath)
        Ttime = readtable(timePath, 'VariableNamingRule', 'preserve');
        if all(ismember({'time_index','time_sec'}, Ttime.Properties.VariableNames))
            timeAxis = Ttime.time_sec;
            fprintf('No new time axis written. Reusing existing: %s\n', timePath);
        else
            warning('Existing time_axis.csv is missing required columns.');
        end
    else
        timeAxis = rebuild_time_axis_from_sessionkey(SessionKey);
        if ~isempty(timeAxis)
            Ttime = table((1:numel(timeAxis))', timeAxis, ...
                'VariableNames', {'time_index', 'time_sec'});
            writetable(Ttime, timePath);
            fprintf('Rebuilt time axis from the first available session: %s\n', timePath);
        else
            warning('No time axis available to export.');
        end
    end

    if ~isempty(failLog)
        Tfail = cell2table(failLog, 'VariableNames', ...
            {'SessionIndex','SessionName','ErrorMessage'});
        writetable(Tfail, fullfile(outRoot, 'pipeline_failures.csv'));
    end

    perAnimalFiles = dir(fullfile(perAnimalRoot, '*_flmm_table.csv'));
    if isempty(perAnimalFiles)
        warning('No peranimal session tables found.');
        Tall = table();
        return
    end

    allTables = cell(numel(perAnimalFiles), 1);
    keep = false(numel(perAnimalFiles), 1);
    for k = 1:numel(perAnimalFiles)
        fpath = fullfile(perAnimalRoot, perAnimalFiles(k).name);
        try
            Tread = readtable(fpath, 'VariableNamingRule', 'preserve');
            allTables{k} = normalize_flmm_table_types(Tread);
            keep(k) = true;
        catch ME
            warning('Failed to read peranimal FLMM table %s: %s', ...
                perAnimalFiles(k).name, ME.message);
        end
    end

    allTables = allTables(keep);
    if isempty(allTables)
        warning('No readable peranimal session tables found.');
        Tall = table();
        return
    end

    Tall = vertcat(allTables{:});
    writetable(Tall, fullfile(outRoot, 'all_sessions_flmm_table.csv'));

    fprintf('\nAll sessions processed.\n');
end


function sub = fp_build_sub_for_flmm_native(z_eventlocked, t, meta, labels)

    nTrial = size(z_eventlocked, 1);

    sub = struct();
    sub.raw = struct();
    sub.raw.z_trials = z_eventlocked;
    sub.raw.t = t(:)';

    sub.meta = struct();
    sub.meta.ID        = string(meta.ID);
    sub.meta.genotype  = string(meta.genotype);
    sub.meta.region    = string(meta.region);
    sub.meta.condition = string(meta.block_type);
    sub.meta.session   = string(meta.session);
    sub.meta.nTrial    = nTrial;

    sub.labels = fit_labels_to_trial_count(labels, nTrial);
end


function labelsOut = fit_labels_to_trial_count(labels, nTrial)

    labelsOut = struct();
    if isempty(labels) || ~isstruct(labels)
        return
    end

    fn = fieldnames(labels);
    for i = 1:numel(fn)
        f = fn{i};
        v = labels.(f);

        if isstring(v) || ischar(v) || iscellstr(v)
            v = string(v);
            v = v(:);
            if numel(v) >= nTrial
                v = v(1:nTrial);
            else
                v(end+1:nTrial,1) = "";
            end
        elseif islogical(v)
            v = double(v(:));
            if numel(v) >= nTrial
                v = v(1:nTrial);
            else
                v(end+1:nTrial,1) = nan;
            end
        elseif isnumeric(v)
            v = v(:);
            if numel(v) >= nTrial
                v = v(1:nTrial);
            else
                v(end+1:nTrial,1) = nan;
            end
        end

        labelsOut.(f) = v;
    end

    if isfield(labelsOut, 'tone_id') && ~isfield(labelsOut, 'tone')
        labelsOut.tone = labelsOut.tone_id;
    end
    if isfield(labelsOut, 'hitFA') && ~isfield(labelsOut, 'outcome')
        labelsOut.outcome = labelsOut.hitFA;
    end
end


function T = fp_sub_to_flmm_table_native(sub)

    Z = sub.raw.z_trials;
    [nTrial, nTime] = size(Z);

    id = string(sub.meta.ID);
    region = string(sub.meta.region);
    condition = string(sub.meta.condition);
    session = string(sub.meta.session);

    genotype_label = upper(string(sub.meta.genotype));
    genotype = double(strcmpi(genotype_label, "FX"));

    trial = (1:nTrial)';

    outcome = get_label_string_native(sub.labels, ["hitFA","outcome"], nTrial, "Other");
    isHit   = double(strcmpi(outcome, "Hit"));
    isFA    = double(strcmpi(outcome, "FA"));

    tone = get_label_numeric_native(sub.labels, ["tone","tone_id"], nTrial, nan);
    octave = get_label_numeric_native(sub.labels, ["octave_id","octave"], nTrial, nan);
    trial_role = get_label_string_native(sub.labels, ["trial_role"], nTrial, "");
    distractor_modality = get_label_string_native(sub.labels, ["distractor_modality"], nTrial, "");
    clean_context = get_label_string_native(sub.labels, ["clean_context"], nTrial, "");
    rt = get_label_numeric_native(sub.labels, ["rt"], nTrial, nan);

    id_col = repmat(id, nTrial, 1);
    gen_col = repmat(genotype, nTrial, 1);
    genotype_label_col = repmat(genotype_label, nTrial, 1);
    region_col = repmat(region, nTrial, 1);
    condition_col = repmat(condition, nTrial, 1);
    session_col = repmat(session, nTrial, 1);

    photCols = "Y." + string(1:nTime);
    Tphot = array2table(Z, 'VariableNames', cellstr(photCols));

    T = table(id_col, gen_col, genotype_label_col, region_col, condition_col, session_col, ...
        trial, tone, octave, outcome, isHit, isFA, trial_role, distractor_modality, clean_context, rt, ...
        'VariableNames', {'id','genotype','genotype_label','region','condition','session', ...
        'trial','tone','octave','outcome','isHit','isFA','trial_role','distractor_modality','clean_context','rt'});

    T = [T Tphot];
end


function s = get_label_string_native(labels, keys, nTrial, defaultVal)
    s = repmat(string(defaultVal), nTrial, 1);
    if ~isstruct(labels), return; end
    f = fieldnames(labels);
    for k = 1:numel(keys)
        hit = strcmpi(f, keys(k));
        if any(hit)
            v = string(labels.(f{find(hit,1)}));
            v = v(:);
            if numel(v) >= nTrial
                s = v(1:nTrial);
            else
                s = v;
                s(end+1:nTrial,1) = string(defaultVal);
            end
            return
        end
    end
end


function x = get_label_numeric_native(labels, keys, nTrial, defaultVal)
    x = repmat(defaultVal, nTrial, 1);
    if ~isstruct(labels), return; end
    f = fieldnames(labels);
    for k = 1:numel(keys)
        hit = strcmpi(f, keys(k));
        if any(hit)
            v = double(labels.(f{find(hit,1)}));
            v = v(:);
            if numel(v) >= nTrial
                x = v(1:nTrial);
            else
                x = v;
                x(end+1:nTrial,1) = defaultVal;
            end
            return
        end
    end
end


function s = safe_str(x)
    s = char(string(x));
    s = strrep(s, ' ', '');
    s = strrep(s, '/', '-');
    s = strrep(s, '\', '-');
    s = strrep(s, ':', '-');
end


function timeAxis = rebuild_time_axis_from_sessionkey(SessionKey)
    timeAxis = [];

    for i = 1:height(SessionKey)
        try
            if ismember('IncludeFlag', SessionKey.Properties.VariableNames)
                if ~SessionKey.IncludeFlag(i)
                    continue;
                end
            end

            row = SessionKey(i,:);

            TankPath = strtrim(string(row.TankPath));
            if ~isfolder(char(TankPath))
                continue;
            end

            AnimalID = strtrim(string(row.AnimalID));
            Genotype = strtrim(string(row.Genotype));
            Region   = strtrim(string(row.Region));
            BlockType = strtrim(string(row.BlockType));

            DateStr = "";
            if ismember('DateStr', SessionKey.Properties.VariableNames)
                DateStr = strtrim(string(row.DateStr));
            end

            BehaviorPath = "";
            if ismember('BehaviorPath', SessionKey.Properties.VariableNames)
                BehaviorPath = strtrim(string(row.BehaviorPath));
            end

            meta = struct();
            meta.ID         = AnimalID;
            meta.genotype   = Genotype;
            meta.region     = Region;
            meta.block_type = BlockType;
            meta.date       = DateStr;
            meta.tankPath   = TankPath;
            meta.behavPath  = BehaviorPath;

            [~, t] = fp_load_tdt_eventlocked_filter( ...
                TankPath, meta, ...
                'BaqScalingType','OLS', ...
                'FilterType','bandpass', ...
                'HighpassCutoff',0.0051, ...
                'LowpassCutoff',2.2860, ...
                'FilterOrder',3, ...
                'Padding',true, ...
                'PaddingPerc',0.1);

            timeAxis = t(:);
            return;
        catch
        end
    end
end


function T = normalize_flmm_table_types(T)
    vars = T.Properties.VariableNames;

    stringVars = {'id','genotype_label','region','condition','session', ...
                  'outcome','trial_role','distractor_modality','clean_context'};
    numericVars = {'genotype','trial','tone','octave','isHit','isFA','rt'};

    for i = 1:numel(stringVars)
        v = stringVars{i};
        if ismember(v, vars)
            T.(v) = string(T.(v));
        end
    end

    for i = 1:numel(numericVars)
        v = numericVars{i};
        if ismember(v, vars)
            T.(v) = double(T.(v));
        end
    end

    yMask = startsWith(vars, 'Y.');
    for i = find(yMask)
        T.(vars{i}) = double(T.(vars{i}));
    end
end
