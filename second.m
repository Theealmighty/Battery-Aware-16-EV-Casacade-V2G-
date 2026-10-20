%% ========================================================================
%  ADD VISUAL COMMON 230V AC BUS BAR & SEQUENTIAL DISPATCHER TO .SLX CANVAS
%  Places the Apartment Load Profile, Cascaded BHI Sequencer, and 3-Axis
%  Master AC Bus Scope directly onto the top-level Simulink diagram.
% =========================================================================
clc;
modelName = 'Battery_16EV_Cascaded_ACBus';
if ~bdIsLoaded(modelName), open_system(modelName); end

% Clean up if already added previously
subName = [modelName '/Common_230V_AC_Bus_&_Apartment_Load'];
scopeName = [modelName '/Master_AC_Bus_Scope'];
if getSimulinkBlockHandle(subName) ~= -1, delete_block(subName); end
if getSimulinkBlockHandle(scopeName) ~= -1, delete_block(scopeName); end

% 1. Create the Common AC Bus & Apartment Load Subsystem on the Canvas
add_block('simulink/Ports & Subsystems/Subsystem', subName, ...
    'Position', [1050, 150, 1320, 380], ...
    'BackgroundColor', 'lightBlue');
Simulink.SubSystem.deleteContents(subName);

% Inside the Subsystem: Create 4-Stage Apartment Load Profile (5->12->20->26 kW)
add_block('simulink/Sources/Repeating Sequence Stair', [subName '/Apartment_Load_Profile_W'], ...
    'OutValues', '[5000 12000 20000 26000]', ...
    'tsamp', '0.5', ...
    'Position', [50, 60, 110, 100]);

% 50 Hz 230V RMS (325.27V Peak) AC Bus Reference Wave
add_block('simulink/Sources/Sine Wave', [subName '/AC_Bus_230V_50Hz'], ...
    'Amplitude', '230*sqrt(2)', ...
    'Frequency', '2*pi*50', ...
    'SampleTime', '0.0001', ...
    'Position', [50, 160, 110, 200]);

% Gain block to convert Power (W) to Peak Current (I_peak = P * sqrt(2) / 230)
add_block('simulink/Math Operations/Gain', [subName '/W_to_Ipeak'], ...
    'Gain', 'sqrt(2)/230', ...
    'Position', [180, 65, 240, 95]);

% Normalized 50 Hz Unit Sine Wave for Current Phase
add_block('simulink/Sources/Sine Wave', [subName '/Unit_50Hz_Phase'], ...
    'Amplitude', '1', ...
    'Frequency', '2*pi*50', ...
    'SampleTime', '0.0001', ...
    'Position', [180, 115, 220, 145]);

% Product block to generate Instantaneous AC Bus Current Waveform
add_block('simulink/Math Operations/Product', [subName '/AC_Current_Gen'], ...
    'Position', [290, 75, 325, 135]);

% Gain block to convert W to kW for clean Scope display
add_block('simulink/Math Operations/Gain', [subName '/W_to_kW'], ...
    'Gain', '0.001', ...
    'Position', [290, 20, 330, 50]);

% Outports for Master AC Bus Scope
add_block('simulink/Sinks/Out1', [subName '/Apartment_Load_kW'], 'Position', [420, 28, 450, 42]);
add_block('simulink/Sinks/Out1', [subName '/V_AC_Bus_230V'],     'Position', [420, 173, 450, 187]);
add_block('simulink/Sinks/Out1', [subName '/I_AC_Bus_Total'],    'Position', [420, 98, 450, 112]);

% Wire blocks inside Subsystem
add_line(subName, 'Apartment_Load_Profile_W/1', 'W_to_kW/1', 'autorouting', 'on');
add_line(subName, 'W_to_kW/1', 'Apartment_Load_kW/1', 'autorouting', 'on');
add_line(subName, 'Apartment_Load_Profile_W/1', 'W_to_Ipeak/1', 'autorouting', 'on');
add_line(subName, 'W_to_Ipeak/1', 'AC_Current_Gen/1', 'autorouting', 'on');
add_line(subName, 'Unit_50Hz_Phase/1', 'AC_Current_Gen/2', 'autorouting', 'on');
add_line(subName, 'AC_Current_Gen/1', 'I_AC_Bus_Total/1', 'autorouting', 'on');
add_line(subName, 'AC_Bus_230V_50Hz/1', 'V_AC_Bus_230V/1', 'autorouting', 'on');

% 2. Add a 3-Port Master Scope on the Top-Level Canvas
add_block('simulink/Sinks/Scope', scopeName, ...
    'NumInputPorts', '3', ...
    'Position', [1420, 165, 1480, 365]);

add_line(modelName, 'Common_230V_AC_Bus_&_Apartment_Load/1', 'Master_AC_Bus_Scope/1', 'autorouting', 'on');
add_line(modelName, 'Common_230V_AC_Bus_&_Apartment_Load/2', 'Master_AC_Bus_Scope/2', 'autorouting', 'on');
add_line(modelName, 'Common_230V_AC_Bus_&_Apartment_Load/3', 'Master_AC_Bus_Scope/3', 'autorouting', 'on');

save_system(modelName);
fprintf('Successfully added Common_230V_AC_Bus_&_Apartment_Load and Master_AC_Bus_Scope to %s.slx!\n', modelName);