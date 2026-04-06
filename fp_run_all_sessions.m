function fp_run_all_sessions(rootDir)
% FP_RUN_ALL_SESSIONS
%   Batch runner:
%     1) Read SessionKey.xlsx
%     2) For every session:
%          - Read TDT tank (TDTbin2mat)
%          - Read behavior (dayofdata)
%          - Create labels, data
%          - Run fp_analyze_session
%          - Save sub_*.mat
%
% Usage:
%   cd('/Users/foxking/Desktop/FPA_Final');
%   fp_run_all_sessions;
%   fp_run_all_sessions('/some/other/path');

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

    % Output folder
    outRoot = fullfile(rootDir, 'Results', 'session');
    if ~isfolder(outRoot)
        mkdir(outRoot);
    end

    nSess = height(SessionKey);
    fprintf('Found %d sessions in SessionKey.\n', nSess);

    for i = 1:nSess
        try
            % --- IncludeFlag (optional) ---
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

            % --- check tank folder ---
            if ~isfolder(TankPath)
                warning('  TankPath not found: %s. Skipping session.', TankPath);
                continue;
            end

            % --- load behavior ---
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

            % --- meta info struct ---
            meta = struct();
            meta.ID         = AnimalID;
            meta.genotype   = Genotype;
            meta.region     = Region;
            meta.block_type = BlockType;
            meta.date       = DateStr;
            meta.tankPath   = TankPath;
            meta.behavPath  = BehaviorPath;

            % --- TDT → event-locked z ---
            % Original 
            %[z_eventlocked, t] = fp_load_tdt_eventlocked(TankPath, meta);

            % % Nofilter
            % [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
            % TankPath, meta, ...
            % 'BaqScalingType','IRLS', ...
            % 'FilterType','nofilter', ...
            % 'Padding',false);

            % Bandpass
            [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
                TankPath, meta, ...
                'BaqScalingType','OLS', ...
                'FilterType','bandpass', ...
                'HighpassCutoff',0.0051, ...
                'LowpassCutoff',2.2860, ...
                'FilterOrder',3, ...
                'Padding',true, ...
                'PaddingPerc',0.1);

            % % Lowpass
            % [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
            % TankPath, meta, ...
            % 'BaqScalingType','OLS', ...
            % 'FilterType','lowpass', ...
            % 'LowpassCutoff',2.2860, ...
            % 'FilterOrder',3, ...
            % 'Padding',true, ...
            % 'PaddingPerc',0.1);

            % % Highpass
            % [z_eventlocked, t] = fp_load_tdt_eventlocked_filter( ...
            % TankPath, meta, ...
            % 'BaqScalingType','OLS', ...
            % 'FilterType','highpass', ...
            % 'HighpassCutoff',0.0051, ...
            % 'FilterOrder',3, ...
            % 'Padding',true, ...
            % 'PaddingPerc',0.1);

            % --- labels from behavior ---
            labels = fp_build_labels_from_dayofdata(dayofdata, BlockType);

            % --- build data struct for analyzer (handles mismatched trial #) ---
            data = fp_build_session_data(z_eventlocked, t, meta, labels);

            % --- config for AUC / Peak windows ---
            config = struct();
            config.winNames    = {'Response','Reward'};
            config.winRanges   = [0 2; 2 5];          % default windows
            config.winAreaMode = {'positive-only','negative-only'};
            config.baselineWin = [-6 -1];            % PSTH baseline [-6 -1]

            % --- run per-session analysis (All / Hit / FA) ---
            sub = fp_analyze_session(data, config);

            % --- save sub struct ---
            safeID      = safe_str(AnimalID);
            safeRegion  = safe_str(Region);
            safeBlock   = safe_str(BlockType);
            safeTank    = safe_str(TankFolder);

            outName = sprintf('sub_%s_%s_%s_%s.mat', ...
                safeID, safeRegion, safeBlock, safeTank);
            outPath = fullfile(outRoot, outName);

            save(outPath, 'sub', '-v7.3');
            fprintf('  Saved sub to: %s\n', outPath);

        catch ME
            warning('  Error in session %d: %s', i, ME.message);
        end
    end

    fprintf('\nAll sessions processed.\n');
end

% ----------------- local helper -----------------
function s = safe_str(x)
    s = char(string(x));
    s = strrep(s, ' ', '');
    s = strrep(s, '/', '-');
    s = strrep(s, '\', '-');
    s = strrep(s, ':', '-');
end
