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

---

## Backend API

### New Endpoint

```
GET /api/developer_activity/<project_name>
```

### Response Schema

```json
{
  "project": "opencloud",
  "generated_at": "2026-03-29T21:34:00Z",
  "summary": {
    "total_developers": 157,
    "active": 8,
    "fading": 5,
    "inactive": 144,
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
│  Developer Activity                               [?] tooltip│
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟢 8 Active   🟡 5 Fading   🔴 144 Inactive   BF: 3  │  │
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
│  Showing 20 of 157 developers    [Show All] [Active Only]    │
└──────────────────────────────────────────────────────────────┘
```

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

Replace the **"Email Links" panel** (currently shows "Select A Developer" with no data for GitHub projects) with the new Developer Activity panel.

**File:** `OSSPREY-FrontEnd-Server/src/pages/dashboard.vue`

```diff
 <!-- Fourth Row: Social and Technical Network Cards -->
 ...

-<VCol cols="6" md="6" sm="6">
-  <SocialNetworkNode />
-</VCol>
+<VCol cols="12" md="12" sm="12">
+  <VCard style="height: 400px;">
+    <DeveloperActivity />
+  </VCard>
+</VCol>
+
+<VCol cols="6" md="6" sm="6">
+  <SocialNetworkNode />
+</VCol>
```

> **Decision needed:** Should Developer Activity replace SocialNetworkNode (which shows "Email Links" on the left), or should it be inserted as a new full-width row? The Email Links panel is always empty for GitHub projects, so replacing it seems natural.

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
| Bot accounts (dependabot) | Include in table but tag with 🤖 icon; exclude from bus factor |
| Very large repos (>500 devs) | Paginate, default to Active + Fading only |
| Foundation projects (not local) | API reads from MongoDB `commit_links` collection instead of CSV |

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

## Open Questions

1. **Replace or add?** Should Developer Activity replace the Email Links panel (empty for GitHub projects), or be added as a new row?
2. **Foundation projects:** Should this also work for Apache/Eclipse projects? The data structure is different (MongoDB vs. CSV).
3. **Bot filtering:** Should bots (dependabot, renovate) be hidden by default or shown with a tag?
4. **Caching:** Should the computed activity data be cached in MongoDB, or recomputed each time from the CSV?
