# QuestProgressShare
This AddOn sends quest progress to other players.
If you are playing with friends and want to share your quest progress, this AddOn is for you.  
  
If you encounter any issues or errors, please report them in the [Bugtracker](https://github.com/Dreambjorn/QuestProgressShare/issues).

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
- Share quest progress
    - with party members
    - with yourself
    - with local chat
- Share all quest progress or only finished quests
- Share quest links instead of plain titles (only if pfQuest is enabled)

## Changelog

### 1.4.0
- Add party progress tooltips showing real-time, color-coded quest progress for all party members
- Implement live party sync so quest progress is always up to date for everyone
- Refactor core logic for clarity, maintainability, and robustness
- Improve and unify debug logging for easier tracking and troubleshooting
- Move string helper functions to QuestStringHelpers.lua for better organization
- Add option to broadcast abandoned quests to your party (disabled by default, can be enabled in settings)
- Improve handling of party member join/leave, quest completion, and quest abandonment for accurate progress display and cleanup
- Enhance tooltip logic to robustly handle edge cases and only show current party members’ progress
- Remove redundant logic between Core.lua and Tooltip.lua
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
