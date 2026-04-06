function fp_run_all_sessions_FLMM_export(rootDir)
% FP_RUN_ALL_SESSIONS_FLMM_EXPORT
%   Batch runner for FLMM-ready fiber photometry export.
%
%   FINAL VERSION:
%     1) Reads SessionKey.xlsx
%     2) Processes only CleanOnly sessions from AUX / PFC
%     3) Loads TDT tank and behavior
%     4) Builds labels and aligned session data
%     5) Exports two wide-format CSV tables:
%          - AUX_CleanOnly_trials.csv
%          - PFC_CleanOnly_trials.csv
%     6) Exports one time-axis CSV:
%          - time_axis.csv
%
%   Wide CSV format:
%     One row = one trial
%     Columns:
%       animal, genotype, region, block_type, tank_folder, trial, outcome,
%       Y_1, Y_2, ..., Y_n
%
%   Notes:
%     - Y_1 ... Y_n are time indices, not seconds.
%     - Real time is stored separately in time_axis.csv.
%
% Usage:
%   fp_run_all_sessions_FLMM_export;
%   fp_run_all_sessions_FLMM_export('/some/other/path');

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(mfilename('fullpath'));
    end

    % ---- check TDT SDK ----
    if ~exist('TDTbin2mat', 'file')
        error('TDTbin2mat not on path. addpath(genpath(''/path/to/TDTMatlabSDK'')) first.');
    end

    sessionKeyFile = fullfile(rootDir, 'SessionKey.xlsx');
    if ~isfile(sessionKeyFile)
        error('SessionKey.xlsx not found at: %s', sessionKeyFile);
    end

    SessionKey = readtable(sessionKeyFile);

    % ---- output folder ----
    outCsvRoot = fullfile(rootDir, 'Results', 'FLMM_export');
    if ~isfolder(outCsvRoot)
        mkdir(outCsvRoot);
    end

    fprintf('Output folder:\n%s\n\n', outCsvRoot);

    % ---- accumulators ----
    AUX_table = table();
    PFC_table = table();

    % ---- shared time axis ----
    timeAxis = [];
    timeAxisSet = false;

    nSess = height(SessionKey);
    fprintf('Found %d sessions in SessionKey.\n', nSess);

    for i = 1:nSess
        try
            % ------------------------------------------------------------
            % optional IncludeFlag
            % ------------------------------------------------------------
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

            DateStr = "";
            if ismember('DateStr', SessionKey.Properties.VariableNames)
                DateStr = strtrim(string(row.DateStr));
            end

            BehaviorPath = "";
            if ismember('BehaviorPath', SessionKey.Properties.VariableNames)
                BehaviorPath = strtrim(string(row.BehaviorPath));
            end

            fprintf('\n[%3d/%3d] %s | %s | %s | %s\n', ...
                i, nSess, AnimalID, Region, BlockType, TankFolder);

            % ------------------------------------------------------------
            % only CleanOnly + AUX/PFC
            % ------------------------------------------------------------
            if ~(BlockType == "CleanOnly" && (Region == "AUX" || Region == "PFC"))
                fprintf('  Skipping (not CleanOnly AUX/PFC).\n');
                continue;
            end

            % ------------------------------------------------------------
            % check tank folder
            % ------------------------------------------------------------
            if ~isfolder(char(TankPath))
                warning('  TankPath not found: %s. Skipping session.', TankPath);
                continue;
            end

            % ------------------------------------------------------------
            % load behavior
            % ------------------------------------------------------------
            if BehaviorPath == "" || ~isfile(char(BehaviorPath))
                warning('  Behavior file missing for this session. Skipping.');
                continue;
            end

            B = load(char(BehaviorPath));
            if ~isfield(B, 'dayofdata')
                warning('  Behavior MAT has no variable "dayofdata". Skipping.');
                continue;
            end
            dayofdata = B.dayofdata;

            % ------------------------------------------------------------
            % meta info
            % ------------------------------------------------------------
            meta = struct();
            meta.ID         = AnimalID;
            meta.genotype   = Genotype;
            meta.region     = Region;
            meta.block_type = BlockType;
            meta.date       = DateStr;
            meta.tankPath   = TankPath;
            meta.behavPath  = BehaviorPath;
            meta.tankFolder = TankFolder;

            % ------------------------------------------------------------
            % TDT -> event-locked z
            % ------------------------------------------------------------
            [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
                TankPath, meta, ...
                'BaqScalingType','OLS', ...
                'FilterType','bandpass', ...
                'HighpassCutoff',0.0051, ...
                'LowpassCutoff',2.2860, ...
                'FilterOrder',3, ...
                'Padding',true, ...
                'PaddingPerc',0.1);

            % ------------------------------------------------------------
            % store first valid time axis
            % ------------------------------------------------------------
            if ~timeAxisSet
                timeAxis = t(:);
                timeAxisSet = true;
            else
                if numel(t) ~= numel(timeAxis) || any(abs(t(:) - timeAxis) > 1e-10)
                    warning(['  Time axis differs from previous sessions. ' ...
                             'Using the first valid time axis for export.']);
                end
            end

            % ------------------------------------------------------------
            % labels from behavior
            % ------------------------------------------------------------
            labels = fp_build_labels_from_dayofdata(dayofdata, BlockType);

            % ------------------------------------------------------------
            % align photometry + labels
            % ------------------------------------------------------------
            data = fp_build_session_data(z_eventlocked, t, meta, labels);

            fprintf('  Photometry trials: %d\n', size(z_eventlocked,1));
            fprintf('  Behavior trials:   %d\n', get_label_count(labels));
            fprintf('  Final data trials: %d\n', size(data.z,1));

            % ------------------------------------------------------------
            % build minimal sub-like struct for export only
            % ------------------------------------------------------------
            sub = struct();
            sub.raw = struct();
            sub.raw.z_trials = data.z;
            sub.raw.t        = data.t;
            sub.meta         = data.meta;
            sub.labels       = data.labels;

            % ------------------------------------------------------------
            % convert to wide FLMM table
            % ------------------------------------------------------------
            T = trials_to_wide_table(sub);

            if Region == "AUX"
                AUX_table = append_table(AUX_table, T);
            elseif Region == "PFC"
                PFC_table = append_table(PFC_table, T);
            end

            fprintf('  Added %d trials to export table.\n', height(T));

        catch ME
            warning('  Error in session %d: %s', i, ME.message);
        end
    end

    % --------------------------------------------------------------------
    % final CSV export
    % --------------------------------------------------------------------
    auxPath  = fullfile(outCsvRoot, 'AUX_CleanOnly_trials.csv');
    pfcPath  = fullfile(outCsvRoot, 'PFC_CleanOnly_trials.csv');
    timePath = fullfile(outCsvRoot, 'time_axis.csv');

    if ~isempty(AUX_table)
        writetable(AUX_table, auxPath);
        fprintf('\nSaved AUX CSV:\n%s\n', auxPath);
    else
        fprintf('\nNo AUX CleanOnly sessions were exported.\n');
    end

    if ~isempty(PFC_table)
        writetable(PFC_table, pfcPath);
        fprintf('Saved PFC CSV:\n%s\n', pfcPath);
    else
        fprintf('No PFC CleanOnly sessions were exported.\n');
    end

    if timeAxisSet
        TimeTable = table((1:numel(timeAxis))', timeAxis, ...
            'VariableNames', {'time_index', 'time_sec'});
        writetable(TimeTable, timePath);
        fprintf('Saved time axis CSV:\n%s\n', timePath);
    else
        fprintf('No time axis exported because no valid session was processed.\n');
    end

    fprintf('\nAll sessions processed.\n');
