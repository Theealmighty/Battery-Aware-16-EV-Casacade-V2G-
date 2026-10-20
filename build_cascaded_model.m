%% ========================================================================
%  AUTO-BUILDER: 16-EV CASCADED BHI DISPATCH + COMMON 230V AC BUS BAR
%  Automatically finds Battery_12_Modelwithinvbhi.slx, fixes internal
%  branch wiring, runs the simulation, and plots the 4-stage AC cascade.
% =========================================================================
clc; close all;

% 1. Automatically find the .slx file in your current folder
if isfile('Battery_12_Modelwithinvbhi.slx')
    origModel = 'Battery_12_Modelwithinvbhi';
elseif isfile('Battery_12_Modelwithinvbhi_2.slx')
    origModel = 'Battery_12_Modelwithinvbhi_2';
else
    fprintf('Select your .slx file in the popup window...\n');
    [fName, fPath] = uigetfile('*.slx', 'Select Battery_12_Modelwithinvbhi.slx');
    if isequal(fName, 0), error('No file selected.'); end
    cd(fPath);
    [~, origModel, ~] = fileparts(fName);
end

newModel = 'Battery_16EV_Cascaded_ACBus';

% 2. Load workspace parameters if not already loaded
if ~exist('packs', 'var') || ~exist('branchSOH', 'var')
    if isfile('battery_pack_parameters.mat')
        load('battery_pack_parameters.mat');
        fprintf('Loaded battery_pack_parameters.mat\n');
    else
        % Fallback check one folder up
        if isfile('../battery_pack_parameters.mat')
            load('../battery_pack_parameters.mat');
            fprintf('Loaded ../battery_pack_parameters.mat\n');
        else
            error('Please load battery_pack_parameters.mat into your Workspace first!');
        end
    end
end

% 3. Copy and open the new .slx file so your original file stays safe
if bdIsLoaded(origModel), close_system(origModel, 0); end
if bdIsLoaded(newModel),  close_system(newModel, 0);  end
copyfile([origModel '.slx'], [newModel '.slx'], 'f');
load_system(newModel);
fprintf('Successfully created %s.slx from %s.slx\n', newModel, origModel);

groupNames    = {'Pack120khw','Pack_2_30khw','Pack_335kwh','Pack440khw'};
branchLetters = {'A','B','C','D'};

%% ========================================================================
%  PART A: FIX INTERNAL WIRING INSIDE ALL 16 BRANCH SUBSYSTEMS
%  - Removes duplicate Test_load (SID 994 in Pack_2_A)
%  - Sets Load resistor to 7 kW @ 230V RMS equivalent (7.557 Ohm)
%  - Fixes Scope Y-limits so AC waveforms (-350V to +350V) are visible
% =========================================================================
for g = 1:4
    for L = 1:4
        subPath = sprintf('%s/%s/Pack_%d_%s', newModel, groupNames{g}, g, branchLetters{L});
        
        % Remove accidental Test_load in Pack_2_A if present
        testLoadBlk = [subPath '/Test_load'];
        if getSimulinkBlockHandle(testLoadBlk) ~= -1
            lh = get_param(testLoadBlk, 'LineHandles');
            if ~isempty(lh.LConn) && lh.LConn ~= -1, delete_line(lh.LConn); end
            if ~isempty(lh.RConn) && lh.RConn ~= -1, delete_line(lh.RConn); end
            delete_block(testLoadBlk);
            fprintf('Removed duplicate Test_load inside %s\n', subPath);
        end
        
        % Set local Load resistor to 7 kW equivalent @ 230V RMS (R = 230^2 / 7000 = 7.557 Ohm)
        loadBlk = [subPath '/Load'];
        if getSimulinkBlockHandle(loadBlk) ~= -1
            set_param(loadBlk, 'R', '7.557');
        end
        
        % Fix Scope Y-Limits inside each branch so AC voltage is not clipped
        scopeBlk = [subPath '/Scope'];
        if getSimulinkBlockHandle(scopeBlk) ~= -1
            try
                set_param(scopeBlk, 'YMin', '-420', 'YMax', '420');
            catch
            end
        end
    end
end

save_system(newModel);
fprintf('Saved internal fixes to %s.slx\n', newModel);

%% ========================================================================
%  PART B: RUN SIMULATION & EXECUTE CASCADED BHI PRIORITY DISPATCH
% =========================================================================
fprintf('Running Simulink model %s (StopTime = 2s)...\n', newModel);
simOut = sim(newModel, 'StopTime', '2');

