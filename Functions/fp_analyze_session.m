function sub = fp_analyze_session(data, cfg)
% FP_ANALYZE_SESSION
%   Per-session analysis for fiber photometry.
%
%   Input:
%     data.z       : [nTrial x nTime]  event-locked z (continuous -> PSTH)
%     data.t       : [1 x nTime]       time vector (sec)
%     data.labels  : struct from fp_build_labels_from_dayofdata
%     data.meta    : struct (ID, genotype, region, block_type, ...)
%
%   cfg.baselineWin : [t1 t2]  (sec) for per-trial baseline centering
%   cfg.winNames    : cellstr, e.g. {'Response','Reward'}
%   cfg.winRanges   : [nWin x 2] time windows (sec)
%   cfg.winAreaMode : cellstr, e.g. {'positive-only','negative-only'}
%
%   Output (sub struct):
%     sub.meta      : same as data.meta
%     sub.cfg       : cfg used
%     sub.time.t    : time vector
%
%     sub.traces.<Outcome>.mean  : [1 x nTime] baseline-centered mean trace
%     sub.traces.<Outcome>.sem   : [1 x nTime]
%        Outcome = 'All', 'Hit', 'FA'
%
%     sub.metrics.<Outcome>.AUC_mean   : [nWin x 1]
%     sub.metrics.<Outcome>.Peak_mean  : [nWin x 1]
%     sub.metrics.<Outcome>.N          : scalar (#trials used)
%
%     Raw trial-level fields:
%     sub.raw.z_trials   : [nTrial x nTime] baseline-centered z
%                          (same data used to compute traces)
%     sub.raw.t          : [1 x nTime]
%     sub.labels         : labels struct (trial_role, hitFA, clean_context, ...)
%
%   For future GUI filtering such as:
%   Aud50_clean / Aud50_distractor / Vis50_clean / Vis50_distractor,
%   use sub.raw.z_trials + sub.labels to split trials on the fly.

    % ---------------- 0) Basic extraction ----------------
    Z = data.z;          % [nTrial x nTime]
    t = data.t(:)';      % row vector
    L = data.labels;
    meta = data.meta;

    [nTrial, nTime] = size(Z);

    if numel(t) ~= nTime
        error('fp_analyze_session:TimeLengthMismatch', ...
            'Length(t)=%d but size(Z,2)=%d.', numel(t), nTime);
    end

    % ---------------- 1) Per-trial baseline centering ----------------
    if isfield(cfg, 'baselineWin') && ~isempty(cfg.baselineWin)
        bw = cfg.baselineWin;   % [t1 t2]
        idxBase = (t >= bw(1)) & (t <= bw(2));
        if ~any(idxBase)
            warning('fp_analyze_session:NoBaselineIdx', ...
                'Baseline window [%.3f %.3f] contains no samples. Skipping baseline centering.', ...
                bw(1), bw(2));
            Zc = Z;
        else
            baseMean = mean(Z(:, idxBase), 2, 'omitnan');  % [nTrial x 1]
            Zc = Z - baseMean;                             % implicit expansion
        end
    else
        Zc = Z;
    end

    % ---------------- 2) Outcome masks: All / Hit / FA ----------------
    maskAll = true(nTrial,1);

    hitFA = strings(nTrial,1);
    if isfield(L, 'hitFA') && ~isempty(L.hitFA)
        if isstring(L.hitFA)
            hitFA = L.hitFA(:);
        elseif iscell(L.hitFA)
            hitFA = string(L.hitFA(:));
        else
            hitFA = string(L.hitFA(:));
        end
    else
        hitFA(:) = "Other";
    end

    maskHit = (hitFA == "Hit");
    maskFA  = (hitFA == "FA");

    outcomeNames = {'All','Hit','FA'};
    outcomeMasks = {maskAll, maskHit, maskFA};

    % ---------------- 3) Window settings ----------------
    if isfield(cfg, 'winNames') && ~isempty(cfg.winNames)
        winNames = cfg.winNames;
    else
        winNames = {'Response','Reward'};
    end

    if isfield(cfg, 'winRanges') && ~isempty(cfg.winRanges)
        winRanges = cfg.winRanges;
    else
        winRanges = [0 2; 2 5];
    end

    if isfield(cfg, 'winAreaMode') && ~isempty(cfg.winAreaMode)
        winAreaMode = cfg.winAreaMode;
    else
        % Default: positive-only AUC
        winAreaMode = repmat({'positive-only'}, numel(winNames), 1);
    end

    nWin = numel(winNames);

    % ---------------- 4) Initialize output structure ----------------
    sub = struct();
    sub.meta = meta;
    sub.cfg  = cfg;

    sub.time = struct();
    sub.time.t = t;

    sub.traces  = struct();
    sub.metrics = struct();

    % Store trial-level baseline-centered z and labels
    % for later filtering (e.g., clean vs distractor)
    sub.raw = struct();
    sub.raw.z_trials = Zc;
    sub.raw.t        = t;
    sub.labels       = L;

    % ---------------- 5) Outcome loop: mean +/- SEM + AUC/Peak ----------------
    dt = mean(diff(t));  % used for AUC approximation

    for oi = 1:numel(outcomeNames)
        oname = outcomeNames{oi};
        omask = outcomeMasks{oi};

        idx = find(omask);
        if isempty(idx)
            % No trials available: fill with NaN
            sub.traces.(oname).mean = nan(1, nTime);
            sub.traces.(oname).sem  = nan(1, nTime);

            sub.metrics.(oname).AUC_mean  = nan(nWin,1);
            sub.metrics.(oname).Peak_mean = nan(nWin,1);
            sub.metrics.(oname).N         = 0;
            continue;
        end

        Zsub = Zc(idx, :);    % [nTrial_used x nTime]

        % ---- mean +/- SEM trace ----
        mTrace = mean(Zsub, 1, 'omitnan');
        sTrace = std(Zsub, 0, 1, 'omitnan') ./ sqrt(size(Zsub,1));

        sub.traces.(oname).mean = mTrace;
        sub.traces.(oname).sem  = sTrace;
        sub.traces.(oname).N    = size(Zsub,1);

        % ---- window metrics ----
        AUC_mean  = nan(nWin,1);
        Peak_mean = nan(nWin,1);

        for wi = 1:nWin
            wName  = winNames{wi};
            wRange = winRanges(wi,:);     % [t1 t2]
            mode   = winAreaMode{wi};     % 'positive-only' / 'negative-only' / 'signed'

            idxW = (t >= wRange(1)) & (t <= wRange(2));
            if ~any(idxW)
                continue;
            end

            Zwin = Zsub(:, idxW);         % [nTrial_used x nWinTime]

            % ---- peak Z ----
            switch lower(mode)
                case 'positive-only'
                    % Positive peak only
                    Zpos = max(Zwin, 0);
                    peakEach = max(Zpos, [], 2, 'omitnan');

                case 'negative-only'
                    % Negative peak only
                    Zneg = min(Zwin, 0);
                    peakEach = min(Zneg, [], 2, 'omitnan');  % more negative = larger response

                otherwise % 'signed'
                    % Magnitude of response regardless of sign
                    peakEach = max(abs(Zwin), [], 2, 'omitnan');
            end

            Peak_mean(wi) = mean(peakEach, 'omitnan');

            % ---- AUC ----
            Zauc = Zwin;
            switch lower(mode)
                case 'positive-only'
                    Zauc(Zauc < 0) = 0;
                case 'negative-only'
                    Zauc(Zauc > 0) = 0;
                otherwise
                    % signed: keep original values
            end

            aucEach = trapz(Zauc, 2) * dt;   % approximate integral of z(t) over time
            AUC_mean(wi) = mean(aucEach, 'omitnan');

            % If you want to store all trial-level values later, add:
            % sub.metrics.(oname).(wName).AUC_all  = aucEach;
            % sub.metrics.(oname).(wName).Peak_all = peakEach;
        end

        % Save summary metrics under each outcome
        sub.metrics.(oname).AUC_mean  = AUC_mean;
        sub.metrics.(oname).Peak_mean = Peak_mean;
        sub.metrics.(oname).N         = size(Zsub,1);
        sub.metrics.(oname).winNames  = winNames;
        sub.metrics.(oname).winRanges = winRanges;
    end
end