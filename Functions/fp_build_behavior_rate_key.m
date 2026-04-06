function RateKey = fp_build_behavior_rate_key(behavRoot, SessionKey)
% FP_BUILD_BEHAVIOR_RATE_KEY
%   Scan behavior folder and compute behavior rates for each .mat file.
%   FIX: Separate CleanOnly vs DistractorOnly using SessionKey.BlockType.
%
% Input
%   behavRoot   : folder containing behavior .mat files
%   SessionKey  : table that includes at least:
%                   - BehaviorFile (string/cellstr)
%                   - BlockType    (string/cellstr) e.g. CleanOnly / DistractorOnly / Aud50 / ...
%
% Output
%   RateKey table with columns:
%     BehaviorFile
%     HitRate_All_Pct, FARate_All_Pct, OmissRate_All_Pct, nTrials_All
%     HitRate_Clean_Pct, FARate_Clean_Pct, OmissRate_Clean_Pct, nTrials_Clean
%     HitRate_Dist_Pct, FARate_Dist_Pct, OmissRate_Dist_Pct, nTrials_Dist

    if nargin < 1 || isempty(behavRoot)
        error('behavRoot is required.');
    end
    if nargin < 2 || isempty(SessionKey) || ~istable(SessionKey)
        error('SessionKey table is required to separate CleanOnly vs DistractorOnly.');
    end
    if ~ismember('BehaviorFile', SessionKey.Properties.VariableNames) || ...
       ~ismember('BlockType',    SessionKey.Properties.VariableNames)
        error('SessionKey must contain columns: BehaviorFile and BlockType.');
    end

    files = dir(fullfile(behavRoot, '*.mat'));
    n     = numel(files);

    BehaviorFile        = strings(n,1);

    HitRate_All_Pct     = nan(n,1);
    FARate_All_Pct      = nan(n,1);
    OmissRate_All_Pct   = nan(n,1);
    nTrials_All         = nan(n,1);

    HitRate_Clean_Pct   = nan(n,1);
    FARate_Clean_Pct    = nan(n,1);
    OmissRate_Clean_Pct = nan(n,1);
    nTrials_Clean       = nan(n,1);

    HitRate_Dist_Pct    = nan(n,1);
    FARate_Dist_Pct     = nan(n,1);
    OmissRate_Dist_Pct  = nan(n,1);
    nTrials_Dist        = nan(n,1);

    % --- Build BehaviorFile -> BlockType map from SessionKey ---
    map = SessionKey(:, {'BehaviorFile','BlockType'});

    % normalize to string for robust matching
    map.BehaviorFile = string(map.BehaviorFile);
    map.BlockType    = string(map.BlockType);

    % remove empty BehaviorFile rows
    map = map(map.BehaviorFile ~= "", :);

    % if duplicates exist, keep the first occurrence
    [~, ia] = unique(map.BehaviorFile, 'stable');
    map = map(ia, :);

    for k = 1:n
        fpath = fullfile(files(k).folder, files(k).name);
        BehaviorFile(k) = string(files(k).name);

        S = load(fpath, 'dayofdata');
        if ~isfield(S, 'dayofdata')
            warning('dayofdata not found in %s', fpath);
            continue;
        end

        B = fp_compute_behavior_rates_tony(S.dayofdata);

        % True 0-1 -> percentage
        HitRate_All_Pct(k)    = 100 * B.all.HitRate;
        FARate_All_Pct(k)     = 100 * B.all.FARate;
        OmissRate_All_Pct(k)  = 100 * B.all.OmissRate;
        nTrials_All(k)        = B.all.nTrials;

        HitRate_Clean_Pct(k)  = 100 * B.clean.HitRate;
        FARate_Clean_Pct(k)   = 100 * B.clean.FARate;
        OmissRate_Clean_Pct(k)= 100 * B.clean.OmissRate;
        nTrials_Clean(k)      = B.clean.nTrials;

        HitRate_Dist_Pct(k)   = 100 * B.dist.HitRate;
        FARate_Dist_Pct(k)    = 100 * B.dist.FARate;
        OmissRate_Dist_Pct(k) = 100 * B.dist.OmissRate;
        nTrials_Dist(k)       = B.dist.nTrials;

        % --- Override for DistractorOnly: treat All as Dist ---
        ix = find(map.BehaviorFile == BehaviorFile(k), 1, 'first');
        if ~isempty(ix)
            bt = lower(strtrim(map.BlockType(ix)));

            if contains(bt, "distractoronly")
                % Dist = All
                HitRate_Dist_Pct(k)   = HitRate_All_Pct(k);
                FARate_Dist_Pct(k)    = FARate_All_Pct(k);
                OmissRate_Dist_Pct(k) = OmissRate_All_Pct(k);
                nTrials_Dist(k)       = nTrials_All(k);

                % Clean cleared
                HitRate_Clean_Pct(k)   = NaN;
                FARate_Clean_Pct(k)    = NaN;
                OmissRate_Clean_Pct(k) = NaN;
                nTrials_Clean(k)       = 0;
            end
        end
    end

    RateKey = table(BehaviorFile, ...
        HitRate_All_Pct, FARate_All_Pct, OmissRate_All_Pct, nTrials_All, ...
        HitRate_Clean_Pct, FARate_Clean_Pct, OmissRate_Clean_Pct, nTrials_Clean, ...
        HitRate_Dist_Pct, FARate_Dist_Pct, OmissRate_Dist_Pct, nTrials_Dist);
end