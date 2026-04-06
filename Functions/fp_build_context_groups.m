function [ctxGroups, groupNames] = fp_build_context_groups(allSubs)
% FP_BUILD_CONTEXT_GROUPS
% Build context-based groups from each session (sub).
%
% Contexts supported:
%   - CleanOnly
%   - Aud50_clean / Aud50_distractor (fallback to Aud50)
%   - Vis50_clean / Vis50_distractor (fallback to Vis50)
%   - AudDistractorOnly
%   - VisDistractorOnly
%
% Input:
%   allSubs : 1xN struct array from fp_collect_all_sub()
%
% Output:
%   ctxGroups.(key) = struct array, each element is one "session-context"
%   groupNames      = sorted cell array of keys

    ctxGroups = struct();

    for i = 1:numel(allSubs)
        sub = allSubs(i);

        % ---- Basic checks ----
        if ~isfield(sub, 'raw') || ~isfield(sub, 'labels')
            warning('fp_build_context_groups: sub(%d) missing raw/labels (skip)', i);
            continue;
        end
        if ~isfield(sub, 'meta') || isempty(sub.meta)
            sub.meta = struct();
        end

        meta   = sub.meta;
        raw    = sub.raw;
        labels = sub.labels;

        if ~isfield(raw, 'z_trials') || ~isfield(raw, 't')
            warning('fp_build_context_groups: sub(%d) missing raw.z_trials/raw.t (skip)', i);
            continue;
        end

        Z = raw.z_trials;    % [nTrial x nTime]
        t = raw.t(:)';       % row vector
        nTrial = size(Z,1);
        if nTrial == 0
            continue;
        end

        % ---- Pull genotype/region/block robustly (meta first, then sub) ----
        geno   = char(string(pick_field(meta, {'genotype','Genotype'}, sub, {'Genotype'}, "UNK")));
        region = char(string(pick_field(meta, {'region','Region'},     sub, {'Region'},   "UNK")));
        block  = char(string(pick_field(meta, {'block_type','BlockType','blockType'}, sub, {'BlockType'}, "UNK")));
        lowerBlock = lower(strtrim(block));

        % ---- Labels as string arrays ----
        trial_role = get_str_field(labels, 'trial_role',          nTrial, "");
        clean_ctx  = get_str_field(labels, 'clean_context',       nTrial, "");
        distr_mod  = get_str_field(labels, 'distractor_modality', nTrial, "None");

        % ---- Build contexts ----
        switch lowerBlock
            case 'cleanonly'
                ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'CleanOnly', true(nTrial,1));

            case 'aud50'
                maskClean = (trial_role == "Clean")      & (clean_ctx == "Clean_in_Aud50");
                maskDist  = (trial_role == "Distractor") & (distr_mod == "Aud");

                if any(maskClean)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Aud50_clean', maskClean);
                end
                if any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Aud50_distractor', maskDist);
                end
                if ~any(maskClean) && ~any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Aud50', true(nTrial,1));
                end

            case 'vis50'
                maskClean = (trial_role == "Clean")      & (clean_ctx == "Clean_in_Vis50");
                maskDist  = (trial_role == "Distractor") & (distr_mod == "Vis");

                if any(maskClean)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Vis50_clean', maskClean);
                end
                if any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Vis50_distractor', maskDist);
                end
                if ~any(maskClean) && ~any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'Vis50', true(nTrial,1));
                end

            case 'auddistractoronly'
                maskDist = (trial_role == "Distractor") & (distr_mod == "Aud");
                if any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'AudDistractorOnly', maskDist);
                else
                    % Fallback: keep group visible even if labels are incomplete
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'AudDistractorOnly', true(nTrial,1));
                end

            case 'visdistractoronly'
                maskDist = (trial_role == "Distractor") & (distr_mod == "Vis");
                if any(maskDist)
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'VisDistractorOnly', maskDist);
                else
                    ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, 'VisDistractorOnly', true(nTrial,1));
                end
        case 'distractoronly'
            % Generic "DistractorOnly" block -> split into Aud vs Vis by labels
            maskAud = (trial_role == "Distractor") & (distr_mod == "Aud");
            maskVis = (trial_role == "Distractor") & (distr_mod == "Vis");

            if any(maskAud)
                ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, ...
                                        'AudDistractorOnly', maskAud);
            end
            if any(maskVis)
                ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, ...
                                        'VisDistractorOnly', maskVis);
            end

            % Fallback: if labels are incomplete, still create *something* but DO NOT use "DistractorOnly"
            if ~any(maskAud) && ~any(maskVis)
                % If you truly can't tell modality, pick one (I default to Aud)
                ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, ...
                                        'AudDistractorOnly', true(nTrial,1));
            end

            otherwise
                ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, block, true(nTrial,1));
        end
    end

    % ---- groupNames ----
    fns = fieldnames(ctxGroups);
    if isempty(fns)
        groupNames = {};
    else
        groupNames = sort(fns);
    end
end

% ====================== subfunctions ======================

function ctxGroups = add_context(ctxGroups, geno, region, meta, labels, Z, t, nTrial, ctxName, mask)
    ctxName = char(string(ctxName));
    idx = find(mask);
    if isempty(idx)
        return;
    end

    key = sprintf('%s_%s_%s', geno, region, ctxName);
    key = safe_str(key);

    % Filter labels (only fields that match trial length)
    Lctx = labels;
    fns = fieldnames(Lctx);
    for ff = 1:numel(fns)
        fn = fns{ff};
        v  = Lctx.(fn);
        try
            if isvector(v) && numel(v) == nTrial
                Lctx.(fn) = v(idx);
            end
        catch
        end
    end

    entry = struct();
    entry.meta        = meta;
    entry.contextName = ctxName;
    entry.t           = t;
    entry.Z           = Z(idx, :);
    entry.labels      = Lctx;
    entry.NTrials     = numel(idx);

    if ~isfield(ctxGroups, key)
        ctxGroups.(key) = entry;
    else
        ctxGroups.(key)(end+1) = entry; 
    end
end

function out = pick_field(meta, metaNames, sub, subNames, defaultVal)
    out = defaultVal;

    for k = 1:numel(metaNames)
        nm = metaNames{k};
        if isfield(meta, nm) && ~isempty(meta.(nm))
            out = meta.(nm);
            return;
        end
    end

    for k = 1:numel(subNames)
        nm = subNames{k};
        if isfield(sub, nm) && ~isempty(sub.(nm))
            out = sub.(nm);
            return;
        end
    end
end

function s = get_str_field(labels, fn, nTrial, defaultVal)
    if isfield(labels, fn) && ~isempty(labels.(fn))
        v = labels.(fn);
        if isstring(v)
            s = v(:);
        elseif iscell(v)
            s = string(v(:));
        else
            s = string(v(:));
        end
        if numel(s) ~= nTrial
            s = repmat(string(defaultVal), nTrial, 1);
        end
    else
        s = repmat(string(defaultVal), nTrial, 1);
    end
end

function s = safe_str(x)
    s = char(string(x));
    s = strrep(s, ' ', '');
    s = strrep(s, '/', '-');
    s = strrep(s, '\', '-');
    s = strrep(s, ':', '-');
end