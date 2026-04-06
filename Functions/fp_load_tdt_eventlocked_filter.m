function [z_eventlocked, t, out] = fp_load_tdt_eventlocked_filter(TankPath, meta, varargin)
% FP_LOAD_TDT_EVENTLOCKED
%
% Load TDT tank fiber photometry data and return event-locked traces.
%
% OUTPUT
%   z_eventlocked : [nTrial x nTime]
%       Event-locked z-scored traces.
%
%   t : [1 x nTime]
%       Time axis in seconds relative to trigger onset.
%
%   out : struct
%       Extra outputs for debugging / QC:
%           .sig465_raw
%           .sig405_raw
%           .sigsub
%           .sigfilt
%           .z_stream
%           .fitcoef
%           .fitmethod
%           .fs
%           .validMask
%           .params
%
% PIPELINE
%   1) Load TDT tank
%   2) Discard early segment
%   3) 405->465 scaling (OLS or IRLS)
%   4) Subtract reference fit
%   5) Optional dF/F
%   6) Optional PASTa-style filtering on corrected signal
%   7) Global z-score
%   8) Event-lock with TDTfilter
%
% NOTES
%   - This function does NOT do per-trial baseline normalization.
%   - If you want ITI baseline centering, do it later after epoch extraction.

%% ---------------------------------------------------------
% Input parser
%% ---------------------------------------------------------
p = inputParser;

addParameter(p, 'GRAB', 'x465A', @(x)ischar(x)||isstring(x));
addParameter(p, 'ISO',  'x405A', @(x)ischar(x)||isstring(x));
addParameter(p, 'TRIG', 'PC1/',  @(x)ischar(x)||isstring(x));

addParameter(p, 'EPOC_RANGE', [-12 24], @(x)isnumeric(x)&&numel(x)==2);
addParameter(p, 't_discard', 5, @(x)isnumeric(x)&&isscalar(x)&&x>=0);

addParameter(p, 'DoDFF', true, @islogical);

% scaling / fitting
addParameter(p, 'BaqScalingType', 'OLS', @(x)ischar(x)||isstring(x)); % 'OLS' or 'IRLS'

