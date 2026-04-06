function behav = fp_behav_core(dayofdata, trialMask)
% FP_BEHAV_CORE
%   Compute Hit / FA / Omission rates for a subset of trials
%   using Tony-style dayofdata format.

    if nargin < 2 || isempty(trialMask)
        trialMask = true(size(dayofdata,1),1);
    end

    dd = dayofdata(trialMask, :);

    if isempty(dd)
        behav = emptyResult();
        return;
    end

    % column mapping
    hitL = dd(:,2) == 1;
    hitR = dd(:,3) == 1;
    faL  = dd(:,4) == 1;
    faR  = dd(:,5) == 1;
    omL  = dd(:,6) == 1;
    omR  = dd(:,7) == 1;

    % mutually exclusive
    isHit   = hitL | hitR;
    isFA    = ~isHit & (faL | faR);
    isOmiss = ~isHit & ~isFA & (omL | omR);

    valid   = isHit | isFA | isOmiss;
    nTrials = sum(valid);

    if nTrials == 0
        behav = emptyResult();
        return;
    end

    behav = struct();
    behav.nTrials   = nTrials;
    behav.nHit      = sum(isHit(valid));
    behav.nFA       = sum(isFA(valid));
    behav.nOmiss    = sum(isOmiss(valid));

    % Here: 0–1
    behav.HitRate   = behav.nHit   / nTrials;
    behav.FARate    = behav.nFA    / nTrials;
    behav.OmissRate = behav.nOmiss / nTrials;
end

function b = emptyResult()
    b = struct('nTrials',0,'nHit',0,'nFA',0,'nOmiss',0, ...
               'HitRate',NaN,'FARate',NaN,'OmissRate',NaN);
end