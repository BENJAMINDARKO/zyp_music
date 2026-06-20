import re

with open('lib/presentation/providers/player_provider.dart', 'r') as f:
    content = f.read()

# Replace _autoDJMode variable definition
content = content.replace('AutoDJMode _autoDJMode = AutoDJMode.off;', 'AutoDJMode _baseAutoDJMode = AutoDJMode.off;\n  AutoDJMode _smartAutoDJMode = AutoDJMode.off;')

# Replace the resolver check
content = content.replace('if (_autoDJMode != AutoDJMode.off) {', 'if (_baseAutoDJMode != AutoDJMode.off || _smartAutoDJMode != AutoDJMode.off) {')
content = content.replace('\'nextTrackResolver: resolved via Auto DJ mode=${_autoDJMode.name}: ${nextTrack.id} ("${nextTrack.title}")\',', '\'nextTrackResolver: resolved via Auto DJ base=${_baseAutoDJMode.name} smart=${_smartAutoDJMode.name}: ${nextTrack.id} ("${nextTrack.title}")\',')

# Replace DSP engine toggle
content = content.replace('engine.setActive(_autoDJMode == AutoDJMode.smartDj || _autoDJMode == AutoDJMode.vibeMatch);', 'engine.setActive(_smartAutoDJMode == AutoDJMode.smartDj || _smartAutoDJMode == AutoDJMode.vibeMatch);')

# Replace getters
content = content.replace('AutoDJMode get autoDJMode => _autoDJMode;', 'AutoDJMode get baseAutoDJMode => _baseAutoDJMode;\n  AutoDJMode get smartAutoDJMode => _smartAutoDJMode;\n  QueueManager? get queueManager => _queueManager;')

# Replace setAutoDJMode
old_set_auto_dj = """  Future<ColdStartResult> setAutoDJMode(AutoDJMode mode) async {
    if (_autoDJMode == mode) return ColdStartResult.skipped;
    _autoDJMode = mode;
    debugPrint('setAutoDJMode: ${mode.label}');
    // Mirror the change into the legacy visual flag so the icons
    // light up. The QueueManager owns the actual `_isAutoDJEnabled`
    // backing field; calling enable/disable is the supported way to
    // mutate it from outside the class.
    if (mode.isActive) {
      _queueManager?.enableAutoDJ();
      _repeatMode = repeat.PlaybackRepeatMode.none;
    } else {
      _queueManager?.disableAutoDJ();
    }
    // Phase 2: tell the QueueManager which mode was selected BEFORE the
    // warm-up fires. This is critical: _warmUpNewMode calls
    // generateNextAutoDJTrack which reads _currentMode from the manager.
    // Setting it after would mean the warm-up always resolves via the
    // previous mode's strategy, defeating the purpose of the mode switch.
    _queueManager?.setCurrentMode(mode);
    // Phase 5: flip the DSP engine gate. Smart DJ is the
    // ONLY mode that unlocks the multi-decoder crossfade
    // pipeline; the other four active modes (Shuffle
    // Library, Similar Songs, Same Genre, Same Artist) use
    // the mixer's plain gapless handoff with no second
    // decoder.
    _dspEngine?.setActive(mode == AutoDJMode.smartDj || mode == AutoDJMode.vibeMatch);
    notifyListeners();
    // Armed Standby: when the player is idle (no current track,
    // no queued items) and the user selects a non-off mode, the
    // player enters a "standby" state. No initial smart-score
    // sweeps, no fallback tokens are generated. The mode tile
    // remains visually highlighted. The engine activates on the
    // first manual song selection via [setQueue].
    if (mode != AutoDJMode.off && _isColdIdle) {
      _isArmedStandby = true;
      AppLogger.log(
        '[AutoDJEngine] Entering Armed Standby for mode=${mode.label}. '
        'Waiting for explicit user track choice before activating lookahead.',
        name: 'PlayerProvider',
      );
      return ColdStartResult.armedStandby;
    }
    // Clear standby when the user explicitly switches to off mode
    // while in the idle state.
    if (mode == AutoDJMode.off && _isArmedStandby) {
      _isArmedStandby = false;
    }
    // Bugfix (atomic queue switching): when the user changes
    // mode mid-track we do NOT flush the preloaded timeline.
    // The existing items remain as an emergency buffer; a
    // background warm-up pre-resolves a candidate via the
    // newly-selected algorithm and verifies its URI token
    // before the next 15s-lookahead trigger trusts the new
    // mode's output.
    if (mode != AutoDJMode.off && _currentTrack != null) {
      unawaited(_warmUpNewMode(mode, currentTrack: _currentTrack!));
    }
    return ColdStartResult.skipped;
  }"""

