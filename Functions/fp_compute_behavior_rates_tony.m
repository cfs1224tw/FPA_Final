function out = fp_compute_behavior_rates_tony(dayofdata)
% FP_COMPUTE_BEHAVIOR_RATES_TONY
%   Compute behavior performance for Tony-style dayofdata.
%
% Output struct "out":
%   .all   : all trials
%   .clean : trials with Distractor == 0  (if col 13 exists)
%   .dist  : trials with Distractor == 1  (if col 13 exists)

    % all trials
    out.all = fp_behav_core(dayofdata);

    % clean / distractor only if we have column 13
    if size(dayofdata,2) >= 13
        isClean = dayofdata(:,13) == 0;
        isDist  = dayofdata(:,13) == 1;

        out.clean = fp_behav_core(dayofdata, isClean);
        out.dist  = fp_behav_core(dayofdata, isDist);
    else
        % clean-only session: all clean, dist -> NaN
        out.clean = fp_behav_core(dayofdata);
        out.dist  = struct('nTrials',0,'nHit',0,'nFA',0,'nOmiss',0, ...
                           'HitRate',NaN,'FARate',NaN,'OmissRate',NaN);
    end
end