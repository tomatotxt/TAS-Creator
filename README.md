***

# TAS Recorder Redux: Kinematic Edition

**TAS Recorder Redux** is a high-precision Tool-Assisted Speedrun (TAS) recording and playback utility for Roblox. Built upon the foundation of the original Tomato/Ali recorder, this version has been completely re-engineered from the ground up. It abandons complex and fragile animation hooking in favor of a **purely kinematic physics engine**, resulting in absolute 1:1 positional replication, real-time trajectory visualization, exact camera tracking, and cinematic playback smoothing.

!(https://img.shields.io/badge/Language-Lua-blue.svg) !(https://img.shields.io/badge/Platform-Roblox-red.svg) !(https://img.shields.io/badge/Status-Active-green.svg)

## 🚀 Key Improvements & Technical Deep-Dive

This is a complete architectural rewrite. The core recording and playback logic has been optimized for maximum stability, visual accuracy, and cinematic rendering.

### 1. Pure Kinematic State Replication (No more Animation Hooks)
*   **The Old Flaw:** Previous versions attempted to track and replay the Humanoid's `Animator` tracks. This caused severe desyncs on complex games with overlapping tracks, and frequently broke across different executors.
*   **The New Engine:** The script now entirely ignores animations. Instead, it records the exact `CFrame`, `Velocity`, `RotVelocity`, and numerical `HumanoidStateType` (e.g., Freefall, Jumping) every frame. During playback, it unanchors the root, applies spherical linear interpolation (Lerp) to the CFrame, and exactly injects the rotational/linear velocity into all character limbs. This forces the Roblox engine to naturally reconstruct the visual state perfectly without relying on fragile animation data.

### 2. Matrix Orthogonality & Anti-Drift Math
*   **The Old Flaw:** Blindly saving and interpolating CFrame rotation matrices causes floating-point errors over time, eventually breaking matrix orthogonality and causing "micro-drift" (shaky/tilting characters).
*   **The New Engine:** The engine now breaks down the CFrame into components and applies a precision `round()` function to the 10,000th decimal *only* on the spatial coordinates (X, Y, Z). It intentionally leaves the rotation matrix completely unrounded, permanently preventing matrix corruption and positional drift while keeping JSON sizes optimized.

### 3. Real-Time Trajectory & Path Visualizers
*   **Velocity Trajectory:** Includes a built-in predictive visualizer (Keybind: `L`). It utilizes `Workspace:Blockcast` to calculate Roblox's internal gravity (`-196.2`), WalkSpeed, and air-acceleration to draw dynamic, color-coded trajectory lines up to 150 frames into the future. 
*   **Playback Pathing:** During playback, the engine draws a Cyan trail predicting the future path of the speedrun up to 20 seconds ahead.

### 4. Cinematic "Extreme Smoothing" & Camera Tracking
*   **Playback Camera:** The script now continuously logs `Workspace.CurrentCamera.CFrame` and seamlessly mimics the exact player camera movements during playback.
*   **Extreme Smoothing Mode:** A headless global variable (`ExtremeSmoothing`) allows you to severely downsample the recorded JSON data to a target FPS (e.g., 24). The engine will then perfectly interpolate between these stretched gaps, creating an ultra-smooth cinematic playback ideal for video rendering (Note: May cause visual wall-clipping).

### 5. Graceful Death Handling & Input Scrubbing
*   **Smart Rewind:** Frame-by-frame advancing/rewinding (`R` and `F`) now uses unique execution IDs, allowing you to hold the keys down to smoothly scrub through time without overlapping loop crashes.
*   **Auto-Recovery:** If your character dies while recording, the script immediately pauses, waits for you to respawn, and automatically teleports you to your last saved frame/savestate so you can continue the run seamlessly.

### 6. Advanced Debug View (Checkerboard Map Parsing)
A built-in map visualizer (Keybind: `V`) engineered to help route creation and hitbox analysis:
*   **Ghosting:** `CanCollide = false` parts are made 90% transparent.
*   **Checkerboard Borders:** To easily distinguish overlapping hitboxes, parts are assigned slightly randomized grey shades.
*   **Thin Walls:** Walls `< 1` stud thick are highlighted in random hues (excluding cyan) so you can easily spot clip/wallbang setups.
*   **TouchInterests:** Killbricks and Teleporters are immediately flagged in bright, randomized shades of **Red**.

---

## 🛠️ Requirements

*   A standard Roblox Executor.
*   **NO high-level exploits required.** Because this version natively reads simple physics properties (CFrame/Velocity) and utilizes standard UI functionality, it is universally compatible with almost any executor.

## 🎮 Controls & Keybinds

| Key | Action | Description |
| :--- | :--- | :--- |
| **Caps Lock** | Pause / Unpause | Toggles recording state. Anchors/Unanchors you. |
| **1** | Add Savestate | Creates a checkpoint at the current frame. |
| **2** | Remove Savestate | Deletes the most recent checkpoint. |
| **3** | Enter Savestate | Loads the last savestate into the active buffer (Edit Mode). |
| **8** | Load Last Savestate | Teleports back to the last checkpoint. |
| **R** | -1 Frame | Rewind 1 frame (Hold to scrub smoothly). |
| **F** | +1 Frame | Advance 1 frame (Hold to scrub smoothly). |
| **6** | Save JSON | Saves the current run data to `workspace/TAS_Recorder/`. |
| **0** | View TAS | Plays back the entire recorded run. |
| **-** | Load JSON | Loads a `.json` file matching the text box name. |
| **L** | Toggle Velocity Vis | Toggles the predictive trajectory blockcast visualizer. |
| **V** | Debug View | Toggles the map visualizer (Hitboxes/Triggers/Thin Walls). |
| **C** | Toggle Collision | Toggles `CanCollide` on the part under your mouse. |
| **Del** | Stop Script | Fully disconnects the script, restores physics, and deletes GUI. |

---

## 💾 Saving, Loading & Headless Mode

The script handles files in the `TAS_Recorder` folder. Data is efficiently saved to standard `.json` formats. 

1.  **Saving:**
    *   Type a name in the text box (e.g., `Speedrun_1`).
    *   Press **6**.
    *   File saved as: `TAS_Recorder/Speedrun_1.json`.
2.  **Loading:**
    *   Type the name in the text box.
    *   Press **-**.
    *   The script automatically pauses, parses the JSON, and teleports you to the starting frame.
3.  **Auto Load & Play (Headless Mode):**
    *   At the top of the script code, change `getgenv().AutoLoadAndPlayFile = "Speedrun_1"`.
    *   When executed, the script skips generating the GUI, automatically parses the file, and plays the TAS instantly for clean video recording.

---

## 📜 Credits

*   **Original Concept:** Tomato -> https://scriptblox.com/u/Tomato
*   **Modifications:** Ali -> https://scriptblox.com/u/Ali_
*   **Enhanced Engine & Kinematic Math: [Tomato -> AI Assisted] **

---

**Disclaimer:** Use at your own risk. This tool is intended for educational purposes, speedrun routing, and private servers. Using this in public servers to gain an unfair advantage violates Roblox Terms of Service.
