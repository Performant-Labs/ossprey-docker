# Feature Design: Developer Activity Timeline

## Overview

Add a new dashboard panel that shows a per-developer activity table with status classifications (Active, Fading, Inactive), contribution metrics, and file ownership — replacing the current empty/generic "Email Links" panel.

---

## Data Source

The commit CSV (`<project>-commit-file-dev.csv`) is already scraped by the Rust miner and available inside the backend container. It contains all the data needed.

### Available Columns

| Column | Example | Used For |
|---|---|---|
| `name` | Jörn Friedrich Dreyer | Developer identity |
| `email` | jfd@example.com | De-duplication |
| `date` | 2026-03-29 00:15:44 UTC | Last-active, trend |
| `commit_sha` | 94f19e6... | Unique commit count |
| `filename` | pkg/auth/scope.go | File ownership |
| `lines_added` | 42 | Impact sizing |
| `lines_deleted` | 7 | Impact sizing |
| `commit_url` | https://github.com/... | Clickable links |

### Verified Data (OpenCloud)

- **104,750 rows**, **157 unique developers**, dates from 2019–2026
- Top committer: Jörn Friedrich Dreyer (1,306 unique commits)
- The CSV is already mounted at `/opt/ossprey/scraper/output/` in the backend container

### Fork History Detection

The Rust scraper clones the full git history, which for forked repos includes all upstream commits. For example, OpenCloud was forked from ownCloud Infinite Scale (ocis) in January 2025, but the commit CSV contains 15,310 pre-fork commits from 2019–2024 by 144 developers who never contributed to OpenCloud.

**Without filtering, the data is misleading:**

| Scope | Developers | Commits | Date Range |
|---|---|---|---|
| Full history (unfiltered) | 157 | 17,065 | 2019–2026 |
| Post-fork only (OpenCloud) | ~25 | ~1,755 | Jan 2025–present |

**Detection method:** Query the GitHub API for `created_at` and `fork` fields:

```python
# GET https://api.github.com/repos/opencloud-eu/opencloud
{
  "fork": true,
  "created_at": "2025-01-14T08:00:00Z",
  "parent": { "full_name": "owncloud/ocis" }
}
```

If `fork == true`, store `created_at` as the fork boundary date. Default to showing only post-fork data, with a toggle to include the full inherited history.

---

## Backend API

### New Endpoint

```
GET /api/developer_activity/<project_name>?include_fork_history=false
```

| Query Param | Type | Default | Description |
|---|---|---|---|
| `include_fork_history` | bool | `false` | If `true`, include pre-fork commits. If `false` (default), filter to post-fork date only. Has no effect on non-fork repos. |

### Response Schema

```json
{
  "project": "opencloud",
  "generated_at": "2026-03-29T21:34:00Z",
  "is_fork": true,
  "fork_date": "2025-01-14T08:00:00Z",
  "parent_repo": "owncloud/ocis",
  "include_fork_history": false,
  "summary": {
    "total_developers": 25,
    "active": 8,
    "fading": 5,
    "inactive": 12,
    "bus_factor": 3
  },
  "developers": [
    {
      "name": "Jörn Friedrich Dreyer",
      "status": "active",
      "total_commits": 1306,
      "commits_90d": 142,
      "commits_30d": 38,
      "last_commit_date": "2026-03-28",
      "first_commit_date": "2020-01-15",
      "days_since_last_commit": 1,
      "files_owned": 340,
      "lines_added_90d": 5200,
      "lines_deleted_90d": 3100,
      "top_files": ["pkg/auth/scope.go", "pkg/reva/..."],
      "commit_share_pct": 14.2
    }
  ]
}
```

### Status Classification

| Status | Criteria | Color |
|---|---|---|
| 🟢 Active | Last commit < 30 days ago | `#4caf50` |
| 🟡 Fading | Last commit 30–90 days ago | `#ff9800` |
| 🔴 Inactive | Last commit > 90 days ago | `#f44336` |

### Bus Factor Calculation

Minimum number of developers whose combined commit share exceeds 50% of all commits (last 90 days). Computed by sorting developers by 90-day commit count descending and accumulating until > 50%.

### Implementation Location

**File:** `OSSPREY-BackEnd-Server/app/routes.py`

