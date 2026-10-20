# 16-EV Vehicle-to-Building (V2B) Microgrid with AHP-BHI Priority Dispatch

This repository contains the digital twin and software validation framework for a **16-EV Cascaded AC Bus Microgrid**. Built in MATLAB/Simulink using Simscape, this project demonstrates a highly dynamic, cyber-physical dispatcher that safely aggregates power from an electric vehicle fleet to support a residential apartment load.

The system utilizes an Analytic Hierarchy Process (AHP) and Battery Health Index (BHI) algorithm to intelligently rank vehicles, isolate faulty packs, and sequentially dispatch inverters to maintain a stable 230V RMS (50 Hz) AC microgrid under extreme load conditions up to 84 kW.

## 🚀 Key Features

* **Cyber-Physical Safety Gates (Layer 1):** Actively monitors real-time telemetry (SOC, SOH, Temperature). Instantly isolates any battery exceeding thermal limits (Temp > 310 K) or dropping below minimum charge (SOC < 20%) to prevent deep discharge and thermal runaway.
* **AHP-BHI Priority Scoring (Layer 2):** Calculates a composite Battery Health Index for all healthy EVs using customized mathematical weights: Reserve Capacity (0.409), SOC (0.266), Temperature (0.167), SOH (0.106), and Age (0.053).
* **Dynamic Load-Matching Cascade (Layer 3):** Rather than triggering all vehicles simultaneously, the algorithm calculates exactly how many 7 kW EV inverters are needed to meet the instantaneous building demand and sequences them ON in strict BHI priority order.
* **Grid Stability:** Utilizes a parallel H-bridge inverter topology with LC filters to ensure a perfectly synchronized 230V RMS AC bus bar, immune to voltage collapse even during massive load steps.

## 🧠 System Architecture

Each of the 16 EV branches is a self-contained digital twin consisting of the following major subsystems:

1. **Energy Source & Telemetry:** Simscape physical model of Panasonic NCR18650BD battery packs (ranging from 20 to 40 kWh). Features precision series current sensing and parallel voltage sensing for accurate discharge telemetry.
2. **BMS Controller:** The digital brain that processes the safety gates and AHP-BHI logic, outputting a precise digital `Enable_CMD` signal (1 or 0) based on fleet priority and grid demand.
3. **H-Bridge Inverter:** Four-MOSFET switching circuit converting DC battery voltage into high-frequency chopped AC, strictly gated by the BMS `Enable_CMD`.
4. **Filter & Grid Connection:** An LC filter (2 mH inductor, 10 uF capacitor) smooths the chopped output into a 50 Hz sine wave before connecting to the common microgrid bus.

## 📊 Simulation Scenario: The 84 kW Deep Cascade

The flagship validation test provided in this repository (`run_deep_cascade.m`) pushes the 16-EV fleet to its absolute limit over a 4-second simulation.

* **The Load:** A 5-stage extreme residential demand profile stepping from 20 kW up to 84 kW.
* **The Fleet:** 16 EVs total. 4 EVs are intentionally seeded with unsafe parameters (e.g., Temp > 310 K) to validate fault isolation. 12 EVs are healthy and available.
* **The Result:** The BMS successfully locks out the 4 faulty EVs, keeping them safely offline. The 12 healthy EVs are ranked and dispatched dynamically. As the load steps up, the system automatically stacks the power from the 12 active EVs one by one, scaling the total AC bus current to ~516 Amps while maintaining a flawless 230V RMS grid voltage.

## 📂 Repository Contents

* `Battery_16EV_Cascaded_ACBus.slx` - The core Simulink/Simscape model containing the complete 16-branch microgrid topology, master dispatcher, and apartment load blocks.
* `run_deep_cascade.m` - The primary automated execution script. Runs the 4-second extreme load scenario, safely handles missing log data, prints the priority ranking table to the Command Window, and generates publication-ready cascade/telemetry graphs.
* `foursecond.m` - Legacy development script for initial 4-second load testing and block validation.

## ⚙️ How to Run

1. Open MATLAB (ensure Simscape and Simscape Electrical toolboxes are installed).
2. Clone this repository and set the downloaded folder as your active MATLAB directory.
3. Ensure Simscape data logging is enabled: Open `Battery_16EV_Cascaded_ACBus.slx` > **Modeling** > **Model Settings** > **Simscape** > Set "Log simulation data" to **All**.
4. Run `run_deep_cascade.m` from the Command Window or Editor.
5. View the generated **Priority Ranking Table** in the Command Window and the two auto-generated figures: the **Master Microgrid Cascade Graph** and the **Individual Battery Telemetry Scope**.

## 🛠 Phase 2: Hardware Implementation (In Progress)

With software validation successfully completed, Phase 2 will transition this mathematical framework into a physical 24V hardware testbench. The upcoming physical implementation will utilize:

* **Dual ESP32 Microcontrollers:** Porting the MATLAB BHI priority logic into C++ for real-time edge processing.
* **INA226 Sensors:** High-precision physical ICs replacing the digital Simscape voltage/current sensors.
* **Solid State Relays:** Replicating the AC breaker and `Enable_CMD` isolation mechanisms on physical battery packs.
