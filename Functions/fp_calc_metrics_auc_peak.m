function [metrics, config_out] = fp_calc_metrics_auc_peak(data, config_in)
% FP_CALC_METRICS_AUC_PEAK
%   Compute per-trial AUC and peak Z within pre-defined time windows,
%   using FPA-style area modes:
%
%   areaMode = 'positive-only' : AUC over max(z, 0)   (Response window)
%   areaMode = 'negative-only' : AUC over min(z, 0)   (Reward window)
%
%   PFC:
%       Response = [0, 2]
%       Reward   = [2, 5]
%
%   AUX:
%       Response = [0, RT_trial]
%       Reward   = [RT_trial, 5]
%       RT_trial comes from data.labels.rt (sec).
%       If RT_trial is NaN or invalid, fall back to config_in.winRanges.
%
% Inputs
%   data      .z [nTrial x nTime], .t [1 x nTime]
%             .meta.region  ('AUX' / 'PFC' / ...)
%             .labels.rt    [nTrial x 1] reaction time (sec, optional)
%
%   config_in .winNames    {nWin x 1}
%             .winRanges   [nWin x 2] (nominal windows)
%             .winAreaMode {nWin x 1} 'positive-only' / 'negative-only'
%
% Outputs
%   metrics   .AUC_trial   [nTrial x nWin]
%             .peakZ_trial [nTrial x nWin]
%   config_out same as config_in, with defaults filled in as needed

    z = data.z;
    t = data.t(:)';    % row
    [nTrial, nTime] = size(z);

    if nargin < 2 || isempty(config_in)
        config_in = struct();
    end

    % --------- window config ---------
    if ~isfield(config_in, 'winNames') || isempty(config_in.winNames) || ...
       ~isfield(config_in, 'winRanges') || isempty(config_in.winRanges)

        % Default to Response and Reward windows.
        config_out.winNames    = {'Response', 'Reward'};
        config_out.winRanges   = [0 2; 2 5];   % nominal windows; PFC uses these directly
        config_out.winAreaMode = {'positive-only','negative-only'};
    else
        config_out.winNames  = config_in.winNames;
        config_out.winRanges = config_in.winRanges;

        if isfield(config_in, 'winAreaMode') && ~isempty(config_in.winAreaMode)
            config_out.winAreaMode = config_in.winAreaMode;
        else
            nWin = numel(config_out.winNames);
            config_out.winAreaMode = cell(nWin,1);
            for w = 1:nWin
                name_w = string(config_out.winNames{w});
                if contains(lower(name_w), "rew")
                    config_out.winAreaMode{w} = 'negative-only';
                else
                    config_out.winAreaMode{w} = 'positive-only';
                end
            end
        end
    end

    winNames    = config_out.winNames;
    winRanges   = config_out.winRanges;
    winAreaMode = config_out.winAreaMode;
    nWin        = numel(winNames);

    % --------- region & RT info ---------
    region = '';
    if isfield(data, 'meta') && isfield(data.meta, 'region')
        region = strtrim(data.meta.region);
    end
    isAUX = strcmpi(region, 'AUX');
    isPFC = strcmpi(region, 'PFC'); %#ok<NASGU>  % PFC currently uses fixed windows only

    if isfield(data, 'labels') && isfield(data.labels, 'rt')
        rt_trial = data.labels.rt(:);
    else
        rt_trial = nan(nTrial,1);
    end

    % --------- allocate outputs ---------
    AUC_trial   = nan(nTrial, nWin);
    peakZ_trial = nan(nTrial, nWin);

    % --------- loop over windows & trials ---------
    for w = 1:nWin
        mode_w = lower(string(winAreaMode{w}));

        for i = 1:nTrial
            yi = z(i,:);  % [1 x nTime]

            % ----- decide window bounds for this trial -----
            if isAUX
                rt_i = NaN;
                if numel(rt_trial) >= i
                    rt_i = rt_trial(i);
                end

                if strcmp(mode_w, 'positive-only')
                    % Response: [0, RT_i]
                    if ~isnan(rt_i) && rt_i > 0
                        t1 = 0;
                        t2 = rt_i;
                    else
                        % Fall back to the nominal window when RT is unavailable.
                        t1 = winRanges(w,1);
                        t2 = winRanges(w,2);
                    end
                elseif strcmp(mode_w, 'negative-only')
                    % Reward: [RT_i, 5]
                    if ~isnan(rt_i) && rt_i > 0
                        t1 = rt_i;
                        t2 = 5;
                    else
                        t1 = winRanges(w,1);
                        t2 = winRanges(w,2);
                    end
                else
                    error('fp_calc_metrics_auc_peak:BadAreaMode', ...
                        'Unknown area mode "%s".', mode_w);
                end
            else
                % PFC and other regions use fixed windows directly.
                t1 = winRanges(w,1);
                t2 = winRanges(w,2);
            end

            % Clamp the window to the valid time range.
            t1 = max(t1, t(1));
            t2 = min(t2, t(end));

            if t2 <= t1
                continue;
            end

            mask = (t >= t1) & (t <= t2);
            if ~any(mask)
                continue;
            end

            tw = t(mask);
            yw = yi(mask);

            % ----- AUC clipping -----
            switch mode_w
                case "positive-only"
                    yw_clip = max(yw, 0);
                    % Peak is the maximum value within the window.
                    peakZ_trial(i,w) = max(yw, [], 2, 'omitnan');

                case "negative-only"
                    yw_clip = min(yw, 0);
                    % Peak is the minimum value within the window.
                    peakZ_trial(i,w) = min(yw, [], 2, 'omitnan');

                otherwise
                    error('fp_calc_metrics_auc_peak:BadAreaMode', ...
                        'Unknown area mode "%s".', mode_w);
            end

            if all(isnan(yw_clip))
                AUC_trial(i,w) = NaN;
            else
                % time spacing
                if numel(tw) > 1
                    dt = mean(diff(tw));
                else
                    dt = NaN;   % A single sample is not enough to compute AUC.
                end
            
                if isnan(dt) || dt <= 0
                    AUC_trial(i,w) = NaN;
                else
                    % For uniform sampling, trapz(t,y) = trapz(y) * dt.
                    AUC_trial(i,w) = trapz(yw_clip) * dt;
                end
            end
        end
    end

    metrics = struct();
    metrics.AUC_trial   = AUC_trial;
    metrics.peakZ_trial = peakZ_trial;
end