end

% =========================================================================
% Convert one session to wide table
% One row = one trial
% =========================================================================
function T = trials_to_wide_table(sub)

    Z = sub.raw.z_trials;   % [nTrial x nTime]
    [nTrial, nTime] = size(Z);

    animal     = repmat(string(sub.meta.ID),         nTrial, 1);
    genotype   = repmat(string(sub.meta.genotype),   nTrial, 1);
    region     = repmat(string(sub.meta.region),     nTrial, 1);
    block_type = repmat(string(sub.meta.block_type), nTrial, 1);

    if isfield(sub.meta, 'tankFolder')
        tank_folder = repmat(string(sub.meta.tankFolder), nTrial, 1);
    else
        tank_folder = repmat("", nTrial, 1);
    end

    trial = (1:nTrial)';

    % ---- outcome ----
    outcome = repmat("Other", nTrial, 1);
    if isfield(sub, 'labels') && isfield(sub.labels, 'hitFA') && ~isempty(sub.labels.hitFA)
        if isstring(sub.labels.hitFA)
            tmp = sub.labels.hitFA(:);
        elseif iscell(sub.labels.hitFA)
            tmp = string(sub.labels.hitFA(:));
        else
            tmp = string(sub.labels.hitFA(:));
        end

        nUse = min(numel(tmp), nTrial);
        outcome(1:nUse) = tmp(1:nUse);
    end

    % ---- metadata columns first ----
    T = table(animal, genotype, region, block_type, tank_folder, trial, outcome);

    % ---- signal columns Y_1 ... Y_n ----
    for k = 1:nTime
        varName = sprintf('Y_%d', k);
        T.(varName) = Z(:, k);
    end
end

% =========================================================================
% Append tables safely
% =========================================================================
function Tbig = append_table(Tbig, Tnew)
    if isempty(Tbig)
        Tbig = Tnew;
    else
        Tbig = [Tbig; Tnew];
    end
end

% =========================================================================
% Count labels safely for console output
% =========================================================================
function n = get_label_count(labels)

    n = NaN;

    if isfield(labels, 'hitFA') && ~isempty(labels.hitFA)
        n = numel(labels.hitFA);
        return;
    end

    if isfield(labels, 'trial_role') && ~isempty(labels.trial_role)
        n = numel(labels.trial_role);
        return;
    end

    if isfield(labels, 'clean_context') && ~isempty(labels.clean_context)
        n = numel(labels.clean_context);
        return;
    end
end
