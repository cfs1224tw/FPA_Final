function fp_plot_behav_longitudinal_batch(rootMaybe, outDir)
% FP_PLOT_BEHAV_LONGITUDINAL_BATCH
%   Accept either:
%     (A) root7TS3 folder directly (contains animal folders 633, 634, ...)
%     (B) a higher folder that contains a subfolder named "7TS3"
%
% Usage:
%   fp_plot_behav_longitudinal_batch('/.../Extracted mFile Data', '/.../out');
%   fp_plot_behav_longitudinal_batch('/.../Extracted mFile Data/7TS3', '/.../out');

    if nargin < 2 || isempty(outDir)
        outDir = fullfile(rootMaybe, '_beh_longitudinal_figs');
    end
    if ~exist(outDir,'dir'), mkdir(outDir); end

    rootMaybe = string(rootMaybe);

    % ---- auto-resolve root7TS3 ----
    root7TS3 = rootMaybe;
    if ~isfolder(root7TS3)
        error('Folder not found: %s', rootMaybe);
    end

    % if this folder doesn't look like it contains animal folders, try /7TS3
    if ~looksLikeAnimalRoot(root7TS3)
        cand = fullfile(root7TS3, '7TS3');
        if isfolder(cand) && looksLikeAnimalRoot(cand)
            root7TS3 = cand;
        end
    end

    if ~looksLikeAnimalRoot(root7TS3)
        error('Cannot find animal folders under: %s (or %s/7TS3)', rootMaybe, rootMaybe);
    end

    % ---- list animal folders ----
    d = dir(root7TS3);
    d = d([d.isdir]);
    names = string({d.name});
    names = names(~ismember(names, [".",".."]));

    isAnimal = ~cellfun(@isempty, regexp(cellstr(names), '^\d+$', 'once'));
    animalFolders = names(isAnimal);

    for i = 1:numel(animalFolders)
        animalID   = animalFolders(i);
        animalPath = fullfile(root7TS3, animalID);

        try
            savePath = fullfile(outDir, sprintf('Beh_Longitudinal_Subj%s.png', animalID));
            fp_plot_behav_longitudinal_one(animalPath, 'SavePath', savePath, ...
                'Title', "Behavior (ALL) - Subj " + animalID);
            close(gcf);
        catch ME
            warning('Skip %s: %s', animalID, ME.message);
        end
    end

    fprintf('Done. Figures saved to: %s\n', outDir);
end

function tf = looksLikeAnimalRoot(pth)
    d = dir(pth);
    d = d([d.isdir]);
    names = string({d.name});
    names = names(~ismember(names, [".",".."]));
    tf = any(~cellfun(@isempty, regexp(cellstr(names), '^\d+$', 'once')));
end