new_set_auto_dj = """  Future<ColdStartResult> setBaseAutoDJMode(AutoDJMode mode) async {
    if (_baseAutoDJMode == mode) return ColdStartResult.skipped;
    _baseAutoDJMode = mode;
    return _applyAutoDJModeChanges(mode);
  }

  Future<ColdStartResult> setSmartAutoDJMode(AutoDJMode mode) async {
    if (_smartAutoDJMode == mode) return ColdStartResult.skipped;
    _smartAutoDJMode = mode;
    return _applyAutoDJModeChanges(mode);
  }

  Future<ColdStartResult> _applyAutoDJModeChanges(AutoDJMode triggeredMode) async {
    debugPrint('applyAutoDJModeChanges: base=${_baseAutoDJMode.label} smart=${_smartAutoDJMode.label}');
    final isActive = _baseAutoDJMode != AutoDJMode.off || _smartAutoDJMode != AutoDJMode.off;
    
    if (isActive) {
      _queueManager?.enableAutoDJ();
      _repeatMode = repeat.PlaybackRepeatMode.none;
    } else {
      _queueManager?.disableAutoDJ();
    }
    
    _queueManager?.setCurrentModes(_baseAutoDJMode, _smartAutoDJMode);
    
    _dspEngine?.setActive(_smartAutoDJMode == AutoDJMode.smartDj || _smartAutoDJMode == AutoDJMode.vibeMatch);
    notifyListeners();

    if (isActive && _isColdIdle) {
      _isArmedStandby = true;
      AppLogger.log(
        '[AutoDJEngine] Entering Armed Standby. '
        'Waiting for explicit user track choice before activating lookahead.',
        name: 'PlayerProvider',
      );
      return ColdStartResult.armedStandby;
    }

    if (!isActive && _isArmedStandby) {
      _isArmedStandby = false;
    }

    if (isActive && _currentTrack != null) {
      unawaited(_warmUpNewMode(triggeredMode, currentTrack: _currentTrack!));
    }
    return ColdStartResult.skipped;
  }"""

content = content.replace(old_set_auto_dj, new_set_auto_dj)

# Replace the condition in _warmUpNewMode
content = content.replace('if (_autoDJMode != mode || !manager.isActive) break;', 'if ((_baseAutoDJMode == AutoDJMode.off && _smartAutoDJMode == AutoDJMode.off) || !manager.isActive) break;')

# Replace cycleRepeatMode AutoDJ disable
old_cycle = """    if (_autoDJMode.isActive) {
      _autoDJMode = AutoDJMode.off;
      _queueManager?.disableAutoDJ();
      _queueManager?.setCurrentMode(AutoDJMode.off);
      _dspEngine?.setActive(false);
    }"""
new_cycle = """    final isActive = _baseAutoDJMode != AutoDJMode.off || _smartAutoDJMode != AutoDJMode.off;
    if (isActive) {
      _baseAutoDJMode = AutoDJMode.off;
      _smartAutoDJMode = AutoDJMode.off;
      _queueManager?.disableAutoDJ();
      _queueManager?.setCurrentModes(AutoDJMode.off, AutoDJMode.off);
      _dspEngine?.setActive(false);
    }"""

content = content.replace(old_cycle, new_cycle)

with open('lib/presentation/providers/player_provider.dart', 'w') as f:
    f.write(content)