Branch = cell(16,1);
SOH    = zeros(16,1);
SOC    = zeros(16,1);
Temp   = zeros(16,1);
MaxV   = zeros(16,1);

idx = 1;
for g = 1:4
    for L = 1:4
        Branch{idx} = sprintf('%d_%s', g, branchLetters{L});
        stackPath   = sprintf('Pack_%d_%s', g, branchLetters{L});
        stack       = simOut.simlog.(groupNames{g}).(stackPath).Pack_Stack;
        
        socArr  = stack.soc.series.values;
        tempArr = stack.cell_temperature.series.values;
        vArr    = stack.v.series.values;
        
        SOH(idx)  = branchSOH(idx);
        SOC(idx)  = socArr(1);
        Temp(idx) = tempArr(1);
        MaxV(idx) = max(vArr);
        idx = idx + 1;
    end
end

% 1. Hard Safety Gate Check (SOC > 0.20, SOH > 0.75, Temp < 310 K)
eligible = (SOC > 0.20) & (SOH > 0.75) & (Temp < 310.0);

% 2. AHP BHI Priority Calculation
%    Weights: SOC=0.266, SOH=0.106, Temp=0.167, Age=0.053, Reserve=0.409
T_norm    = (Temp - 298.15) / 15.0;
Reserve   = max(0, SOC - 0.20);
Age_score = SOH;

BHI = 0.266*SOC + 0.106*SOH - 0.167*T_norm + 0.053*Age_score + 0.409*Reserve;
BHI(~eligible) = NaN;

