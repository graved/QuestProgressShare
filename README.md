# QuestProgressShare
Automatically syncs quest progress with your party in real time. Designed for smoother and more coordinated group questing without the need for manual updates or chat messages. 
  
If you encounter any issues or errors, please report them in the [bugtracker](https://github.com/Dreambjorn/QuestProgressShare/issues).

If you have any feature requests, please let me know [here](https://github.com/Dreambjorn/QuestProgressShare/issues).

## Installation

### I. Manual Installation

1. Download the latest version from the [releases page](https://github.com/Dreambjorn/QuestProgressShare/releases)
2. Extract the archive and copy the `QuestProgressShare` folder to your `Interface/AddOns` folder

### II. Automatic Installation

1. Go to the Addons tab in the Turtle WoW Launcher
2. Use the "Add new addon" button and enter the [repository link](https://github.com/Dreambjorn/QuestProgressShare.git) to install the addon

## Usage
- `/qps` to open the settings window

## Features
- **Share quest progress**
    - with party members
    - with yourself
    - with local chat
- **Share all quest progress or only finished quests**
- **Share quest links instead of plain titles** *(only if pfQuest is enabled)*
- **Party progress tooltips** - View party member quest progress by hovering over:
    - Quest log entries - Display party member progress for the same quest when hovering over quest log titles
    - Tracker entries - Show party member progress in pfQuest tracker tooltips when available
    - World objects/mobs - View party progress for quest-related entities when hovering over them in the world

## Changelog

### 1.5.0
- Add world object/mob tooltip integration to display party quest progress when hovering over quest-related entities
- Deduplicate and unify tooltip logic by creating helper functions for class colors and objective processing
- Unify world object/mob tooltip integration to always use GameTooltip for consistent party progress display
- Preserve pfQuest integration where required while eliminating unnecessary pfQuest checks in world object/mob tooltips
- Improve message coloring consistency by using centralized IsObjectiveComplete() helper function
- Enhance code maintainability by removing redundant logic between quest log/tracker tooltips and world object/mob tooltip systems
- Update tooltip comments to reflect unified approach with helper functions
- Refactor debug logging system to support two-tier debugging with normal and verbose modes
- Add Verbose Debug configuration option that can only be enabled when main debug logging is active
- Optimize debug output by moving highly detailed logs (table dumps, per-objective traces, string parsing internals) to verbose-only mode

### 1.4.5
- Fix objective progress coloring by adding per-objective completion status tracking
- Send party sync progress data regardless of addon config

### 1.4.4
- Fix missing final progress messages for completed objectives in multi-objective quests

### 1.4.3
- Fix 'Quest completed' message reliability and stale progress cleanup on login

### 1.4.2
- Fix missing "Quest abandoned" message on repeated quest abandonment

### 1.4.1
- Fix duplicate "Quest completed" message sent on quest completion

### 1.4.0
- Add party progress tooltips showing real-time, color-coded quest progress for all party members
- Implement live party sync so quest progress is always up to date for everyone
- Refactor core logic for clarity, maintainability, and robustness
- Improve and unify debug logging for easier tracking and troubleshooting
- Move string helper functions to [QuestStringHelpers.lua](https://github.com/Dreambjorn/QuestProgressShare/blob/main/util/QuestStringHelpers.lua) for better organization
- Add option to broadcast abandoned quests to your party (disabled by default, can be enabled in settings)
- Improve handling of party member join/leave, quest completion, and quest abandonment for accurate progress display and cleanup
- Enhance tooltip logic to robustly handle edge cases and only show current party members’ progress
- Remove redundant logic between [Core.lua](https://github.com/Dreambjorn/QuestProgressShare/blob/main/Core.lua) and [Tooltip.lua](https://github.com/Dreambjorn/QuestProgressShare/blob/main/Tooltip.lua)
- Fix issues with party progress not updating correctly when members join, leave, or reconnect
- Fix rare cases where tooltips could show outdated or incorrect progress
- Fix color-coding inconsistencies for certain classes and completion states
- Address edge cases where abandoned or completed quests could still appear in party progress
- Improve documentation and inline comments for easier future maintenance

### 1.2.1
- Prevent spam of "Quest accepted" messages on initial addon load

### 1.2.0
- Add pfQuest integration to send quest links instead of plain titles  
- Use ChatThrottleLib to prevent addon compatibility issues  
- Reorganize addon file structure 
 
  **Note: If pfQuest is not installed, the addon will still function using its legacy plain title messages.**

### 1.1.7
- Add a custom string library to handle string.match (or similar) safely
- Implement saved quest progress using saved character variables

### 1.1.6
- Suppress quest progress messages on reload after collapsing quest headers

### 1.1.5
- Prevent "Quest accepted" message from showing when expanding quest categories

### 1.1.3
- Don't show "Quest completed" message when quest is abandoned

### 1.1.2
- Show "Quest accepted" and "Quest completed" in chat instead of progress updates
- Add a startup delay on player login to prevent game freeze in situations where the quest log has 15 or more quests
- Fix "Quest completed" not showing for turn-in only quests
- Store current quests in a Saved Character Variable (it only applies to self)

### 1.1.1
- Fixed incorrectly working only-send-finished-quests option while in a group

### 1.1.0

- Added option to skip messages when a quest starts
- Fixed unnecessary UI reloads

### 1.0.1

- Fixed a bug where the AddOn would not displayed in the pfUI "AddOn Button Frame"

### 1.0.0

- Initial release
