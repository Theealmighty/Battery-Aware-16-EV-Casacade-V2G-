%% EXTRACT EXACT PACK CURRENTS FROM SIMULATION LOG
fprintf('\n====================================================================\n');
fprintf('          16-EV FLEET INDIVIDUAL PACK CURRENT MEASUREMENTS\n');
fprintf('====================================================================\n');

groupNames    = {'Pack120khw','Pack_2_30khw','Pack_335kwh','Pack440khw'};
branchLetters = {'A','B','C','D'};

packCurrentTable = table();
idx = 1;

for g = 1:4
    for L = 1:4
        branchName = sprintf('%d_%s', g, branchLetters{L});
        stackPath  = sprintf('Pack_%d_%s', g, branchLetters{L});

        try
            % Access the Simscape logging data for the current sensor
            iSensor = simOut.simlog.(groupNames{g}).(stackPath).Pack_Current_Sensor.current.series.values;
            timeVec = simOut.simlog.(groupNames{g}).(stackPath).Pack_Current_Sensor.current.series.time;

            % Get average current during the final steady state
            avgCurrent = mean(iSensor(timeVec >= 1.5)); 

            Status = 'Active (Discharging)';
            if abs(avgCurrent) < 0.1
                Status = 'Isolated / OFF';
            end

            packCurrentTable{idx, 'Branch'}  = {branchName};
            packCurrentTable{idx, 'Avg_Current_A'} = round(avgCurrent, 2);
            packCurrentTable{idx, 'Operational_Status'} = {Status};
        catch
            packCurrentTable{idx, 'Branch'}  = {branchName};
            packCurrentTable{idx, 'Avg_Current_A'} = 0;
            packCurrentTable{idx, 'Operational_Status'} = {'Not Logged'};
        end
        idx = idx + 1;
    end
end

disp(packCurrentTable);
fprintf('====================================================================\n');