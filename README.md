***

# TAS Recorder Enhanced

**TAS Recorder Enhanced** is a high-precision Tool-Assisted Speedrun (TAS) recording and playback utility for Roblox. Built upon the foundation of the original Tomato/Ali recorder, this version has been completely re-engineered to support 1:1 animation replication, optimized data storage, robust physics handling, and advanced debugging tools.

![Lua](https://img.shields.io/badge/Language-Lua-blue.svg) ![Platform](https://img.shields.io/badge/Platform-Roblox-red.svg) ![Status](https://img.shields.io/badge/Status-Active-green.svg)

## 🚀 Key Improvements & Features

This is not just a UI reskin; the core logic has been rewritten for stability and accuracy.

### 1. The "Gatekeeper" Animation System
The most significant upgrade is the animation engine.
*   **Old Method:** Checked `Humanoid` state every frame and guessed the animation (e.g., "If velocity > 0 then 'Walk'"). This resulted in desync and jitter.
*   **New Method (Event-Based):** Uses `getsenv()` to hook the game's internal `Animate` script.
    *   **Recording:** Acts as a passthrough, logging exact `playAnimation` calls and transition times while letting the game behave normally.
    *   **Playback:** Acts as a **Gatekeeper**. It completely blocks the game's default animation script from running, preventing it from fighting the TAS. It then manually plays the recorded animation events at the exact tick they occurred.
    *   **Result:** 100% accurate, jitter-free animation playback that persists even after character death/respawn.

### 2. Natural Physics & Replication
*   **Old Method:** Used `Anchored = true` during playback. This causes the character to freeze for other players, breaking visual replication in multiplayer.
*   **New Method:** The character remains **Unanchored** during playback. To prevent gravity or momentum from ruining the path, the script forces `Velocity = Vector3.zero` every frame while interpolating the CFrame.
*   **Result:** Your TAS playback looks smooth and **replicates correctly to other players** in the server.

### 3. Data Optimization (JSON)
*   **Old Method:** Saved verbose dictionaries (e.g., `{ "posX": 12.123456... }`). Files were massive and slow to load.
*   **New Method:** 
    *   **Arrays:** Converts data to compact arrays (e.g., `[12.12, 5.5, 9.1]`).
    *   **Rounding:** All physics data is rounded to 3 decimal places (0.001 stud precision).
    *   **60 FPS Cap:** Recording loop discards excess frames if your FPS > 60, preventing bloated files on high-end PCs.
    *   **Result:** File sizes reduced by **~70-80%**.

### 4. Robust Death Handling
*   **Old Method:** Dying would often wipe the current recording buffer or break the script entirely upon respawn.
*   **New Method:**
    *   **Pause on Death:** The script detects death and immediately pauses recording.
    *   **Auto-Recovery:** Upon respawning, it re-hooks the new character and teleports you back to the last valid frame/savestate.
    *   **Choice:** You can choose to Undo the death (Back Savestate) or Resume (if the death was intentional for the run).

### 5. Debug View Mode
A built-in visualizer (Keybind: `V`) to help route creation:
*   **Invisible Parts:** Made semi-transparent (Visible).
*   **CanCollide False:** Made highly transparent (Ghost).
*   **TouchInterests (Killbricks):** Highlighted in **Bright Red**.
*   **Thin Walls:** Walls < 1 stud thick highlighted in **Cyan** (useful for finding wallbangs/clips).
*   **Part Borders:** Randomizes part colors to visualize geometry edges.

---

## 🛠️ Requirements

*   A Roblox Executor that supports `writefile`, `readfile`, `hookmetamethod` (optional), and crucially **`getsenv`**.
*   *Note: Standard "Level 3" executors may not support the Animation Hooking features.*

## 🎮 Controls & Keybinds

| Key | Action | Description |
| :--- | :--- | :--- |
| **Caps Lock** | Pause / Unpause | Toggles recording state. |
| **1** | Add Savestate | Creates a checkpoint at current frame. |
| **2** | Remove Savestate | Deletes the most recent checkpoint. |
| **3** | **Enter Savestate** | *New!* Loads the last savestate into the active buffer, allowing you to edit/continue from it. |
| **8** | Load Last Savestate | Teleports back to the last checkpoint (Visual only, does not edit buffer). |
| **R** | Frame Back | Rewind 1 frame (Hold to scroll). |
| **F** | Frame Forward | Advance 1 frame (Hold to scroll). |
| **4** | Go Back | Fast rewind (Scrubbing). |
| **5** | Go Forward | Fast forward (Scrubbing). |
| **6** | Save Run | Saves the current run to `workspace/TAS_Recorder/`. |
| **0** | View TAS | Plays back the entire recorded run. |
| **-** | Load Run | Loads a file matching the text box name. |
| **V** | **Debug View** | Toggles the map visualizer (Hitboxes/Triggers). |
| **C** | Toggle Collision | Toggles `CanCollide` on the part under your mouse. |
| **Del** | Stop Script | Fully disconnects the script and cleans up hooks. |

---

## 💾 Saving & Loading

The script handles files in the `TAS_Recorder` folder.

1.  **Saving:**
    *   Type a name in the text box (e.g., `Speedrun_1`).
    *   Press **6**.
    *   File saved as: `TAS_Recorder/Speedrun_1.json`.
2.  **Loading:**
    *   Type the name in the text box.
    *   Press **-**.
    *   The script automatically pauses and teleports you to the last frame.

---

## ⚙️ Technical Comparison

| Feature | Old Script | **Enhanced Script** |
| :--- | :--- | :--- |
| **File Format** | Verbose JSON | **Compact Arrays (Compressed)** |
| **Playback Physics** | Anchored (Frozen) | **Unanchored + Zero Velocity** |
| **Replication** | No (Local visual only) | **Yes (Replicates to server)** |
| **Animation Method** | Guesswork (Velocity checks) | **Direct `playAnimation` Hook** |
| **Framerate** | Uncapped (Bloats files) | **Capped at 60 FPS** |
| **Camera** | Default | **Smoothed Interpolation** |
| **Respawning** | Breaks script/Wipes data | **Auto-rehooks & Restores state** |
| **UI** | Static | **Draggable + Status Colors** |

---

## 📜 Credits

*   **Original Script:** Tomato -> https://scriptblox.com/u/Tomato
*   **Modifications:** Ali -> https://scriptblox.com/u/Ali_
*   **Enhanced / Optimized Version:** [Tomato / "AI Assisted"]

---

**Disclaimer:** Use at your own risk. This tool is intended for educational purposes and private servers. Using this in public servers to gain an unfair advantage may result in a ban.
