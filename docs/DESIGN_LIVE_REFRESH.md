# Feature Design: Live Refresh for Foundation Projects

## Problem Statement

The Foundation tab (Apache/Eclipse) displays pre-computed data imported from a static Zenodo dataset. This data is a frozen research artifact — there is no pipeline, cron job, or automation keeping it current. Projects like Apache Airflow or Eclipse Jetty have evolved significantly since the dataset was published, but OSSPREY shows stale metrics.

Meanwhile, the tool already has a working live pipeline (Rust scraper → Pex Forecaster → ReACT) that can process any GitHub repo on demand. There is no technical reason Foundation projects can't use this same pipeline to get fresh data.

### Current State

| Path | Data Source | Freshness |
|---|---|---|
| Custom URL (GitHub tab) | Live scraper → CSV → ML pipeline | Real-time (on demand) |
| Foundation tab (Apache) | Static Zenodo import → MongoDB | Frozen (months/years old) |
| Foundation tab (Eclipse) | Static Zenodo import → MongoDB | Frozen (months/years old) |

### Zenodo Data Inventory

The Zenodo dataset contains pre-computed results for **260 Apache** and **272 Eclipse** projects across 18 MongoDB collections. The `github_repositories` collection already stores the GitHub URL for each project (e.g., `https://github.com/apache/zookeeper`).

---

## Proposed Solution

Add a **"Refresh Data"** button to Foundation project views that re-runs the live pipeline for that project's GitHub URL, replacing the stale Zenodo data with fresh results.

### User Flow

1. User selects "Apache" → "Airflow" from the Foundation tab
2. Dashboard shows stale data with a banner: **"Data last updated: Jan 2024 (Zenodo import). [🔄 Refresh with live data]"**
3. User clicks Refresh
4. Backend looks up `https://github.com/apache/airflow` from `github_repositories` collection
5. Runs the normal pipeline: scraper → forecast → ReACT
6. Updates the MongoDB collections (`grad_forecast`, `tech_net`, `social_net`, etc.) with fresh results
7. Dashboard updates with current data
8. Banner changes to: **"Data last updated: Mar 29, 2026 (live scrape)"**

### Backend Changes

#### New Endpoint

```
POST /api/refresh_project/<project_id>
```

**Logic:**
1. Look up the GitHub URL from `github_repositories` collection
2. Call the existing `orchestrator.run_pipeline(github_url)` — same code path as custom URLs
3. Write the results back to the **same MongoDB collections** the Zenodo data lives in, keyed by `project_id`
4. Add a `last_refreshed` timestamp to distinguish live vs. static data

**Response:**
```json
{
  "project_id": "airflow",
  "github_url": "https://github.com/apache/airflow",
  "status": "success",
  "last_refreshed": "2026-03-29T22:00:00Z",
  "forecast_months": 120,
  "data_source": "live_scrape"
}
```

#### Data Source Tracking

Add a `data_source` field to `grad_forecast` and related collections:

| Value | Meaning |
|---|---|
| `zenodo_import` | Original static data from Zenodo (default for all existing docs) |
| `live_scrape` | Freshly computed from the pipeline |

```python
# When importing Zenodo data, tag it:
doc["data_source"] = "zenodo_import"
doc["last_refreshed"] = import_date

# When refreshing live, update the tag:
doc["data_source"] = "live_scrape"
doc["last_refreshed"] = datetime.utcnow()
```

### Frontend Changes

#### Freshness Banner

Add a banner to the dashboard when a Foundation project is selected:

```
┌──────────────────────────────────────────────────────────────┐
│  ⚠ Data from Zenodo import (Jan 2024)                       │
│  This data may be outdated. [🔄 Refresh with live data]      │
└──────────────────────────────────────────────────────────────┘
```

After refresh:

```
┌──────────────────────────────────────────────────────────────┐
│  ✅ Live data (Mar 29, 2026)              [🔄 Refresh again]  │
└──────────────────────────────────────────────────────────────┘
```

#### Loading State

Since the pipeline takes 1–5 minutes for large repos:
- Show a progress indicator with estimated time
- Disable the Refresh button during processing
- Allow the user to keep browsing stale data while the refresh runs in the background

---

## Batch Refresh (Future)

For a production deployment, consider a scheduled batch job that refreshes all 532 Foundation projects periodically:

```bash
# Refresh all Apache projects (could run weekly via cron)
for project_id in $(mongo_query "db.github_repositories.distinct('name')"); do
  curl -X POST http://localhost:5001/api/refresh_project/$project_id
  sleep 60  # Rate limit: ~1 project/minute to avoid GitHub API limits
done
```

At ~1 project/minute with 4 GitHub tokens (20,000 requests/hour total), a full refresh of 532 projects would take ~9 hours. A weekly cron job could handle this overnight.

**This is not part of v1.** The manual Refresh button is sufficient to start.

---

## Missing GitHub URLs

Some Foundation projects may not have a GitHub URL in the `github_repositories` collection, or the URL may be outdated (repo moved/renamed). Handle gracefully:

| Case | Handling |
|---|---|
| No GitHub URL found | Disable Refresh button, show "No GitHub URL available for this project" |
| URL returns 404 | Show error "Repository not found. It may have been moved or deleted." |
| Private repo | Show error "Repository is private. A GitHub token with access is required." |
| Rate limited | Show "GitHub API rate limit reached. Try again in X minutes." |

---

## Files Changed

| Repo | File | Change Type | Description |
|---|---|---|---|
| BackEnd | `app/routes.py` | Modify | Add `POST /api/refresh_project/<project_id>` |
| BackEnd | `app/pipeline/orchestrator.py` | Modify | Add option to write results back to MongoDB (currently returns JSON) |
| FrontEnd | `src/pages/dashboard.vue` | Modify | Add freshness banner component |
| FrontEnd | `src/views/dashboard/FreshnessBanner.vue` | **New** | Banner showing data source + refresh button |
| FrontEnd | `src/stores/projectStore.js` | Modify | Add `refreshProject()` action |

---

## Relationship to Other Features

- **Developer Activity Timeline:** Once Foundation projects can be refreshed with live data, the Developer Activity panel can also work for them (it reads from the same scraper CSV).
- **ReACT Enhancements:** Fresh data means the ReACT recommendations would be based on current metrics, not stale snapshots.

---

## Testing

| Test | Type | Description |
|---|---|---|
| Refresh button triggers pipeline | Integration | Select Apache project → click Refresh → verify new data in MongoDB |
| Stale data banner appears | Manual | Select Foundation project → verify banner shows Zenodo date |
| Live data banner after refresh | Manual | After refresh → verify banner shows current date |
| Missing URL handled | Unit | Project with no GitHub URL → Refresh button disabled |
| Large repo timeout | Integration | Refresh a large project (e.g., Apache Spark) → verify doesn't crash |
