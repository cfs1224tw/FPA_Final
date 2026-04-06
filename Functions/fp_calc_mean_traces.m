function [meanTrace, semTrace] = fp_calc_mean_traces(data, cfg)
% FP_CALC_MEAN_TRACES
%   Compute mean ± SEM PSTH-style traces for one session.
%
%   Does:
%     - optional per-trial baseline-centering (single rule)
%     - mean±SEM for:
%         * condition-level traces (PureClean, Clean_in_Aud50, ...)
%         * tone-level traces (7-tone)
%         * octave-level traces
%
%   Does NOT:
%     - permutation
%     - bootstrap
%     - window metrics (AUC/Peak)
%
% Inputs
%   data  struct (see fp_build_session_data)
%   cfg   struct with optional field:
%         .baselineWin  [t1 t2] baseline window (sec) for per-trial centering
%
% Outputs
%   meanTrace struct:
%       .conditions.(condName).mean   [1 x nTime]
%       .tones.(condName).mean        [nTone x nTime]
%       .octaves.(condName).mean      [nOct x nTime]
%       .t                            [1 x nTime]
%
%   semTrace  struct with same fields but "sem" instead of "mean".

    % --------- basic inputs ----------
    if ~isfield(data,'z') || ~isfield(data,'t')
        error('fp_calc_mean_traces: data.z and data.t are required.');
    end

    z      = data.z;        % [nTrial x nTime]
    t      = data.t;        % [1 x nTime]
    labels = data.labels;
    [nTrial, nTime] = size(z); %#ok<NASGU>

    if nargin < 2
        cfg = struct();
    end

    % ---------- optional baseline centering ----------
    if isfield(cfg, 'baselineWin') && ~isempty(cfg.baselineWin)
        bw = cfg.baselineWin;  % [t1 t2] in sec
        idxBase = t >= bw(1) & t <= bw(2);
        if ~any(idxBase)
            warning('fp_calc_mean_traces:NoBaselineIdx', ...
                'Baseline window [%.3f %.3f] contains no time points. Skipping centering.', ...
                bw(1), bw(2));
        else
            baseMean = mean(z(:, idxBase), 2, 'omitnan');  % [nTrial x 1]
            z = z - baseMean;
        end
    end

    % ---------- convert label fields to string for safe compare ----------
    trial_role    = get_label_as_string(labels, 'trial_role');
    distractorMod = get_label_as_string(labels, 'distractor_modality');
    cleanContext  = get_label_as_string(labels, 'clean_context');

    % tone & octave
    [tone_id, uTone]     = get_label_as_numeric(labels, 'tone_id');
    [octave_id, uOctave] = get_label_as_numeric(labels, 'octave_id');

    % ---------- define condition categories ----------
    condNames = {'PureClean', 'Clean_in_Aud50', 'Clean_in_Vis50', ...
                 'AudDistr', 'VisDistr'};

    condMasks = struct();
    condMasks.PureClean      = (cleanContext == "PureClean");
    condMasks.Clean_in_Aud50 = (cleanContext == "Clean_in_Aud50");
    condMasks.Clean_in_Vis50 = (cleanContext == "Clean_in_Vis50");
    condMasks.AudDistr       = (trial_role == "Distractor") & (distractorMod == "Aud");
    condMasks.VisDistr       = (trial_role == "Distractor") & (distractorMod == "Vis");

    % ---------- allocate output ----------
    meanTrace = struct();
    semTrace  = struct();

    meanTrace.conditions = struct();
    semTrace.conditions  = struct();

    meanTrace.tones   = struct();
    semTrace.tones    = struct();

    meanTrace.octaves = struct();
    semTrace.octaves  = struct();

    % ---------- condition-level PSTH ----------
    for c = 1:numel(condNames)
        cname = condNames{c};
        mask  = condMasks.(cname);
        idx   = find(mask);

        if isempty(idx)
            meanTrace.conditions.(cname).mean = nan(1, nTime);
            semTrace.conditions.(cname).sem   = nan(1, nTime);
            continue;
        end

        Zc = z(idx, :);  % [nTrial_c x nTime]
        meanTrace.conditions.(cname).mean = mean(Zc, 1, 'omitnan');
        semTrace.conditions.(cname).sem   = std(Zc, 0, 1, 'omitnan') ./ sqrt(size(Zc,1));
    end

    % ---------- tone-level PSTH ----------
    if ~isempty(uTone)
        for c = 1:numel(condNames)
            cname    = condNames{c};
            condMask = condMasks.(cname);

            mt = nan(numel(uTone), nTime);
            st = nan(numel(uTone), nTime);

            if ~any(condMask)
                meanTrace.tones.(cname).mean      = mt;
                semTrace.tones.(cname).sem        = st;
                meanTrace.tones.(cname).tone_list = uTone;
                continue;
            end

            for k = 1:numel(uTone)
                toneMask = (tone_id == uTone(k));
                idx      = find(condMask & toneMask);

                if isempty(idx)
                    mt(k,:) = nan(1, nTime);
                    st(k,:) = nan(1, nTime);
                    continue;
                end

                Ztk = z(idx, :);
                mt(k,:) = mean(Ztk, 1, 'omitnan');
                st(k,:) = std(Ztk, 0, 1, 'omitnan') ./ sqrt(size(Ztk,1));
            end

            meanTrace.tones.(cname).mean      = mt;
            semTrace.tones.(cname).sem        = st;
            meanTrace.tones.(cname).tone_list = uTone;
        end
    end

    % ---------- octave-level PSTH ----------
    if ~isempty(uOctave)
        for c = 1:numel(condNames)
            cname    = condNames{c};
            condMask = condMasks.(cname);

            mo = nan(numel(uOctave), nTime);
            so = nan(numel(uOctave), nTime);

            if ~any(condMask)
                meanTrace.octaves.(cname).mean       = mo;
                semTrace.octaves.(cname).sem         = so;
                meanTrace.octaves.(cname).oct_list   = uOctave;
                continue;
            end

            for k = 1:numel(uOctave)
                octMask = (octave_id == uOctave(k));
                idx     = find(condMask & octMask);

                if isempty(idx)
                    mo(k,:) = nan(1, nTime);
                    so(k,:) = nan(1, nTime);
                    continue;
                end

                Zok = z(idx, :);
                mo(k,:) = mean(Zok, 1, 'omitnan');
                so(k,:) = std(Zok, 0, 1, 'omitnan') ./ sqrt(size(Zok,1));
            end

            meanTrace.octaves.(cname).mean      = mo;
            semTrace.octaves.(cname).sem        = so;
            meanTrace.octaves.(cname).oct_list  = uOctave;
        end
    end

    % time vector
    meanTrace.t = t;
    semTrace.t  = t;
end

% ---- local helpers ----
function s = get_label_as_string(labels, fieldName)
    if ~isfield(labels, fieldName) || isempty(labels.(fieldName))
        s = strings(0,1);
        return;
    end
    val = labels.(fieldName);
    if isstring(val)
        s = val(:);
    elseif iscellstr(val) || iscell(val)
        s = string(val(:));
    else
        % numeric -> convert to string
        s = string(val(:));
    end
end

function [x, u] = get_label_as_numeric(labels, fieldName)
    if ~isfield(labels, fieldName) || isempty(labels.(fieldName))
        x = [];
        u = [];
        return;
    end
    val = labels.(fieldName);
    x = double(val(:));        % enforce numeric
    u = unique(x(~isnan(x)));
end