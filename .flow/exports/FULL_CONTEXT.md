# FULL CONTEXT — YTMusix

## Project Overview
Here is a ready-to-use template for your project's README.md file [1]. It is structured specifically for a personal portfolio project, highlighting your learning journey and technical skills while being transparent about the project's scope.
------------------------------
## Custom Background Music Player
A personal mobile application designed to stream audio from public YouTube playlists [1]. Built as a learning project to understand mobile app development, API integration, and handling background background audio services [1].

⚠️ Disclaimer: This project is strictly for personal, educational use [1]. It does not comply with YouTube's official developer terms regarding background playback and is not intended for commercial distribution [1].

## Features

* Playlist Syncer: Fetches video titles, thumbnails, and structures from any public YouTube playlist ID using the official data API [1].
* Background Playback: Keeps the audio stream playing seamlessly even when the app is minimized or the device screen is turned off [1].
* Media Controls: Integrates with native lock screen/notification widgets to let you play, pause, and skip tracks easily [1].

## Tech Stack & Skills Learned


* API Integration: Learned how to fetch JSON payloads, handle API keys securely, and manage daily quota limits using YouTube Data API v3 [1].
* Background Services: Handled mobile OS power-saving limits to keep processes running while the screen is asleep [1].
* Stream Extraction: Integrated local scraping utilities to extract direct audio-only channels from video source links [1].


when the app is openned on your android phonet locally, you will need:
. A public YouTube Playlist ID (found in the playlist URL after ?list=) [1].


------------------------------
## Pro-Tip for Your Portfolio
When tech recruiters look at your GitHub, they love seeing a section titled "Challenges I Faced & How I Overcame Them."
Once you get your app up and running, what specific aspect of the development process would you like to tackle next? We can map out the logic for fetching the data or focus on setting up the background audio service.



## Platform
mobile

## Architecture
hexagonal-architecture

## Phases
- Initialization: Set up project foundation and development environment
- Architecture Setup: Establish project architecture and core infrastructure
- Data Layer: Implement data storage, retrieval, and management
- Business Logic: Implement core business logic and feature functionality
- Interface Layer: Build user interface and user-facing features

## Stack Recommendations
[
  {
    "category": "framework",
    "options": [
      {
        "name": "React Native",
        "reason": "Cross-platform, large community, code reuse"
      },
      {
        "name": "Flutter",
        "reason": "Excellent performance, single codebase, Material Design"
      },
      {
        "name": "Swift (iOS) / Kotlin (Android)",
        "reason": "Native performance, platform-specific features"
      }
    ]
  },
  {
    "category": "backend",
    "options": [
      {
        "name": "Firebase",
        "reason": "BAAS, real-time sync, auth included"
      },
      {
        "name": "Node.js + Express",
        "reason": "Full-stack JS, scalable"
      },
      {
        "name": "Python + FastAPI",
        "reason": "Type-safe, async-native"
      }
    ]
  },
  {
    "category": "database",
    "options": [
      {
        "name": "SQLite",
        "reason": "Embedded, zero-config, ideal for mobile"
      },
      {
        "name": "Firebase Firestore",
        "reason": "Real-time sync, offline support"
      },
      {
        "name": "Supabase",
        "reason": "PostgreSQL-based, real-time capabilities"
      }
    ]
  }
]

## Deferred Decisions
[
  {
    "field": "backend",
    "reason": "No backend preference specified",
    "options": [
      "node.js",
      "python",
      "java",
      "go",
      "firebase"
    ],
    "status": "pending",
    "suggested": null
  },
  {
    "field": "database",
    "reason": "No database preference specified",
    "options": [
      "postgresql",
      "mongodb",
      "sqlite",
      "mysql",
      "firebase"
    ],
    "status": "pending",
    "suggested": "sqlite"
  }
]

## Rules
All projects must follow sequential phase execution
No feature is added outside blueprint scope
Unknown values must become deferred_resolution nodes
All decisions must be logged in project memory
Export always reflects current blueprint state