% filter options (PASTa-like)
addParameter(p, 'FilterType', 'nofilter', @(x)ischar(x)||isstring(x)); % 'nofilter','lowpass','highpass','bandpass'
addParameter(p, 'FilterOrder', 3, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
addParameter(p, 'LowpassCutoff', 2.2860, @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p, 'HighpassCutoff', 0.0051, @(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p, 'Padding', true, @islogical);
addParameter(p, 'PaddingPerc', 0.1, @(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<0.5);

parse(p, varargin{:});
params = p.Results;

GRAB = char(params.GRAB);
ISO  = char(params.ISO);
TRIG = char(params.TRIG);

EPOC_RANGE = params.EPOC_RANGE;
t_discard  = params.t_discard;
DO_DFF     = params.DoDFF;

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
sig465 = double(data.streams.(GRAB).data(:)');

fs405  = data.streams.(ISO).fs;
sig405 = double(data.streams.(ISO).data(:)');

t465 = (0:numel(sig465)-1)/fs465;
t405 = (0:numel(sig405)-1)/fs405;

%% ---------------------------------------------------------
% Remove early bleaching / sync artifact segment
%% ---------------------------------------------------------
if t_discard > 0
    i465 = find(t465 >= t_discard, 1, 'first');
    i405 = find(t405 >= t_discard, 1, 'first');

    if isempty(i465) || isempty(i405)
        error('t_discard (%.2f s) exceeds recording duration.', t_discard);
    end

    sig465 = sig465(i465:end);
    sig405 = sig405(i405:end);

    t465 = t465(i465:end) - t_discard;
    t405 = t405(i405:end) - t_discard;

    % shift epoc timestamps
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
% Match lengths
%% ---------------------------------------------------------
L = min(numel(sig465), numel(sig405));
if L < 2
    error('Not enough samples after trimming.');
end

sig465 = sig465(1:L);
sig405 = sig405(1:L);
t465   = t465(1:L);

%% ---------------------------------------------------------
% 405 -> 465 scaling (OLS or IRLS)
%% ---------------------------------------------------------
switch upper(string(params.BaqScalingType))
    case "OLS"
        fitcoef = polyfit(sig405, sig465, 1);   % [m b]
        iso_fit = polyval(fitcoef, sig405);

    case "IRLS"
        mdl = fitlm(sig405(:), sig465(:), 'linear', 'RobustOpts', 'on');
        c = mdl.Coefficients.Estimate;          % [intercept; slope]
        fitcoef = [c(2), c(1)];                 % convert to [m b]
        iso_fit = predict(mdl, sig405(:))';
        
    otherwise
        error('Unknown BaqScalingType: %s. Use ''OLS'' or ''IRLS''.', ...
            char(params.BaqScalingType));
end

sigsub = sig465 - iso_fit;

%% ---------------------------------------------------------
% Compute dF/F or keep dF
%% ---------------------------------------------------------
if DO_DFF
    F0 = iso_fit;
    F0(F0 == 0) = 1;
    proc = sigsub ./ F0;
else
    proc = sigsub;
end

%% ---------------------------------------------------------
% Prepare filters (PASTa-like)
%% ---------------------------------------------------------
fs = fs465;
nyquist = fs / 2;

filterType = lower(string(params.FilterType));

switch filterType
    case "bandpass"
        highpasscutoffval = round(params.HighpassCutoff / nyquist, 6);
        lowpasscutoffval  = round(params.LowpassCutoff  / nyquist, 6);

        assert(highpasscutoffval > 0 && highpasscutoffval < 1, ...
            'Invalid HighpassCutoff.');
        assert(lowpasscutoffval > 0 && lowpasscutoffval < 1, ...
            'Invalid LowpassCutoff.');
        assert(highpasscutoffval < lowpasscutoffval, ...
            'Need HighpassCutoff < LowpassCutoff.');

        [b_high, a_high] = butter(params.FilterOrder, highpasscutoffval, 'high');
        [b_low,  a_low ] = butter(params.FilterOrder, lowpasscutoffval,  'low');

    case "highpass"
        highpasscutoffval = round(params.HighpassCutoff / nyquist, 6);

        assert(highpasscutoffval > 0 && highpasscutoffval < 1, ...
            'Invalid HighpassCutoff.');

        [b_high, a_high] = butter(params.FilterOrder, highpasscutoffval, 'high');

    case "lowpass"
        lowpasscutoffval = round(params.LowpassCutoff / nyquist, 6);

        assert(lowpasscutoffval > 0 && lowpasscutoffval < 1, ...
            'Invalid LowpassCutoff.');

        [b_low, a_low] = butter(params.FilterOrder, lowpasscutoffval, 'low');

    case "nofilter"
        % nothing

    otherwise
        error('FilterType "%s" not recognized.', char(params.FilterType));
end

%% ---------------------------------------------------------
% Filter corrected signal (PASTa-like)
%% ---------------------------------------------------------
if filterType ~= "nofilter"
    sigfilt_in = proc;

    if params.Padding
        nsamplesedge = floor(length(sigfilt_in) * params.PaddingPerc);
        nsamplesedge = max(nsamplesedge, 1);

        firstsamples = fliplr(sigfilt_in(1:nsamplesedge));
        lastsamples  = fliplr(sigfilt_in(end-nsamplesedge+1:end));
        sigfilt_in   = [firstsamples, sigfilt_in, lastsamples];
    end

    switch filterType
        case "bandpass"
            sigfilt = filtfilt(b_high, a_high, sigfilt_in);
            sigfilt = filtfilt(b_low,  a_low,  sigfilt);

        case "highpass"
            sigfilt = filtfilt(b_high, a_high, sigfilt_in);

        case "lowpass"
            sigfilt = filtfilt(b_low, a_low, sigfilt_in);

        otherwise
            sigfilt = sigfilt_in;
    end

    if params.Padding
        sigfilt = sigfilt(nsamplesedge+1:end-nsamplesedge);
    end
else
    sigfilt = proc;
end

%% ---------------------------------------------------------
% Global z-score across entire filtered corrected trace
%% ---------------------------------------------------------
mu = mean(sigfilt, 'omitnan');
sd = std(sigfilt, 0, 'omitnan');

if sd == 0 || isnan(sd)
    sd = 1;
end

z_stream = (sigfilt - mu) / sd;

%% ---------------------------------------------------------
% Put processed stream back into TDT struct
%% ---------------------------------------------------------
data.streams.(GRAB).data = z_stream(:)';
data.streams.(GRAB).fs   = fs465;

% keep original 405 stream in case needed
data.streams.(ISO).data = sig405(:)';
data.streams.(ISO).fs   = fs405;

%% ---------------------------------------------------------
% Extract event-locked epochs
%% ---------------------------------------------------------
DE = TDTfilter(data, TRIG, 'TIME', EPOC_RANGE);

if ~isfield(DE,'streams') || ...
   ~isfield(DE.streams,GRAB) || ...
   ~isfield(DE.streams.(GRAB),'filtered') || ...
   isempty(DE.streams.(GRAB).filtered)
    error('No filtered GRAB stream found. Check TRIG / EPOC_RANGE.');
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
    fprintf('fp_load_tdt_eventlocked: dropping %d empty trials\n', sum(~validMask));
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
% Build trial x time matrix
%% ---------------------------------------------------------
z_eventlocked = cell2mat(filtered');   % [nTrial x nTime]

grab_fs = DE.streams.(GRAB).fs;
nSamp   = size(z_eventlocked, 2);

%% ---------------------------------------------------------
% Create time axis
%% ---------------------------------------------------------
t = EPOC_RANGE(1) + (0:nSamp-1)/grab_fs;

%% ---------------------------------------------------------
% Optional extra output
%% ---------------------------------------------------------
out = struct();
out.sig465_raw = sig465;
out.sig405_raw = sig405;
out.iso_fit    = iso_fit;
out.sigsub     = sigsub;
out.sigfilt    = sigfilt;
out.z_stream   = z_stream;
out.fitcoef    = fitcoef;
out.fitmethod  = string(params.BaqScalingType);
out.fs         = fs465;
out.validMask  = validMask;
out.params     = params;

if nargin >= 2 && ~isempty(meta)
    out.meta = meta;
end

end