function [hitFA, hitFA_sem] = fp_calc_mean_traces_hitFA(data, cfg)
% FP_CALC_MEAN_TRACES_HITFA
%   Compute mean ± SEM PSTH traces for:
%       - All trials
%       - Hit  trials only
%       - FA   trials only
%
% Inputs
%   data.z   [nTrial x nTime] event-locked z
%   data.t   [1 x nTime]
%   data.labels.hitFA   string array ("Hit","FA","Omission","Other")
%
%   cfg.baselineWin  [t1 t2]  (optional) per-trial baseline-centering window
%
% Outputs
%   hitFA: struct with fields
%       .all.mean   [1 x nTime]
%       .hit.mean   [1 x nTime]
%       .fa.mean    [1 x nTime]
%       .t          [1 x nTime]
%
%   hitFA_sem: same fields but "sem"

    if ~isfield(data,'z') || ~isfield(data,'t')
        error('fp_calc_mean_traces_hitFA: data.z and data.t are required.');
    end

    z = data.z;
    t = data.t;
    [nTrial, nTime] = size(z);

    if nargin < 2
        cfg = struct();
    end

    % ---------- baseline centering (optional) ----------
    if isfield(cfg,'baselineWin') && ~isempty(cfg.baselineWin)
        bw = cfg.baselineWin;      % [t1 t2] in sec
        idxBase = t >= bw(1) & t <= bw(2);
        if ~any(idxBase)
            warning('fp_calc_mean_traces_hitFA:NoBaselineIdx', ...
                'Baseline window [%.3f %.3f] contains no time points. Skipping centering.', ...
                bw(1), bw(2));
        else
            baseMean = mean(z(:, idxBase), 2, 'omitnan');   % [nTrial x 1]
            z = z - baseMean;
        end
    end

    % ---------- outcome labels from labels.hitFA ----------
    if ~isfield(data,'labels') || ~isfield(data.labels,'hitFA')
        error('fp_calc_mean_traces_hitFA: labels.hitFA is required.');
    end

    outcome = data.labels.hitFA;
    if ~isstring(outcome)
        outcome = string(outcome);
    end
    outcome = outcome(:);   % [nTrial x 1]

    % ---------- trial masks ----------
    mask_all = true(nTrial,1);
    mask_hit = (outcome == "Hit");
    mask_fa  = (outcome == "FA");

    % ---------- helper ----------
    function [m,s] = calc_mean_sem(Z)
        if isempty(Z)
            m = nan(1, nTime);
            s = nan(1, nTime);
        else
            m = mean(Z, 1, 'omitnan');
            s = std(Z, 0, 1, 'omitnan') ./ sqrt(size(Z,1));
        end
    end

    % ---------- compute ----------
    [mean_all, sem_all] = calc_mean_sem(z(mask_all,:));
    [mean_hit, sem_hit] = calc_mean_sem(z(mask_hit,:));
    [mean_fa,  sem_fa ] = calc_mean_sem(z(mask_fa ,:));

    % ---------- pack outputs ----------
    hitFA = struct();
    hitFA_sem = struct();

    hitFA.all.mean = mean_all;
    hitFA.hit.mean = mean_hit;
    hitFA.fa.mean  = mean_fa;
    hitFA.t        = t;

    hitFA_sem.all.sem = sem_all;
    hitFA_sem.hit.sem = sem_hit;
    hitFA_sem.fa.sem  = sem_fa;
    hitFA_sem.t       = t;
end