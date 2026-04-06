function [allSubs, byGroup] = fp_collect_all_sub(rootDir)
% FP_COLLECT_ALL_SUB
%   Load sub_*.mat (per-session results) filtered by SessionKey IncludeFlag,
%   then group by Genotype × Region × BlockType.
%
% Key matching strategy (IMPORTANT):
%   SessionKey uses SubjNum + Genotype. sub files store meta.ID like "WT_640" or "FX_736".
%   Therefore we match using:
%       allowKey = (Genotype_SubjNum) _ Region _ BlockType
%       thisKey  = meta.ID           _ meta.region _ meta.block_type
%
% Usage:
%   cd('/Users/foxking/Desktop/FP_Project');
%   [allSubs, byGroup] = fp_collect_all_sub;
%   [allSubs, byGroup] = fp_collect_all_sub('/some/other/path');

    if nargin < 1 || isempty(rootDir)
        rootDir = '/Users/foxking/Desktop/FP_Project';
    end

    sessDir = fullfile(rootDir, 'Results', 'session');
    if ~isfolder(sessDir)
        error('Session folder not found: %s', sessDir);
    end

    files = dir(fullfile(sessDir, 'sub_*.mat'));
    if isempty(files)
        warning('No sub_*.mat found in: %s', sessDir);
        allSubs = struct([]);
        byGroup = struct();
        return;
    end

    % ---------------- read SessionKey ----------------
    skFile = fullfile(rootDir, 'SessionKey.xlsx');
    if ~isfile(skFile)
        error('SessionKey not found: %s', skFile);
    end

    SK = readtable(skFile);

    % Require these columns (per your header)
    req = {'SubjNum','Genotype','Region','BlockType','IncludeFlag'};
    for i = 1:numel(req)
        if ~ismember(req{i}, SK.Properties.VariableNames)
            error('SessionKey missing required column: %s', req{i});
        end
    end

    % Convert IncludeFlag robustly (logical or "TRUE"/"FALSE")
    keep = normalize_bool(SK.IncludeFlag);

    SK = SK(keep, :);

    % Build allowlist key: ID_Region_BlockType
    %   ID = Genotype_SubjNum  (e.g. WT_640, FX_736)
    ID_SK = upper(string(SK.Genotype)) + "_" + string(SK.SubjNum);
    allowKey = normalize_str(ID_SK) + "_" + ...
               normalize_str(SK.Region) + "_" + ...
               normalize_str(SK.BlockType);

    % ---------------- load + filter ----------------
    requiredFields = {'meta', 'cfg', 'time', 'traces', 'metrics', 'raw', 'labels'};

    allSubs = [];
    byGroup = struct();

    fprintf('Loading sub_*.mat with IncludeFlag==TRUE ...\n');

    for k = 1:numel(files)
        fpath = fullfile(sessDir, files(k).name);
        S = load(fpath);

        if ~isfield(S, 'sub')
            continue;
        end
        s = S.sub;

        % Minimal required fields for GUI usage
        if ~isfield(s, 'meta') || ~isfield(s, 'time') || ~isfield(s, 'traces')
            continue;
        end

        m = s.meta;

        % ---- extract meta fields robustly ----
        id  = normalize_str(get_meta(m, {'ID','id'}));  % e.g. "fx_736" after normalize
        reg = normalize_str(get_meta(m, {'region','Region'}));
        blk = normalize_str(get_meta(m, {'block_type','BlockType','blocktype','block'}));

        if strlength(id)==0 || strlength(reg)==0 || strlength(blk)==0
            continue;
        end

        thisKey = id + "_" + reg + "_" + blk;

        % ---- include filter ----
        if ~ismember(thisKey, allowKey)
            continue;
        end

        % ---- pack s2 with consistent fields ----
        s2 = struct();
        for fi = 1:numel(requiredFields)
            fn = requiredFields{fi};
            if isfield(s, fn)
                s2.(fn) = s.(fn);
            else
                s2.(fn) = [];
            end
        end

        % ---- append allSubs ----
        if isempty(allSubs)
            allSubs = s2;
        else
            % sanity: keep struct fields consistent
            fnPrev = fieldnames(allSubs);
            fnNow  = fieldnames(s2);
            if ~isequal(fnPrev, fnNow)
                warning('sub in %s has different fields; skipped.', files(k).name);
                continue;
            end
            allSubs(end+1) = s2; 
        end

        % ---- grouping key: Genotype_Region_BlockType ----
        g = char(string(get_meta(m, {'genotype','Genotype'})));
        if isempty(g), g = 'UNK'; end

        key = safe_str(sprintf('%s_%s_%s', g, char(reg), char(blk)));

        if ~isfield(byGroup, key)
            byGroup.(key) = s2;
        else
            byGroup.(key)(end+1) = s2;
        end
    end

    fprintf('Loaded %d sessions into allSubs.\n', numel(allSubs));
    fprintf('Groups found (Genotype_Region_BlockType):\n');
    if isempty(fieldnames(byGroup))
        disp('<none>');
    else
        disp(fieldnames(byGroup));
    end

    % ---- debug if nothing matched ----
    if isempty(allSubs)
        fprintf('\n[DEBUG] No sessions matched allowlist.\n');
        fprintf('[DEBUG] allowKey first 10:\n');
        disp(allowKey(1:min(10,end)));

        S0 = load(fullfile(sessDir, files(1).name));
        if isfield(S0,'sub') && isfield(S0.sub,'meta')
            m0 = S0.sub.meta;
            id0  = normalize_str(get_meta(m0, {'ID','id'}));
            reg0 = normalize_str(get_meta(m0, {'region','Region'}));
            blk0 = normalize_str(get_meta(m0, {'block_type','BlockType','blocktype','block'}));
            fprintf('[DEBUG] first sub key: %s\n', string(id0 + "_" + reg0 + "_" + blk0));
            fprintf('[DEBUG] first sub meta fields:\n');
            disp(fieldnames(m0));
        end
    end
end

% ===================== helpers =====================
function out = get_meta(m, names)
    out = "";
    for i = 1:numel(names)
        f = names{i};
        if isfield(m, f) && ~isempty(m.(f))
            out = m.(f);
            return;
        end
    end
end

function v = normalize_str(x)
    v = lower(string(x));
    v = strip(v);
    v = strrep(v, " ", "");
end

function b = normalize_bool(x)
    if islogical(x)
        b = x;
        return;
    end
    s = lower(string(x));
    s = strip(s);
    b = (s=="true") | (s=="1") | (s=="yes") | (s=="y");
end

function s = safe_str(x)
    s = char(string(x));
    s = strrep(s, ' ', '');
    s = strrep(s, '/', '-');
    s = strrep(s, '\', '-');
    s = strrep(s, ':', '-');
end
