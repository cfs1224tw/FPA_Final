function [z_eventlocked, t] = fp_load_tdt_eventlocked(TankPath, meta)
% FP_LOAD_TDT_EVENTLOCKED
%
% Load fiber photometry data from a TDT tank and return event-locked traces.
%
% OUTPUT
%   z_eventlocked : [nTrial x nTime]
%       Continuous z-scored signal aligned to trigger events.
%
%   t : [1 x nTime]
%       Time axis in seconds relative to trigger (t = 0 is trigger onset).
%
% PROCESSING PIPELINE
%   1. Load TDT streams and epocs using TDTbin2mat
%   2. Perform 405 nm bleed-through correction using linear regression
%   3. Compute ΔF/F
%   4. Compute z-score across the entire continuous trace
%   5. Extract event-locked epochs using TDTfilter
%
% IMPORTANT
%   This function does NOT perform per-trial baseline normalization.
%   Per-trial baseline centering should be done later (e.g., using an ITI window).

%% ---------------------------------------------------------
% Parameters (can be adjusted if needed)
%% ---------------------------------------------------------

% Stream names
GRAB = 'x465A';      % signal channel
ISO  = 'x405A';      % isosbestic reference

% Trigger epoc (tone onset)
TRIG = 'PC1/';

% Event-locking window relative to trigger (seconds)
EPOC_RANGE = [-12 24];

% Remove initial segment to avoid bleaching or sync artifacts
t_discard = 5;     % seconds

% Whether to compute ΔF/F
DO_DFF = true;

%% ---------------------------------------------------------
% Sanity checks and load TDT tank
%% ---------------------------------------------------------

assert(exist('TDTbin2mat','file')==2, 'TDTbin2mat not on path.');
assert(exist('TDTfilter','file')==2, 'TDTfilter not on path.');

TankPath_char = char(TankPath);
assert(exist(TankPath_char,'dir')==7, 'TankPath missing: %s', TankPath_char);

data = TDTbin2mat(TankPath_char);

assert(isfield(data,'streams') && isfield(data.streams,GRAB), ...
       'Missing stream %s', GRAB);
assert(isfield(data.streams,ISO), ...
       'Missing stream %s', ISO);

fs465  = data.streams.(GRAB).fs;
sig465 = data.streams.(GRAB).data(:)';

fs405  = data.streams.(ISO).fs;
sig405 = data.streams.(ISO).data(:)';

t465 = (0:numel(sig465)-1)/fs465;
t405 = (0:numel(sig405)-1)/fs405;

%% ---------------------------------------------------------
% Remove early bleaching / synchronization artifacts
%% ---------------------------------------------------------

if t_discard > 0

    i465 = find(t465 >= t_discard,1,'first');
    i405 = find(t405 >= t_discard,1,'first');

    if isempty(i465) || isempty(i405)
        error('t_discard (%.2fs) exceeds recording duration', t_discard);
    end

    sig465 = sig465(i465:end);
    sig405 = sig405(i405:end);

    t465   = t465(i465:end) - t_discard;
    t405   = t405(i405:end) - t_discard;

    % Shift epoc timestamps so they remain aligned
    if isfield(data,'epocs')

        efn = fieldnames(data.epocs);

        for ii = 1:numel(efn)

            en = efn{ii};

            if isfield(data.epocs.(en),'onset')
                data.epocs.(en).onset = data.epocs.(en).onset - t_discard;
            end

            if isfield(data.epocs.(en),'offset')
                data.epocs.(en).offset = data.epocs.(en).offset - t_discard;
            end

        end
    end
end

%% ---------------------------------------------------------
% 405 nm bleed-through correction
%% ---------------------------------------------------------

L = min(numel(sig465), numel(sig405));

if L < 2
    error('Not enough samples for bleed correction (L = %d).', L);
end

% Fit linear model: 465 ≈ m * 405 + b
p = polyfit(sig405(1:L), sig465(1:L), 1);

iso_fit = polyval(p, sig405(1:L));

sig465 = sig465(1:numel(iso_fit));
t465   = t465(1:numel(iso_fit));

dF = sig465 - iso_fit;   % bleed-corrected signal

%% ---------------------------------------------------------
% Compute ΔF/F
%% ---------------------------------------------------------

if DO_DFF

    F0 = iso_fit;
    F0(F0 == 0) = 1;

    dFF = dF ./ F0;

else

    dFF = dF;

end

%% ---------------------------------------------------------
% Compute global z-score across entire trace
%% ---------------------------------------------------------

mu = mean(dFF);
sd = std(dFF);

if sd == 0
    sd = 1;
end

z_stream = (dFF - mu) / sd;

% Replace GRAB stream with z-scored signal
data.streams.(GRAB).data = z_stream(:)';
data.streams.(ISO).data  = sig405;

%% ---------------------------------------------------------
% Extract event-locked epochs
%% ---------------------------------------------------------

DE = TDTfilter(data, TRIG, 'TIME', EPOC_RANGE);

if ~isfield(DE,'streams') || ...
   ~isfield(DE.streams,GRAB) || ...
   ~isfield(DE.streams.(GRAB),'filtered') || ...
   isempty(DE.streams.(GRAB).filtered)

    error('No filtered GRAB stream found. Check TRIG/EPOC_RANGE.');

end

filtered = DE.streams.(GRAB).filtered;

%% ---------------------------------------------------------
% Remove empty trials
%% ---------------------------------------------------------

len_per_trial = cellfun(@numel, filtered);

validMask = len_per_trial > 0;

if ~any(validMask)
    error('All trials are empty after TDTfilter.');
end

if any(~validMask)
    fprintf('fp_load_tdt_eventlocked: dropping %d empty trials\n', ...
        sum(~validMask));
end

filtered      = filtered(validMask);
len_per_trial = len_per_trial(validMask);

%% ---------------------------------------------------------
% Equalize trial lengths
%% ---------------------------------------------------------

Lg = min(len_per_trial);

if Lg < 1
    error('Minimum trial length < 1 sample.');
end

filtered = cellfun(@(x) x(1:Lg), filtered, 'UniformOutput', false);

%% ---------------------------------------------------------
% Build trial × time matrix
%% ---------------------------------------------------------

Grab_stream = cell2mat(filtered');   % [nTrials x nTime]

grab_fs = DE.streams.(GRAB).fs;
nSamp   = size(Grab_stream,2);

%% ---------------------------------------------------------
% Create time axis
%% ---------------------------------------------------------

t = EPOC_RANGE(1) + (0:nSamp-1)/grab_fs;

%% ---------------------------------------------------------
% Output
%% ---------------------------------------------------------

z_eventlocked = Grab_stream;  % continuous z-scored event-locked traces

end