 % ==========================================================
% RUN_ALL_EARLY_LATE_TILES
%
% Batch runner for fp_plot_each_animal_early_late_tiles
%
% Runs all combinations:
%   BlockType × Genotype × Region
%
% ==========================================================

close all; clear all; clc

sessionKey = "/Users/foxking/Desktop/FP_Project/SessionKey.xlsx";
resultsDir = "/Users/foxking/Desktop/FP_Project/Results/session";
fp_run_all_sessions()
% ----------------------------------------------------------
% PARAMETERS
% ----------------------------------------------------------

blockTypes = ["CleanOnly","AudDistractorOnly", "VisDistractorOnly","Aud50","Vis50"];

genotypes = ["WT","FX"];

regions = ["AUX","PFC"];

saveFigs = true;

% ----------------------------------------------------------
% RUN LOOP
% ----------------------------------------------------------

for b = 1:length(blockTypes)

    block = blockTypes(b);

    for g = 1:length(genotypes)

        geno = genotypes(g);

        for r = 1:length(regions)

            region = regions(r);

            fprintf("\n==============================\n")
            fprintf("Block: %s | Genotype: %s | Region: %s\n",block,geno,region)
            fprintf("==============================\n")

            try

            % fp_plot_each_animal_early_late_tiles( ...
            %     sessionKey, ...
            %     resultsDir, ...
            %     geno, ...
            %     region, ...
            %     'BlockType', block, ...
            %     'EarlyN', 10, ...
            %     'UseLastNTrials', false, ...
            %     'LateRange', [200 210], ...
            %     'SaveFigs', saveFigs ...
            % );

            fp_plot_each_animal_early_late_tiles( ...
                sessionKey, ...
                resultsDir, ...
                geno, ...
                region, ...
                'BlockType', block, ...
                'EarlyN', 20, ...
                'UseLastNTrials', false, ...
                'LateRange', [190 210], ...
                'SaveFigs', saveFigs ...
            );

            catch ME

                warning("Failed: %s | %s | %s",block,geno,region)
                disp(ME.message)

            end

        end
    end
end

fprintf("\n\nAll batch plotting finished.\n")
