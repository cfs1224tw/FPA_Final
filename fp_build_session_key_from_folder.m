function fp_build_session_key_from_folder(rootDir)
% FP_BUILD_SESSION_KEY_FROM_FOLDER
% Auto-scan AnimalData and generate a SessionKey.xlsx
% each row = 1 TDT session (tank).
%
% Folder layout assumed:
%   FP_Project/
%       AnimalData/<AnimalID>/<Region>/<BlockType>/<TankFolderName>/
%       behavior/YYYY-MM-DDSubjNNN.mat
%
% Output:
%   SessionKey.xlsx in FP_Project/

    % ==== 0. Path ====
    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(mfilename('fullpath'));
    end
    animalRoot = fullfile(rootDir, 'AnimalData');
    behavRoot  = fullfile(rootDir, 'behavior');

    if ~isfolder(animalRoot)
        error('AnimalData folder not found at: %s', animalRoot);
    end

    % ==== 1. Struct array for row ====
    rows = struct( ...
        'AnimalID',      {}, ...
        'SubjNum',       {}, ...
        'Genotype',      {}, ...
        'Region',        {}, ...
        'BlockType',     {}, ...
        'TankFolderName',{}, ...
        'TankPath',      {}, ...
        'DateStr',       {}, ...
        'BehaviorFile',  {}, ...
        'BehaviorPath',  {}, ...
        'IncludeFlag',   {}, ...
        'Notes',         {} );

    % ==== 2. Screen all dir ====
    dAnimals = dir(animalRoot);
    for iA = 1:numel(dAnimals)
        if ~dAnimals(iA).isdir, continue; end
        nameA = dAnimals(iA).name;
        if ismember(nameA, {'.','..'}), continue; end

        AnimalID = string(nameA);   % e.g. "WT_633"
        [Genotype, SubjNum] = parse_animal_id(AnimalID);

        animalPath = fullfile(animalRoot, nameA);

        % Region (AUX / PFC)
        dRegions = dir(animalPath);
        for iR = 1:numel(dRegions)
            if ~dRegions(iR).isdir, continue; end
            nameR = dRegions(iR).name;
            if ismember(nameR, {'.','..'}), continue; end

            Region = string(nameR);   % e.g. "AUX" / "PFC"
            regionPath = fullfile(animalPath, nameR);

            % BlockType: CleanOnly / Aud50 / Vis50
            dBlocks = dir(regionPath);
            for iB = 1:numel(dBlocks)
                if ~dBlocks(iB).isdir, continue; end
                nameB = dBlocks(iB).name;
                if ismember(nameB, {'.','..'}), continue; end

                BlockType = string(nameB);   % "CleanOnly" / "Aud50" / "Vis50"
                blockPath = fullfile(regionPath, nameB);

                % TDT tank folder
                dTanks = dir(blockPath);
                for iT = 1:numel(dTanks)
                    if ~dTanks(iT).isdir, continue; end
                    nameT = dTanks(iT).name;
                    if ismember(nameT, {'.','..'}), continue; end

                    TankFolderName = string(nameT);
                    TankPath       = string(fullfile(blockPath, nameT));

                    % Tank parse recording date
                    DateStr = parse_date_from_tankname(TankFolderName);

                    % BehaviorFile / Path
                    BehaviorFile  = "";
                    BehaviorPath  = "";

                    % If date + subj, get behavior name
                    if strlength(DateStr) > 0 && ~isnan(SubjNum) && SubjNum > 0
                        candName = sprintf('%sSubj%d.mat', DateStr, SubjNum); % e.g. "2024-12-21Subj640.mat"
                        candPath = fullfile(behavRoot, candName);
                        if exist(candPath, 'file')
                            BehaviorFile = string(candName);
                            BehaviorPath = string(candPath);
                        end
                    end

                    % Put in rows
                    row = struct();
                    row.AnimalID       = AnimalID;
                    row.SubjNum        = SubjNum;
                    row.Genotype       = Genotype;
                    row.Region         = Region;
                    row.BlockType      = BlockType;
                    row.TankFolderName = TankFolderName;
                    row.TankPath       = TankPath;
                    row.DateStr        = DateStr;
                    row.BehaviorFile   = BehaviorFile;
                    row.BehaviorPath   = BehaviorPath;
                    row.IncludeFlag    = true;      % Include all for now
                    row.Notes          = "";

                    rows(end+1) = row;
                end
            end
        end
    end

    % ==== 3. table ====
    if isempty(rows)
        warning('No sessions found under: %s', animalRoot);
        return;
    end

    SessionKey = struct2table(rows, 'AsArray', true);
    SessionKey.TankPath = string(SessionKey.TankPath);
    SessionKey = dedupe_sessionkey(SessionKey);

    % ==== 4. Call behavior-rate function，merge into SessionKey ====
    RateKey = fp_build_behavior_rate_key(behavRoot, SessionKey);

    % BehaviorFile left join and keep SessionKey row
    SessionKey = outerjoin(SessionKey, RateKey, ...
        'Keys', 'BehaviorFile', ...
        'MergeKeys', true, ...
        'Type', 'left');
    SessionKey.TankPath = string(SessionKey.TankPath);
    SessionKey = dedupe_sessionkey(SessionKey);

    % ==== 5. Incremental update (append new tanks to existing SessionKey) ====
    outFile = fullfile(rootDir, 'SessionKey.xlsx');
    
    % Ensure TankPath is a string column (for robust matching)
    if ~iscellstr(SessionKey.TankPath) && ~isstring(SessionKey.TankPath)
        SessionKey.TankPath = string(SessionKey.TankPath);
    end
    
    if isfile(outFile)
        OldKey = readtable(outFile);
    
        % If old file doesn't have TankPath, fall back to overwrite (or error)
        if ~ismember('TankPath', OldKey.Properties.VariableNames)
            error('Existing SessionKey.xlsx has no TankPath column. Cannot incremental update safely.');
        end
    
        % Make sure types match for comparison
        OldKey.TankPath = string(OldKey.TankPath);
        nOldBefore = height(OldKey);
        OldKey = dedupe_sessionkey(OldKey);

        % Refresh behavior-related fields for rows that already exist.
        refreshVars = intersect(SessionKey.Properties.VariableNames, OldKey.Properties.VariableNames);
        refreshVars = intersect(refreshVars, {'DateStr','BehaviorFile','BehaviorPath'});

        [isExisting, locOld] = ismember(SessionKey.TankPath, OldKey.TankPath);
        nRefreshed = 0;
        for r = find(isExisting(:))'
            rowChanged = false;
            for v = 1:numel(refreshVars)
                vn = refreshVars{v};
                newVal = SessionKey{r, vn};
                oldVal = OldKey{locOld(r), vn};
                if ~isequaln(string(newVal), string(oldVal))
                    OldKey = assign_table_value(OldKey, locOld(r), vn, newVal);
                    rowChanged = true;
                end
            end
            if rowChanged
                nRefreshed = nRefreshed + 1;
            end
        end
    
        % Identify new rows (TankPath not in old)
        isNew = ~ismember(SessionKey.TankPath, OldKey.TankPath);
        AddKey = SessionKey(isNew, :);
    
        if isempty(AddKey)
            if nRefreshed > 0
                writetable(OldKey, outFile);
                fprintf('SessionKey refreshed (%d existing rows updated):\n  %s\n', ...
                    nRefreshed, outFile);
            elseif height(OldKey) < nOldBefore
                writetable(OldKey, outFile);
                fprintf('SessionKey cleaned (removed %d duplicate rows):\n  %s\n', ...
                    nOldBefore - height(OldKey), outFile);
            else
                fprintf('No new tanks found. SessionKey unchanged:\n  %s\n', outFile);
            end
            return;
        end
    
        % --- OPTIONAL: keep OldKey column schema (recommended) ---
        % If OldKey has extra manual columns, add them to AddKey as missing
        oldVars = OldKey.Properties.VariableNames;
        addVars = AddKey.Properties.VariableNames;
    
        missingInAdd = setdiff(oldVars, addVars);
        for k = 1:numel(missingInAdd)
            v = missingInAdd{k};
            % Create a default missing column in AddKey with same type-ish as OldKey
            proto = OldKey.(v);
            AddKey.(v) = make_default_column(proto, height(AddKey));
        end
    
        % If AddKey has new columns not in OldKey, add them to OldKey (so concat works)
        missingInOld = setdiff(addVars, oldVars);
        for k = 1:numel(missingInOld)
            v = missingInOld{k};
            proto = AddKey.(v);
            OldKey.(v) = make_default_column(proto, height(OldKey));
        end
    
        % Reorder AddKey columns to match OldKey
        AddKey = AddKey(:, OldKey.Properties.VariableNames);
    
        % Append
        nOldUnique = height(OldKey);
        UpdatedKey = [OldKey; AddKey];
        UpdatedKey.TankPath = string(UpdatedKey.TankPath);
        UpdatedKey = dedupe_sessionkey(UpdatedKey);
    
        writetable(UpdatedKey, outFile);
        fprintf('SessionKey updated (added %d new tanks):\n  %s\n', ...
            height(UpdatedKey) - nOldUnique, outFile);
    
    else
        % No old file: write new
        writetable(SessionKey, outFile);
        fprintf('SessionKey created:\n  %s\n', outFile);
    end

