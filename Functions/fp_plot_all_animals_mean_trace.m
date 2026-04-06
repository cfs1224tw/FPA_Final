function fp_plot_all_animals_mean_trace(rootDir)
% FP_PLOT_ALL_ANIMALS_MEAN_TRACE
%   Plot the mean trace for each session stored in Results/session/sub_*.mat.
%
%   Rules:
%     - Prefer sub.meanTrace + sub.t when available.
%     - If meanTrace is missing but z_eventlocked + t exist, use
%           mean(z_eventlocked, 1, 'omitnan')
%     - Save one figure per session to:
%           Results/perAnimal_meanTrace/
%       Filename format:
%           meanTrace_<ID>_<Region>_<Block>.png / .fig
%
% Usage:
%   fp_plot_all_animals_mean_trace;                 % use the default rootDir
%   fp_plot_all_animals_mean_trace('/some/path');   % specify rootDir explicitly

    if nargin < 1 || isempty(rootDir)
        rootDir = fileparts(fileparts(mfilename('fullpath')));
    end

    % Collect all processed sub_*.mat files first.
    [allSubs, ~] = fp_collect_all_sub(rootDir); 

    % Output folder
    outDir = fullfile(rootDir, 'Results', 'perAnimal_meanTrace');
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    fprintf('\n==== Plotting per-animal mean traces ====\n');

    for k = 1:numel(allSubs)
        sub  = allSubs(k).sub;
        meta = allSubs(k).meta;

        % ------- 1) Load the time axis -------
        if isfield(sub, 't') && ~isempty(sub.t)
            t = sub.t(:)';   % row vector
        else
            error('sub(%d) has no field "t". Please ensure fp_analyze_session saves time axis.', k);
        end

        % ------- 2) Load the mean trace -------
        if isfield(sub, 'meanTrace') && ~isempty(sub.meanTrace)
            y = sub.meanTrace(:)';   % use the precomputed mean trace directly
        elseif isfield(sub, 'z_eventlocked') && ~isempty(sub.z_eventlocked)
            % z_eventlocked: [nTrial x T]; compute the trial-averaged trace
            y = mean(sub.z_eventlocked, 1, 'omitnan');
        else
            error(['sub(%d) has neither "meanTrace" nor "z_eventlocked". ' ...
                   'Please check fp_analyze_session output.'], k);
        end

        if numel(t) ~= numel(y)
            warning('sub(%d): length(t)=%d, length(y)=%d. Skipping.', k, numel(t), numel(y));
            continue;
        end

        % ------- 3) Prepare metadata for titles and filenames -------
        ID        = safe_meta(meta, 'ID');
        genotype  = safe_meta(meta, 'genotype');
        region    = safe_meta(meta, 'region');
        blockType = safe_meta(meta, 'block_type');

        ID_s        = sanitize_for_field(ID);
        region_s    = sanitize_for_field(region);
        blockType_s = sanitize_for_field(blockType);

        % ------- 4) Plot -------
        fig = figure('Visible', 'off');
        plot(t, y, 'LineWidth', 1.5); hold on;
        yline(0, 'k:');                % zero line
        xline(0, 'k--');               % event time

        xlabel('Time (s)');
        ylabel('z (session)');
        title(sprintf('%s | %s | %s | %s', ...
            char(ID), char(genotype), char(region), char(blockType)), ...
            'Interpreter', 'none');

        box off;
        set(gca, 'TickDir', 'out');

        % Adjust xlim/ylim here if needed.
        % xlim([min(t) max(t)]);

        % ------- 5) Save -------
        outBase = sprintf('meanTrace_%s_%s_%s', ID_s, region_s, blockType_s);
        pngPath = fullfile(outDir, [outBase '.png']);
        figPath = fullfile(outDir, [outBase '.fig']);

        saveas(fig, pngPath);
        savefig(fig, figPath);
        close(fig);

        fprintf('  [%3d/%3d] Saved %s\n', k, numel(allSubs), pngPath);
    end

    fprintf('==== Done plotting per-animal mean traces. ====\n');
end

% --------- local helpers ---------
function v = safe_meta(meta, name)
    if isfield(meta, name) && ~isempty(meta.(name))
        v = string(meta.(name));
    else
        v = "";
    end
end

function s = sanitize_for_field(x)
    s = char(string(x));
    s = strtrim(s);
    s = strrep(s, ' ', '');
    s = strrep(s, '/', '_');
    s = strrep(s, '\', '_');
    s = strrep(s, '-', '_');
    if isempty(s)
        s = 'UNK';
    end
end
