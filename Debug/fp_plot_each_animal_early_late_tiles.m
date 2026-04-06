function fp_plot_each_animal_early_late_tiles(sessionKeyPath, resultsDir, genotypeWanted, regionWanted, varargin)

% ==========================================================
% FP_PLOT_EACH_ANIMAL_EARLY_LATE_TILES  (FINAL VERSION)
%
% For each animal:
%   plot early vs late trial mean traces in a 1x2 tile layout
%
% Features
%   ✓ align signal so y=0 at t=0
%   ✓ handles NaN safely
%   ✓ publication-ready figure layout
%
% ==========================================================

p = inputParser;

p.addRequired('sessionKeyPath', @(x) ischar(x) || isstring(x));
p.addRequired('resultsDir', @(x) ischar(x) || isstring(x));
p.addRequired('genotypeWanted', @(x) ischar(x) || isstring(x));
p.addRequired('regionWanted', @(x) ischar(x) || isstring(x));

p.addParameter('BlockType',"CleanOnly");
p.addParameter('EarlyN',10);
p.addParameter('LateN',10);
p.addParameter('UseLastNTrials',true);
p.addParameter('LateRange',[200 210]);
p.addParameter('AlignAtZero',true);
p.addParameter('SaveFigs',false);
p.addParameter('OutDir',"");

p.parse(sessionKeyPath,resultsDir,genotypeWanted,regionWanted,varargin{:});
opt = p.Results;

% ==========================================================
% check paths
% ==========================================================

if ~isfile(sessionKeyPath)
    error("SessionKey not found")
end

if ~isfolder(resultsDir)
    error("Results directory not found")
end

if strlength(string(opt.OutDir)) == 0
    outDir = fullfile(resultsDir,"animal_tile_plots");
else
    outDir = char(opt.OutDir);
end

if opt.SaveFigs && ~isfolder(outDir)
    mkdir(outDir)
end

% ==========================================================
% read session key
% ==========================================================

T = readtable(sessionKeyPath);

req = {'AnimalID','Genotype','Region','BlockType','TankFolderName'};
missing = setdiff(req,T.Properties.VariableNames);

if ~isempty(missing)
    error("Missing columns: %s",strjoin(missing,", "))
end

if ismember('IncludeFlag',T.Properties.VariableNames)
    T = T(T.IncludeFlag==true,:);
end

T = T(string(T.BlockType)==string(opt.BlockType),:);
T = T(string(T.Genotype)==string(genotypeWanted),:);
T = T(string(T.Region)==string(regionWanted),:);

fprintf("Found %d matching sessions\n",height(T));

% ==========================================================
% main loop
% ==========================================================

for i = 1:height(T)

    AnimalID   = string(T.AnimalID(i));
    Genotype   = string(T.Genotype(i));
    Region     = string(T.Region(i));
    BlockType  = string(T.BlockType(i));
    TankFolder = string(T.TankFolderName(i));

    safeID     = safe_str(AnimalID);
    safeRegion = safe_str(Region);
    safeBlock  = safe_str(BlockType);
    safeTank   = safe_str(TankFolder);

    matName = sprintf("sub_%s_%s_%s_%s.mat",safeID,safeRegion,safeBlock,safeTank);
    matPath = fullfile(resultsDir,matName);

    fprintf("\n[%d/%d] %s | %s | %s\n",i,height(T),AnimalID,Region,TankFolder);

    if ~isfile(matPath)
        warning("Missing file: %s",matPath)
        continue
    end

    S = load(matPath);

    if ~isfield(S,"sub")
        warning("Missing variable 'sub'")
        continue
    end

    sub = S.sub;

    if ~isfield(sub.raw,"z_trials")
        warning("Missing z_trials")
        continue
    end

    Z = sub.raw.z_trials;
    t = sub.raw.t(:)';
    nTrial = size(Z,1);

    if nTrial < 2
        continue
    end