% ========== local helpers ==========

function [Genotype, SubjNum] = parse_animal_id(AnimalID)
% AnimalID = "WT_633" / "FX_737" / etc.

    Genotype = "";
    SubjNum  = NaN;

    s = char(AnimalID);

    % from genotype before _
    parts = strsplit(s, {'_','-'});
    if ~isempty(parts) && ~isempty(parts{1})
        Genotype = string(parts{1});
    end

    % SubjNum
    tokens = regexp(s, '(\d+)$', 'tokens', 'once');
    if ~isempty(tokens)
        SubjNum = str2double(tokens{1});
    end
end

function DateStr = parse_date_from_tankname(TankFolderName)
% Expect tank name like "633-241229-155946"
%          or "640-241220-170818"
% Extract "241229" as yymmdd -> convert to "2024-12-29"

    DateStr = "";

    s = char(TankFolderName);
    % pattern: <anything> - yymmdd - hhmmss
    tok = regexp(s, '^[^-]+-(\d{6})-\d{6}', 'tokens', 'once');
    if isempty(tok)
        return;
    end

    yymmdd = tok{1};
    yy = str2double(yymmdd(1:2));
    mm = str2double(yymmdd(3:4));
    dd = str2double(yymmdd(5:6));

    if isnan(yy) || isnan(mm) || isnan(dd)
        return;
    end

    year = 2000 + yy;  % Assume 20xx

    DateStr = sprintf('%04d-%02d-%02d', year, mm, dd); % "2024-12-29"