```python
@app.route('/api/developer_activity/<project_name>', methods=['GET'])
def get_developer_activity(project_name):
    csv_path = find_commit_csv(project_name)  # Look in scraper output/
    df = pd.read_csv(csv_path)
    # ... compute per-developer metrics
    return jsonify(result)
```

**Dependencies:** `pandas` (already installed in the container)

---

## Frontend Component

### New File: `DeveloperActivity.vue`

**Location:** `OSSPREY-FrontEnd-Server/src/views/dashboard/DeveloperActivity.vue`

### Panel Layout

```
┌──────────────────────────────────────────────────────────────┐
│  Developer Activity                     [🔄 Refresh] [?]    │
│  Last computed: Mar 29, 2026 at 2:34 PM                      │
│                                                              │
│  ⚠ Forked from owncloud/ocis on Jan 14, 2025                │
│  [✓] Show OpenCloud commits only  [ ] Include fork history   │
│                                     Hide bots: [ON]          │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟢 8 Active   🟡 5 Fading   🔴 12 Inactive   BF: 3   │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────┬────────┬─────────┬──────────┬───────┬───────┐ │
│  │ Developer│ Status │ Commits │ Last     │ Share │ Files │ │
│  │          │        │ (90d)   │ Commit   │  (%)  │ Owned │ │
│  ├──────────┼────────┼─────────┼──────────┼───────┼───────┤ │
│  │ JF Dreyer│ 🟢     │ 142     │ 1d ago   │ 14.2% │ 340   │ │
│  │ M. Barz  │ 🟢     │ 87      │ 3d ago   │ 8.7%  │ 215   │ │
│  │ ...      │ 🟡     │ 12      │ 45d ago  │ 1.2%  │ 28    │ │
│  │ Old Dev  │ 🔴     │ 0       │ 180d ago │ 0.0%  │ 5     │ │
│  └──────────┴────────┴─────────┴──────────┴───────┴───────┘ │
│                                                              │
│  Showing 20 of 25 developers     [Show All] [Active Only]    │
└──────────────────────────────────────────────────────────────┘
```

**Controls:**
- **Fork toggle:** Only visible when `is_fork` is true. Switching re-fetches with `?include_fork_history=true`.
- **Hide bots switch:** `VSwitch` toggled ON by default. Hides accounts matching known bot patterns (`[bot]`, `dependabot`, `renovate`). Filtering is client-side (bot flag comes from the API response).
- **Refresh button:** Re-fetches from the API with `?force_refresh=true`, which recomputes from the CSV and updates the cache.
- **Last computed:** Displays `generated_at` from the cached response. Helps users know if they're looking at stale data.

### Features

1. **Summary bar** — counts of active/fading/inactive + bus factor badge
2. **Sortable table** — click column headers to sort by commits, last active, share %
3. **Filter buttons** — "Active Only", "Show All", "Fading + Inactive"
4. **Row click** — clicking a developer name sets `projectStore.selectedDeveloper`, updating the Commit Links and Email Links panels  
5. **Default pagination** — shows top 20 by commit count, "Show All" expands
6. **Relative dates** — "2d ago", "45d ago" instead of absolute timestamps

### Styling

- Follows existing Vuetify card pattern (`VCard` → `VCardText`)
- Uses existing `DashboardPanelHeader` component for title + tooltip
- Status dots reuse the existing `.bullet` CSS class
- Bus factor badge: red if ≤ 2, yellow if 3–4, green if ≥ 5

---

## Dashboard Integration

### Placement

Insert Developer Activity as a **new full-width row** between the Social/Technical Network row and the Network Node row. All existing panels stay in place.

**File:** `OSSPREY-FrontEnd-Server/src/pages/dashboard.vue`

```diff
      <!-- Fourth Row: Social and Technical Network Cards -->
      <VCol cols="12" md="6">
        <VCard style="height: 400px;"><SocialNetwork /></VCard>
      </VCol>
      <VCol cols="12" md="6">
        <VCard style="height: 400px;"><TechnicalNetwork /></VCard>
      </VCol>
    </VRow>

+   <!-- NEW: Developer Activity Row -->
+   <VRow>
+     <VCol cols="12">
+       <VCard style="height: 500px;">
+         <DeveloperActivity />
+       </VCard>
+     </VCol>
+   </VRow>

    <VRow>
      <VCol cols="6" md="6" sm="6">
        <SocialNetworkNode />
      </VCol>
```

