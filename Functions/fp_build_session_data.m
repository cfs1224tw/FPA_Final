function data = fp_build_session_data(z_eventlocked, t, meta, labels)
% FP_BUILD_SESSION_DATA
%   Wrap event-locked z + time + labels + meta into one "data" struct
%   for fp_analyze_session, with safe trial-number mismatch handling.
%
% Inputs
%   z_eventlocked : [nTrial x nTime] baseline-uncentered z or dF/F
%   t             : [1 x nTime] time vector (sec)
%   meta          : struct with fields (ID, genotype, region, block_type…)
%   labels        : struct from fp_build_labels_from_dayofdata
%
% Output
%   data.z      [nTrial_use x nTime]
%   data.t      [1 x nTime]
%   data.labels (cropped to nTrial_use)
%   data.meta

    if nargin < 3 || isempty(meta)
        meta = struct();
    end
    if nargin < 4 || isempty(labels)
        labels = struct();
    end

    [nTrial_z, nTime] = size(z_eventlocked);

    % ---- decide "nTrial_labels" from the first 1D field in labels ----
    labelFields = fieldnames(labels);
    nTrial_lab = nTrial_z;   % default

    for k = 1:numel(labelFields)
        v = labels.(labelFields{k});
        if isvector(v) && ~isempty(v)
            nTrial_lab = numel(v);
            break;
        elseif ismatrix(v) && ~isempty(v)
            nTrial_lab = size(v,1);
            break;
        end
    end

    % ---- resolve mismatch (truncate to min) ----
    if nTrial_lab ~= nTrial_z
        nKeep = min(nTrial_lab, nTrial_z);
        warning('fp_build_session_data:TrialMismatch', ...
            'z_eventlocked has %d trials, labels have %d. Truncating to %d.', ...
            nTrial_z, nTrial_lab, nKeep);

        % crop z
        z_eventlocked = z_eventlocked(1:nKeep, :);

        % crop each label field along the row/trial dimension
        for k = 1:numel(labelFields)
            v = labels.(labelFields{k});
            if isvector(v) && numel(v) >= nKeep
                labels.(labelFields{k}) = v(1:nKeep);
            elseif ismatrix(v) && size(v,1) >= nKeep
                labels.(labelFields{k}) = v(1:nKeep, :);
            end
        end
    end

    % ---- assemble data struct ----
    data = struct();
    data.z      = z_eventlocked;
    data.t      = t(:)';   % ensure a row vector
    data.labels = labels;
    data.meta   = meta;
end