end

function col = make_default_column(proto, n)
% Make a default column with the same "shape/type family" as proto.
% This is to preserve extra manual columns in old SessionKey when appending.

    if islogical(proto)
        col = false(n,1);
    elseif isnumeric(proto)
        col = NaN(n,1);
    elseif isstring(proto)
        col = strings(n,1);
    elseif iscell(proto)
        col = cell(n,1);
    elseif isdatetime(proto)
        col = NaT(n,1);
    else
        % fallback
        col = strings(n,1);
    end
end

function T = dedupe_sessionkey(T)
% Keep only the first row for each tank path.

    if isempty(T) || ~ismember('TankPath', T.Properties.VariableNames)
        return;
    end

    tankPath = strip(string(T.TankPath));
    keep = tankPath ~= "";
    T = T(keep, :);
    tankPath = tankPath(keep);

    [~, ia] = unique(tankPath, 'stable');
    T = T(sort(ia), :);
end

function T = assign_table_value(T, rowIdx, varName, newVal)
    col = T.(varName);

    if iscell(col)
        T.(varName){rowIdx} = char(string(newVal));
    elseif isstring(col)
        T.(varName)(rowIdx) = string(newVal);
    elseif ischar(col)
        T.(varName)(rowIdx,:) = char(string(newVal));
    else
        T.(varName)(rowIdx) = newVal;
    end
end
end
