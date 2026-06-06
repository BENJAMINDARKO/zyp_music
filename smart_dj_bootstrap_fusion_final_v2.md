# Specification: Asymmetrical Liked-Song Affinity Fusion with Linear Decay, Row Caching, & Clean Isolate Serialization

## Objective
Implement an asymmetrical data fusion pipeline inside `AutoDjRoutingService` that leverages the local `liked_songs` SQLite data tables to bootstrap the Smart DJ's Markov Chain transition algorithm. The system must utilize a smooth linear decay to phase out the affinity bias, implement a cached write-invalidation tracker bound to the explicit history logging database call site, handle incomplete or null genre fields defensively, and ensure thread safety across the background Isolate boundary through raw data serialization.

## Strict Constraints (Read Carefully)
1. **Targeted Service Isolation Only:** This task must ONLY modify data computation passes within `auto_dj_routing_service.dart` and cache initialization wrappers in `PlayerProvider`.
2. **Zero UI Touch Policy:** Do NOT alter presentation widgets, control panels, button configurations, layout dimensions, or the monochrome visual theme.
3. **No New Thread Overhead:** Do not instantiate duplicate background tickers or periodic streams. Leverage the existing position stream listener architecture exclusively.

---

## 1. Authoritative Engineering Rules

### A. Linear Decay Matrix Interpolation
To eliminate abrupt, jarring changes in playback character, the blend ratio between Live Transitions ($M_{real}$) and Liked Affinity ($L_{affinity}$) must glide gracefully across a rolling linear transition window from $H = 0$ up to $H = 150$ tracks.

* **The Formula:** The dynamic Liked Song bias weight ($\beta$) is calculated on every curation cycle using the following linear function bounded by the cached live history count ($H$):

$$\beta = \max\left(0.0, \, 0.6 \cdot \left(1.0 - \frac{H}{150}\right)\right)$$

* **The Transition Step Execution:** * At $H = 0$ (Absolute Cold Start), the ratio scales to **60% Liked Affinity ($\beta = 0.6$) / 40% Live Transition ($1 - \beta = 0.4$)**.
  * At $H = 75$ (Midway Point), the ratio slides perfectly to **30% Liked Affinity ($\beta = 0.3$) / 70% Live Transition ($1 - \beta = 0.7$)**.
  * At $H \ge 150$ (Fully Matured), the ratio stabilizes completely to **0% Liked Affinity ($\beta = 0.0$) / 100% Pure Markov Live Sequencing ($1 - \beta = 1.0$)**, gracefully completing the bootstrapping lifecycle.

### B. Determined Call-Site Cache Invalidation (Performance Guard)
* **The Rule:** The engine must store an internal state integer named `_cachedHistoryCount`.
* **The Optimization Flow:** 1. On initial application boot, `_cachedHistoryCount` is populated once via a background asynchronous database query.
  2. The `buildTransitionProbabilities()` engine pass must read this local memory variable directly—never issue raw database queries during lookahead track evaluation cycles.
  3. **The Invalidation Audit:** The agent must explicitly locate the exact function block where the app calls `database.insert()` or `historyRepository.logTrack()` to commit a row to the `dj_listening_history` table. **Do not assume an 80% callback listener exists.** Increment the variable (`_cachedHistoryCount++`) directly inside the successful completion closure block of that *existing* database operation, regardless of whether it executes at a time checkpoint or at absolute song termination.

### C. Deterministic Metadata Affinity Scoring ($L_{affinity}$) with Null-Genre Defensiveness
To ensure predictable matching weights even when evaluating tracks with incomplete metadata, the affinity profile matrix must be calculated using a strict conditional redistribution architecture:

* **The Database Query Strategy:** On application startup, asynchronously query the `liked_songs` table using an aggregate grouping count query (`GROUP BY artist ORDER BY COUNT(*) DESC LIMIT 5`) to isolate the user's **Top 5 Most Liked Artists** and **Top 5 Most Liked Genres** strings into local memory caches.
* **The Normal Intersection Matrix (Valid Metadata Present):**
  * **Artist Match (Weight = 0.6):** If the candidate track's primary artist string matches one of your Top 5 Liked Artists, award `0.6`. Otherwise, award `0.0`.
  * **Genre Match (Weight = 0.4):** If the candidate track's genre matches one of your Top 5 Liked Genres, award `0.4`. Otherwise, award `0.0`.
  * **The Combined Sum:** $L_{affinity} = \text{Artist Score} + \text{Genre Score}$.
* **The Defensive Null-Genre Guard:** * If a candidate track's genre parameter reads as `null`, empty, or `"Unknown"`, the engine is strictly forbidden from evaluating a static 0.0 genre match. 
  * Instead, **reallocate the missing genre weight completely to the artist component**. If the track's artist matches your Top 5 Liked Artists list, award a perfect affinity score ($L_{affinity} = 1.0$); if the artist does not match, award `0.0`. This ensures tracks with partial metadata are not mathematically penalized.

### D. Isolated Thread Serialization Boundary (Dart `compute` Isolate Contract)
To prevent severe runtime exceptions, no live database repository references, object pointers, or complex state models are permitted to cross the isolate boundary loop.

* **The Rule:** All heavy dataset combinations, decay weight multiplications, and string intersections must execute on a background isolate thread using Dart’s standard **`compute` function execution wrapper**.
* **The Boundary Constraint:** You must strictly serialize the input payloads into primitive data parameters before sending them to the compute isolate. Pass only raw, flat structures across the barrier—specifically, **`List<String>` representation arrays for your top artists/genres** and a decoupled **`Map<String, dynamic>` key-value dataset for your next-track candidates**. Reconstruct your core Dart data models cleanly inside the isolate block before processing calculations.

---

## 2. AI Agent Implementation Checklist

1. **Audit Database Call Sites:** Locate the exact function handling row writes into `dj_listening_history`. Place the `_cachedHistoryCount++` indicator right in its successful database resolution wrapper.
2. **Deploy the Asymmetric Entry Guard:** Open `auto_dj_routing_service.dart`. Implement the linear decay scaling weight and the defensive null-genre reallocation parameters verbatim.
3. **Enforce Isolate Prim-Serialization:** Wrap your matrix logic passes inside a clean `compute()` background isolate block, ensuring only serialized primitive collections travel across the thread execution lanes to eliminate thread state errors completely.
