***

# TAS Recorder Enhanced

**TAS Recorder Enhanced** is a high-precision Tool-Assisted Speedrun (TAS) recording and playback utility for Roblox. Built upon the foundation of the original Tomato/Ali recorder, this version has been completely re-engineered from the ground up. It abandons hacky exploit-dependent hooks in favor of native Roblox API integration, resulting in 1:1 animation replication, flawlessly preserved easing curves, procedural physics retention, and advanced map-debugging tools.

!(https://img.shields.io/badge/Language-Lua-blue.svg) !(https://img.shields.io/badge/Platform-Roblox-red.svg) !(https://img.shields.io/badge/Status-Active-green.svg)

## 🚀 Key Improvements & Technical Deep-Dive

This is not a UI reskin; the core recording and playback logic has been completely rewritten for maximum stability, accuracy, and executor compatibility.

### 1. Executor-Agnostic Animation Tracking (No more `getsenv`)
*   **The Old Flaw:** Previous versions used `getsenv()` to hook the game's default `Animate` script. This was heavily flawed because Luau optimizations often inline function calls, bypassing the hook entirely. Furthermore, it made the script incompatible with many modern executors.
*   **The New Engine:** The script now natively queries the Humanoid's `Animator` object using `GetPlayingAnimationTracks()` every Heartbeat. It captures the exact `TimePosition`, `WeightCurrent`, `Speed`, and `Priority` of every running track.
*   **Educational Note - Track Instance Collisions:** In Roblox, the engine frequently plays multiple overlapping tracks of the *exact same AnimationId* to cross-fade (e.g., blending two jump cycles). Previous TAS scripts grouped animations by ID, which mathematically smashed these overlapping tracks together, destroying the fade. **Fix:** The new script assigns a Unique Identifier (uID) to every animation instance in memory using a weak-keyed metatable cache, ensuring identical overlapping tracks are recorded and played back independently.

### 2. Preserving Native Easing Curves & Speeds
*   **The Old Flaw:** The old playback loop mathematically forced `TimePosition` forward linearly every frame. This ruined Roblox's natural cubic easing curves, making animations (like swimming or jumping) look stiff, shaky, and prematurely cut off.
*   **The New Engine:** The script now records the dynamic `Speed` of the animation. During playback, instead of forcing frames, it applies the exact `Weight` and `Speed` and *lets the Roblox C++ engine play the animation naturally*. It only steps in to manually snap the `TimePosition` if a lag spike causes the engine to drift out of sync by more than `0.15` seconds.

### 3. Procedural Physics & Unanchored Replication
*   **The Old Flaw:** Using `Anchored = true` during playback freezes the character for other players, breaking visual replication in multiplayer. Forcing the `Physics` state machine stops the engine from applying procedural joint sway (gravity IK on the arms/torso).
*   **The New Engine:** The character remains **Unanchored**. To prevent gravity or momentum from ruining the TAS path, the script forces `Velocity = Vector3.zero` while interpolating the `CFrame`. Because the script allows the Humanoid to naturally enter the `Freefall` state, the engine's built-in procedural arm sway is perfectly retained during jumps.

### 4. Advanced Debug View (Checkerboard Map Parsing)
A built-in map visualizer (Keybind: `V`) engineered to help route creation and hitbox analysis:
*   **Ghosting:** `CanCollide = false` parts are made 90% transparent.
*   **Checkerboard Borders:** To easily distinguish overlapping hitboxes, parts are assigned slightly randomized shades.
    *   **Default Hitboxes:** Random shades of Grey.
    *   **Thin Walls:** Walls `<= 1` stud thick are highlighted in random shades of **Cyan** (invaluable for finding wallbangs/clips).
    *   **TouchInterests:** Killbricks and Teleporters are highlighted in random shades of **Bright Red**.

### 5. Loop "Backwards Interpolation" Fix
*   **The Math Bug:** When a looping animation finishes, its `TimePosition` resets from `Length` (e.g., 2.5s) back to `0.0s`. Standard Lerp algorithms attempt to smoothly transition backwards from 2.5 down to 0.0, causing a 1-frame violent reverse jitter.
*   **The Fix:** The script detects if `Frame B`'s time is less than `Frame A`'s time. If so, it calculates the remaining distance to the track's `Length` and wraps it seamlessly forward, completely eliminating playback jitter.

---

## 🛠️ Requirements

*   A standard Roblox Executor.
*   **NO high-level exploits required.** Because this version natively reads the `Animator` object, it no longer requires `getsenv()`, `hookmetamethod`, or unsafe environment manipulation. It is universally compatible.

## 🎮 Controls & Keybinds

| Key | Action | Description |
| :--- | :--- | :--- |
| **Caps Lock** | Pause / Unpause | Toggles recording state. |
| **1** | Add Savestate | Creates a checkpoint at current frame. |
| **2** | Remove Savestate | Deletes the most recent checkpoint. |
| **3** | Enter Savestate | Loads the last savestate into the active buffer, allowing you to edit/continue from it. |
| **8** | Load Last Savestate | Teleports back to the last checkpoint (Visual only). |
| **R** | Frame Back | Rewind 1 frame (Hold to scroll). |
| **F** | Frame Forward | Advance 1 frame (Hold to scroll). |
| **4** | Go Back | Fast rewind (Scrubbing). |
| **5** | Go Forward | Fast forward (Scrubbing). |
| **6** | Save Run | Saves the current run to `workspace/TAS_Recorder/`. |
| **0** | View TAS | Plays back the entire recorded run. |
| **-** | Load Run | Loads a file matching the text box name. |
| **V** | **Debug View** | Toggles the map visualizer (Hitboxes/Triggers/Thin Walls). |
| **C** | Toggle Collision | Toggles `CanCollide` on the part under your mouse. |
| **Del** | Stop Script | Fully disconnects the script, restores physics, and cleans up tracks. |

---

## 💾 Saving & Loading

The script handles files in the `TAS_Recorder` folder. Data is heavily compressed into raw arrays (e.g., ``) to reduce JSON file sizes by ~80%.

1.  **Saving:**
    *   Type a name in the text box (e.g., `Speedrun_1`).
    *   Press **6**.
    *   File saved as: `TAS_Recorder/Speedrun_1.json`.
2.  **Loading:**
    *   Type the name in the text box.
    *   Press **-**.
    *   The script automatically pauses and teleports you to the last frame.

---

## 📜 Credits

*   **Original Concept:** Tomato -> https://scriptblox.com/u/Tomato
*   **Modifications:** Ali -> https://scriptblox.com/u/Ali_
*   **Enhanced Engine & Math Corrections:**

---

**Disclaimer:** Use at your own risk. This tool is intended for educational purposes, speedrun routing, and private servers. Using this in public servers to gain an unfair advantage violates Roblox Terms of Service.
