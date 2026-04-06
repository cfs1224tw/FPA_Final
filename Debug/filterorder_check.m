close all;clear all; clc;
TankPath = '/Users/foxking/Desktop/FP_Project/AnimalData/FX_736/AUX/CleanOnly/736-250328-140342';
% orders = [2 3 4];
% 
% figure
% 
% for k = 1:numel(orders)
%     [z, t] = fp_load_tdt_eventlocked_filter( ...
%         TankPath, [], ...
%         'FilterType', 'bandpass', ...
%         'FilterOrder', orders(k), ...
%         'HighpassCutoff', 0.0051, ...
%         'LowpassCutoff', 2.2860, ...
%         'Padding', true, ...
%         'PaddingPerc', 0.05);
% 
%     subplot(1,3,k)
%     plot(t, mean(z,1), 'LineWidth', 1.5)
%     title(['Order = ' num2str(orders(k))])
%     xlabel('Time (s)')
%     ylabel('z')
% end

types = {'nofilter','highpass','lowpass','bandpass'};

figure

for k = 1:4
    [z, t] = fp_load_tdt_eventlocked_filter( ...
        TankPath, [], ...
        'BaqScalingType','OLS', ...
        'FilterType',types{k}, ...
        'HighpassCutoff',0.0051, ...
        'LowpassCutoff',2.2860, ...
        'FilterOrder',3, ...
        'Padding',true, ...
        'PaddingPerc',0.1);

    m = mean(z,1);

    % align t = 0
    idx0 = find(t >= 0, 1, 'first');
    m = m - m(idx0);

    subplot(1,4,k)
    plot(t, m, 'LineWidth',1.5)
    title(types{k})
    xlim([-2 10]);
    ylim([-1.05 0.1]);
    xlabel('Time (s)')
    ylabel('z (aligned)')
    grid on
end
