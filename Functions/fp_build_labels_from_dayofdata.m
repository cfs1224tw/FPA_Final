function labels = fp_build_labels_from_dayofdata(dayofdata, block_type)
% FP_BUILD_LABELS_FROM_DAYOFDATA
%   Convert behavior "dayofdata" + block_type into standardized
%   trial-level labels for the FP analysis.
%
% dayofdata columns (1-based):
%   1: Tone
%   2: Hit left
%   3: Hit right
%   4: False alarm left
%   5: False alarm right
%   6: Omission left
%   7: Omission right
%   8: ITI(s)
%   9: Latency hit left
%  10: Latency false alarm left
%  11: Latency hit right
%  12: Latency false alarm right
%  13: Distractor (only 50% blocks; CleanOnly may not have col 13)

    nTrial = size(dayofdata, 1);
    nCol   = size(dayofdata, 2);

    % ---------- tone ----------
    tone_id_raw = dayofdata(:,1);          % 'Tone'
    tone_id     = double(tone_id_raw(:));

    % ---------- Hit / FA / Omission flags ----------
    % Use scalar check on nCol, then element-wise ~= 0
    hitL = false(nTrial,1);
    hitR = false(nTrial,1);
    faL  = false(nTrial,1);
    faR  = false(nTrial,1);
    omL  = false(nTrial,1);
    omR  = false(nTrial,1);

    if nCol >= 2,  hitL = dayofdata(:,2) ~= 0;  end  % Hit left
    if nCol >= 3,  hitR = dayofdata(:,3) ~= 0;  end  % Hit right
    if nCol >= 4,  faL  = dayofdata(:,4) ~= 0;  end  % FA left
    if nCol >= 5,  faR  = dayofdata(:,5) ~= 0;  end  % FA right
    if nCol >= 6,  omL  = dayofdata(:,6) ~= 0;  end  % Omission left
    if nCol >= 7,  omR  = dayofdata(:,7) ~= 0;  end  % Omission right

    hit_flag      = hitL | hitR;
    fa_flag       = faL  | faR;
    omission_flag = omL  | omR;

    % ---------- hitFA label ----------
    hitFA = strings(nTrial, 1);
    hitFA(:) = "Other";

    hitFA(hit_flag)                              = "Hit";
    hitFA(~hit_flag & fa_flag)                   = "FA";
    hitFA(~hit_flag & ~fa_flag & omission_flag)  = "Omission";
    % rest stay "Other"

    % ---------- distractor flag ----------
    distr_flag = false(nTrial,1);

    if nCol >= 13
        % Distractor column: assume 0 = no distractor, non-zero = distractor
        distr_flag = dayofdata(:,13) ~= 0;
    end

    % CleanOnly block should conceptually have no distractor
    if strcmpi(block_type, 'CleanOnly')
        distr_flag(:) = false;
    end

    % ---------- trial_role & distractor_modality ----------
    trial_role   = strings(nTrial, 1);
    distr_mod    = strings(nTrial, 1);

    isDistr = distr_flag;

    trial_role(~isDistr) = "Clean";
    trial_role(isDistr)  = "Distractor";

    distr_mod(~isDistr) = "None";

    % modality determined by block_type for 50% blocks
    isAudBlock = strcmpi(block_type, 'Aud50');
    isVisBlock = strcmpi(block_type, 'Vis50');

    distr_mod(isDistr & isAudBlock) = "Aud";
    distr_mod(isDistr & isVisBlock) = "Vis";

    unknownMask = isDistr & ~(isAudBlock | isVisBlock);
    distr_mod(unknownMask) = "None";

    % ---------- clean_context ----------
    clean_context = strings(nTrial, 1);
    clean_context(:) = "";

    isClean = (trial_role == "Clean");

    if strcmpi(block_type, 'CleanOnly')
        clean_context(isClean) = "PureClean";
    elseif strcmpi(block_type, 'Aud50')
        clean_context(isClean) = "Clean_in_Aud50";
    elseif strcmpi(block_type, 'Vis50')
        clean_context(isClean) = "Clean_in_Vis50";
    end

    % Distractor trials have no clean_context
    clean_context(trial_role == "Distractor") = "";

    % ---------- octave mapping ----------
    octave_id = map_tone_to_octave(tone_id);
    % ---------- reaction time (sec) ----------
    % Use the smallest positive latency across columns as the trial RT.
    rt = nan(nTrial,1);
    if nCol >= 9
        lat_hitL = dayofdata(:,9);
        lat_faL  = nan(nTrial,1);
        lat_hitR = nan(nTrial,1);
        lat_faR  = nan(nTrial,1);

        if nCol >= 10, lat_faL  = dayofdata(:,10); end
        if nCol >= 11, lat_hitR = dayofdata(:,11); end
        if nCol >= 12, lat_faR  = dayofdata(:,12); end

        lat_all = [lat_hitL, lat_faL, lat_hitR, lat_faR];
        lat_all(lat_all <= 0) = NaN;   % treat <= 0 as no response

        rt = min(lat_all, [], 2, 'omitnan');  % trial-wise RT in sec
    end

    % ---------- assemble labels ----------
    labels = struct();
    labels.tone_id             = tone_id;
    labels.octave_id           = octave_id;
    labels.trial_role          = trial_role;
    labels.distractor_modality = distr_mod;
    labels.clean_context       = clean_context;
    labels.hitFA               = hitFA;
    labels.rt                  = rt;   % used to define AUX AUC/peak windows
end

function octave_id = map_tone_to_octave(tone_id)
% MAP_TONE_TO_OCTAVE
%   Example mapping: tones 1–2 = octave 1, 3–5 = octave 2, 6–7 = octave 3.
%   Modify to match your real paradigm if different.

    octave_id = nan(size(tone_id));
    octave_id(ismember(tone_id, [1 2])) = 1;
    octave_id(ismember(tone_id, [3 4 5])) = 2;
    octave_id(ismember(tone_id, [6 7]))   = 3;
end
