# QuestProgressShare
This AddOn sends quest progress to other players.
If you are playing with friends and want to share your quest progress, this AddOn is for you.

## Installation
1. Download the latest version from the [releases page](https://github.com/Dreambjorn/QuestProgressShare/releases)
2. Extract the archive and copy the `QuestProgressShare` folder to your `Interface/AddOns` folder

## Usage
- `/qps` to open the settings window

## Features
- Share quest progress
    - with other players in the group
    - with yourself
    - with local chat
- Share all quest progress or only finished quests

## Changelog

### 1.1.2
- Show "Quest accepted" and "Quest completed" in chat instead of progress updates
- Add a startup delay on player login to prevent game freeze in situations where the quest log has 15 or more quests
- Fix "Quest completed" not showing for turn-in only quests

### 1.1.1
- Fixed incorrectly working only-send-finished-quests option while in a group

### 1.1.0

- Added option to skip messages when a quest starts
- Fixed unnecessary UI reloads

### 1.0.1

- Fixed a bug where the AddOn would not displayed in the pfUI "AddOn Button Frame"

### 1.0.0

- Initial release