% 3. Sort Priority Ranking (Winner #1 -> #16)
rankTable = table(Branch, SOH, SOC, Temp, MaxV, eligible, BHI);
rankTable = sortrows(rankTable, 'BHI', 'descend', 'MissingPlacement', 'last');
rankTable.Rank = (1:16)';
rankTable = movevars(rankTable, 'Rank', 'Before', 'Branch');

fprintf('\n====================================================================\n');
fprintf('         16-EV FLEET AHP-BHI PRIORITY RANKING TABLE\n');
fprintf('====================================================================\n');
disp(rankTable);

%% ========================================================================
%  PART C: CASCADED RESIDENTIAL APARTMENT LOAD DISPATCH & AC BUS WAVEFORMS
%  Bus Rating: 230 V RMS (325.27 V Peak), 50 Hz, 100 A Main Breaker
%  Per-EV Converter Rating: 7 kW
% =========================================================================
fs = 10000;                  % 10 kHz sampling for clean 50 Hz AC waveform
t  = (0:1/fs:2)';            % 2-second simulation timeline
f_ac = 50;                   % 50 Hz AC Bus frequency
V_rms = 230;                 % 230 V RMS Common AC Bus Bar
V_peak = V_rms * sqrt(2);    % 325.27 V Peak

% 4-Stage Residential Apartment Load Profile (Watts)
P_load = zeros(size(t));
P_load(t >= 0.0 & t < 0.5) = 5000;   % Stage 1: 5 kW Base Load (1 EV needed: 3_D)
P_load(t >= 0.5 & t < 1.0) = 12000;  % Stage 2: 12 kW Morning Load (2 EVs: 3_D + 3_C)
P_load(t >= 1.0 & t < 1.5) = 20000;  % Stage 3: 20 kW Evening Peak (3 EVs: 3_D + 3_C + 2_C)
P_load(t >= 1.5 & t <= 2.0) = 26000; % Stage 4: 26 kW Critical Peak (4 EVs: 3_D + 3_C + 2_C + 1_C)

P_inv_max = 7000; % 7 kW max per EV inverter

% Common AC Bus Voltage & Individual/Total Current Waveforms
V_ac_bus = V_peak * sin(2*pi*f_ac*t);

% Calculate per-EV power allocation in priority order (Each EV capped at 7 kW)
P_EV1 = min(P_load, P_inv_max);                                 % Priority #1 (3_D)
P_EV2 = max(0, min(P_load - P_inv_max, P_inv_max));             % Priority #2 (3_C)
P_EV3 = max(0, min(P_load - 2*P_inv_max, P_inv_max));           % Priority #3 (2_C)
P_EV4 = max(0, min(P_load - 3*P_inv_max, P_inv_max));           % Priority #4 (1_C)

I_EV1_ac = (P_EV1 / V_rms) * sqrt(2) .* sin(2*pi*f_ac*t);
I_EV2_ac = (P_EV2 / V_rms) * sqrt(2) .* sin(2*pi*f_ac*t);
I_EV3_ac = (P_EV3 / V_rms) * sqrt(2) .* sin(2*pi*f_ac*t);
I_EV4_ac = (P_EV4 / V_rms) * sqrt(2) .* sin(2*pi*f_ac*t);
I_total_ac = I_EV1_ac + I_EV2_ac + I_EV3_ac + I_EV4_ac;

% Print Dispatch Cascade Summary Table
stageNames = {'0.0 - 0.5 s (Base)'; '0.5 - 1.0 s (Morning)'; '1.0 - 1.5 s (Evening)'; '1.5 - 2.0 s (Peak)'};
loadKW     = [5; 12; 20; 26];
evsOn      = [1; 2; 3; 4];
activeList = { ...
    sprintf('%s (5 kW)', rankTable.Branch{1}); ...
    sprintf('%s (7 kW) + %s (5 kW)', rankTable.Branch{1}, rankTable.Branch{2}); ...
    sprintf('%s (7 kW) + %s (7 kW) + %s (6 kW)', rankTable.Branch{1}, rankTable.Branch{2}, rankTable.Branch{3}); ...
    sprintf('%s (7 kW) + %s (7 kW) + %s (7 kW) + %s (5 kW)', rankTable.Branch{1}, rankTable.Branch{2}, rankTable.Branch{3}, rankTable.Branch{4})};

cascadeTable = table(stageNames, loadKW, evsOn, activeList, ...
    'VariableNames', {'Time_Window','Apartment_Load_kW','EVs_Dispatched','Active_Inverters_Priority_Order'});
fprintf('\n====================================================================\n');
fprintf('       SEQUENTIAL PRIORITY DISPATCH SUMMARY (230V AC BUS)\n');
fprintf('====================================================================\n');
disp(cascadeTable);

%% ========================================================================
%  PART D: PLOT WHITE-BACKGROUND GRAPHS OF CASCADED AC BUS OPERATION
% =========================================================================
figure('Name','Cascaded BHI Priority Dispatch & 230V AC Bus Waveforms', ...
       'Position',[100 50 1100 780]);
set(gcf, 'Color', 'w');

% Subplot 1: Apartment Load Demand vs Per-EV Power Sharing
subplot(3,1,1);
hold on;
plot(t, P_load/1000, 'k-', 'LineWidth', 2.5);
plot(t, P_EV1/1000,  'b--', 'LineWidth', 1.8);
plot(t, P_EV2/1000,  'r--', 'LineWidth', 1.8);
plot(t, P_EV3/1000,  'g--', 'LineWidth', 1.8);
plot(t, P_EV4/1000,  'm--', 'LineWidth', 1.8);
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
ylabel('Power (kW)', 'Color', 'k', 'FontWeight', 'bold');
title('Residential Apartment Load Profile & Sequential BHI Priority Power Sharing (7 kW/EV Limit)', 'Color', 'k');
lgd1 = legend({'Total Apartment Load', ...
               sprintf('#1 Priority: Pack %s (Max 7 kW)', rankTable.Branch{1}), ...
               sprintf('#2 Priority: Pack %s (Joins at 0.5s)', rankTable.Branch{2}), ...
               sprintf('#3 Priority: Pack %s (Joins at 1.0s)', rankTable.Branch{3}), ...
               sprintf('#4 Priority: Pack %s (Joins at 1.5s)', rankTable.Branch{4})}, ...
              'Location', 'northwest');
set(lgd1, 'Color', 'w', 'TextColor', 'k');
grid on; ylim([0 30]);

% Subplot 2: Common 230V AC Bus Bar Voltage (Zoomed transition 0.40s to 0.60s)
subplot(3,1,2);
plot(t, V_ac_bus, 'b-', 'LineWidth', 1.2);
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
ylabel('AC Bus Voltage (V)', 'Color', 'k', 'FontWeight', 'bold');
title('Common AC Bus Bar Voltage Waveform (230 V RMS / 325.3 V Peak, 50 Hz)', 'Color', 'k');
xlim([0.40 0.60]); ylim([-380 380]);
grid on;

% Subplot 3: Total AC Bus Bar Current Stepping Up as Priority EVs Join
subplot(3,1,3);
plot(t, I_total_ac, 'r-', 'LineWidth', 1.2);
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
xlabel('Simulation Time (s)', 'Color', 'k', 'FontWeight', 'bold');
ylabel('AC Bus Current (A)', 'Color', 'k', 'FontWeight', 'bold');
title('Total AC Bus Current Delivered to Apartment Load (Steps Up at 0.5s, 1.0s, 1.5s as Next Priority EV Joins)', 'Color', 'k');
ylim([-180 180]);
grid on;

open_system(newModel);