% ==========================================================
% alignment (y=0 at t=0)
% ==========================================================

    if opt.AlignAtZero

        [~,idx0] = min(abs(t));

        z0 = Z(:,idx0);
        Z  = Z - z0;

    end

% ==========================================================
% trial selection
% ==========================================================

    earlyIdx = 1:min(opt.EarlyN,nTrial);

    if opt.UseLastNTrials

        lateIdx = (nTrial-opt.LateN+1):nTrial;

    else

        r = opt.LateRange;
        r(1) = max(1,r(1));
        r(2) = min(nTrial,r(2));
        lateIdx = r(1):r(2);

    end

% ==========================================================
% compute stats
% ==========================================================

    Zearly = Z(earlyIdx,:);
    Zlate  = Z(lateIdx,:);

    mEarly = mean(Zearly,1,'omitnan');
    mLate  = mean(Zlate ,1,'omitnan');

    semEarly = std(Zearly,0,1,'omitnan') ./ sqrt(size(Zearly,1));
    semLate  = std(Zlate ,0,1,'omitnan') ./ sqrt(size(Zlate,1));

% ==========================================================
% figure
% ==========================================================

    f = figure( ...
        'Color','w', ...
        'Position',[100 100 1400 500], ...
        'Name',sprintf('%s_%s_%s_%s',char(AnimalID),Genotype,Region,BlockType));

    tl = tiledlayout(1,2,'TileSpacing','tight','Padding','compact');

% ==========================================================
% EARLY
% ==========================================================

    nexttile
    hold on

    fill([t fliplr(t)], ...
        [mEarly-semEarly fliplr(mEarly+semEarly)], ...
        [0 0 1], ...
        'FaceAlpha',0.2,'EdgeColor','none')

    plot(t,mEarly,'b','LineWidth',2)

    xline(0,'--k')
    yline(0,':k')

    xlim([-2 10])
    ylim([-1.5 1])

    xlabel("Time (s)")
    ylabel("Aligned z")

    title(sprintf('%s Early (%d-%d)',char(AnimalID),earlyIdx(1),earlyIdx(end)), ...
        'Interpreter','none','FontSize',14)

    grid on

% ==========================================================
% LATE
% ==========================================================

    nexttile
    hold on

    fill([t fliplr(t)], ...
        [mLate-semLate fliplr(mLate+semLate)], ...
        [1 0 0], ...
        'FaceAlpha',0.2,'EdgeColor','none')

    plot(t,mLate,'r','LineWidth',2)

    xline(0,'--k')
    yline(0,':k')

    xlim([-2 10])
    ylim([-1.5 1])

    xlabel("Time (s)")
    ylabel("Aligned z")

    title(sprintf('%s Late (%d-%d)',char(AnimalID),lateIdx(1),lateIdx(end)), ...
        'Interpreter','none','FontSize',14)

    grid on

% ==========================================================
% super title
% ==========================================================

    if opt.AlignAtZero

        title(tl, ...
            sprintf('%s | %s | %s | %s | aligned at t=0', ...
            char(AnimalID),Genotype,Region,BlockType), ...
            'Interpreter','none','FontSize',16)

    else

        title(tl, ...
            sprintf('%s | %s | %s | %s', ...
            char(AnimalID),Genotype,Region,BlockType), ...
            'Interpreter','none','FontSize',16)

    end

% ==========================================================
% save
% ==========================================================

    if opt.SaveFigs

        outName = sprintf("tileEarlyLate_%s_%s_%s_%s.png", ...
            safeID,safeRegion,safeBlock,safeTank);

        exportgraphics(f,fullfile(outDir,outName),'Resolution',300)

        close(f)

    end

end

fprintf("\nDone\n")

end


function s = safe_str(x)

s = char(string(x));
s = strrep(s," ","");
s = strrep(s,"/","-");
s = strrep(s,"\","-");
s = strrep(s,":","-");

end