### Store Integration

**File:** `OSSPREY-FrontEnd-Server/src/stores/projectStore.js`

Add:
```javascript
// Developer Activity State
const developerActivityData = ref(null);
const developerActivityLoading = ref(false);
const developerActivityError = ref(null);

const fetchDeveloperActivity = async (projectName) => {
  developerActivityLoading.value = true;
  try {
    const response = await ngrokFetch(
      `${baseUrl.value}/api/developer_activity/${projectName}`
    );
    developerActivityData.value = await response.json();
  } catch (err) {
    developerActivityError.value = err.message;
  } finally {
    developerActivityLoading.value = false;
  }
};
```

Trigger: Call `fetchDeveloperActivity()` when `selectedProject` changes (add to the existing watcher).

---

## Files Changed

| Repo | File | Change Type | Description |
|---|---|---|---|
| BackEnd | `app/routes.py` | Modify | Add `/api/developer_activity/<project_name>` endpoint |
| FrontEnd | `src/views/dashboard/DeveloperActivity.vue` | **New** | Developer activity table component |
| FrontEnd | `src/pages/dashboard.vue` | Modify | Add DeveloperActivity to layout |
| FrontEnd | `src/stores/projectStore.js` | Modify | Add fetch + state for developer activity |

---

## Edge Cases

| Case | Handling |
|---|---|
| No commit CSV found | Return 404 with message "No commit data. Process this repo first." |
| Developer name variations | Group by email as primary key, display most recent `name` |
| Bot accounts (dependabot, renovate, `[bot]`) | Flagged with `is_bot: true` in API response. Hidden by default via "Hide bots" switch. Always excluded from bus factor calculation. |
| Very large repos (>500 devs) | Paginate, default to Active + Fading only |
| Foundation projects (Apache/Eclipse) | **Deferred.** Panel shows "Developer activity is available for GitHub-processed repos only" with a link to process via URL. Foundation data uses a different schema (MongoDB `commit_links`) and will be supported in a future iteration. |
| Forked repos | Auto-detect via GitHub API `fork` field; default to post-fork data only |
| Non-fork repos | Toggle is hidden; all commits shown |
| GitHub API unavailable | Fall back to showing all commits with a note that fork detection failed |
| Cached data exists | Serve from MongoDB cache. Display `generated_at` timestamp in panel header. |
| `?force_refresh=true` | Recompute from CSV, update MongoDB cache, return fresh data |

---

## Testing

| Test | Type | Description |
|---|---|---|
| API returns valid JSON | Smoke test | Add to `smoke_test.sh`: `curl /api/developer_activity/opencloud` |
| Status classification | Unit test | 29d = Active, 30d = Fading, 91d = Inactive |
| Bus factor calculation | Unit test | Known dataset → expected bus factor |
| Sort by column | Manual/E2E | Click "Commits (90d)" header, verify order |
| Row click sets developer | Manual/E2E | Click name → Commit Links panel updates |
| Empty state (no data) | Unit test | Returns helpful message, not crash |

---

## Decisions (Resolved)

| # | Question | Decision |
|---|---|---|
| 1 | Replace or add? | **Add a new full-width row** between Social/Tech Networks and Network Node panels. All existing panels stay. |
| 2 | Foundation projects? | **Deferred.** GitHub-processed repos only for v1. Foundation data uses a different schema and will be added later. |
| 3 | Bot filtering? | **Hidden by default** via a "Hide bots" switch (ON by default). Bots detected by name pattern (`[bot]`, `dependabot`, `renovate`). Always excluded from bus factor. |
| 4 | Caching? | **Cache in MongoDB.** Show `generated_at` timestamp and a Refresh button. `?force_refresh=true` recomputes from CSV. No reason not to cache — the CSV doesn't change until the repo is re-processed. |

### Caching Strategy

**Collection:** `developer_activity` in `decal-db`

```json
{
  "project_name": "opencloud",
  "include_fork_history": false,
  "generated_at": "2026-03-29T21:34:00Z",
  "summary": { "..." },
  "developers": [ "..." ]
}
```

**Cache key:** `(project_name, include_fork_history)` — two separate cache entries for fork/non-fork views.

**Invalidation:** Only when `?force_refresh=true` is passed (user clicks Refresh button), or when the project is re-processed via `upload_git_link`.
