# Feature Design: Project Selector Redesign

## Problem Statement

The current Project Selector has critical UX issues:

1. **Can't type and search** — uses `VSelect` (dropdown) instead of `VAutocomplete` (searchable), so users can't type a project name to filter
2. **Only 3 hardcoded repos** — EvidenceBot, ReACTive, APEX (the researchers' own repos)
3. **Custom URL buried** — "Try a Different GitHub Repo" is the 4th item in the dropdown, easy to miss
4. **Two-step process** — must select "Try a Different GitHub Repo" first, then a text field appears
5. **Foundation tab hidden** — the Foundation/GitHub toggle is commented out, so users can't browse 532 pre-loaded projects at all

### Current Behavior

```
┌─ Project Selector ──────────────────────┐
│                                          │
│  GitHub Repository URL          [▼]      │
│  ┌────────────────────────────────────┐  │
│  │ https://github.com/Nafiz43/Evid.. │  │
│  │ https://github.com/Nafiz43/ReAC.. │  │
│  │ https://github.com/ossustain/APEX │  │
│  │ Try a Different GitHub Repo       │  │
│  └────────────────────────────────────┘  │
│                                          │
│  [ Process Repository ]                  │
└──────────────────────────────────────────┘
```

---

## Proposed Design

Replace the dropdown with a **single text input** that accepts any GitHub URL directly. Add a history of previously processed repos. Restore the Foundation tab as a secondary option.

### New Layout

```
┌─ Project Selector ──────────────────────────────────────┐
│                                                          │
│  [GitHub URL]  [Foundation ▾]                             │
│                                                          │
│  ┌────────────────────────────────────────────────┐      │
│  │ https://github.com/opencloud-eu/opencloud      │      │
│  └────────────────────────────────────────────────┘      │
│  [ Process Repository ]                                  │
│                                                          │
│  Recent:                                                 │
│  • opencloud-eu/opencloud (Mar 29)      [Load]           │
│  • Nafiz43/EvidenceBot (Mar 28)         [Load]           │
│                                                          │
│  ──── Month Slider ────────────────────── 80 ──          │
│  Adjust the timeline to view forecasts for a month.      │
│                                                          │
│  Stars: 5,026  Forks: 173  License: Apache-2.0          │
└──────────────────────────────────────────────────────────┘
```

---

## Changes

### 1. Replace Dropdown with Text Input (Primary)

**Remove:**
```javascript
const repoOptions = [
  { title: 'https://github.com/Nafiz43/EvidenceBot', ... },
  { title: 'https://github.com/Nafiz43/ReACTive', ... },
  { title: 'https://github.com/ossustain/APEX', ... },
  { title: 'Try a Different GitHub Repo', value: 'custom' }
];
```

**Replace with:**
```html
<VTextField
  v-model="githubRepoLink"
  label="GitHub Repository URL"
  placeholder="https://github.com/owner/repo"
  prepend-inner-icon="mdi-github"
  clearable
  outlined
  dense
  @keyup.enter="uploadRepoLink"
/>
<VBtn color="primary" :loading="repoUploading" :disabled="!githubRepoLink" @click="uploadRepoLink" block>
  Process Repository
</VBtn>
```

**Key improvements:**
- Direct text input — no dropdown step
- Enter key submits (power users)
- Loading state on button during processing
- Button disabled when input is empty (not a separate `buttonDisabled` ref)
- GitHub icon in the input field

### 2. Recently Processed Repos

Show repos the user has previously processed, stored in the backend via `userRepos`. The endpoint `/api/user_repositories` already exists.

```html
<div v-if="userRepos.length" class="mt-3">
  <div class="text-caption text-medium-emphasis mb-1">Recently processed:</div>
  <VChipGroup>
    <VChip
      v-for="repo in userRepos"
      :key="repo"
      size="small"
      variant="outlined"
      @click="loadPreviousRepo(repo)"
    >
      {{ formatRepoName(repo) }}
    </VChip>
  </VChipGroup>
</div>
```

**`formatRepoName()`** extracts `owner/repo` from the full URL for compact display.

**`loadPreviousRepo(repo)`** sets `githubRepoLink` to the URL and calls `uploadRepoLink()` — since the data is cached, it returns instantly.

### 3. Restore Foundation Tab (Secondary)

Uncomment the Foundation/GitHub toggle (lines 14-27 in current code) and restyle as a subtle tab or segmented control:

```html
<VBtnToggle v-model="selectedDataSource" mandatory density="compact" class="mb-3">
  <VBtn value="local" size="small">GitHub URL</VBtn>
  <VBtn value="foundation" size="small">Foundation</VBtn>
</VBtnToggle>
```

When "Foundation" is selected, show the existing `VAutocomplete` for Apache/Eclipse projects (already implemented but hidden behind the commented-out block).

### 4. Metadata Display

After processing, show project metadata inline (currently shown in a separate `ProjectDetails` component but useful here too):

```html
<div v-if="projectStore.localMetadata" class="metrics-row mt-2">
  <VChip size="small" prepend-icon="mdi-star">{{ projectStore.localMetadata.stars }}</VChip>
  <VChip size="small" prepend-icon="mdi-source-fork">{{ projectStore.localMetadata.forks }}</VChip>
  <VChip size="small" prepend-icon="mdi-scale-balance">{{ projectStore.localMetadata.license }}</VChip>
</div>
```

### 5. Remove Alert Dialogs

Replace `alert()` calls (lines 375, 383, 392, 395, 407) with inline Vuetify feedback:

| Current | Replacement |
|---|---|
| `alert('Please enter a Git Repository URL.')` | Input validation error state |
| `alert('Please enter a valid GitHub repository URL...')` | Input rules prop with validation |
| `alert("Error: " + response.error)` | `VAlert` component below input |
| `alert("Repository link uploaded successfully!")` | Success state → show results |
| `alert("Failed to upload repository link.")` | `VAlert` error below input |

---

## Files Changed

| Repo | File | Change Type | Description |
|---|---|---|---|
| FrontEnd | `src/views/dashboard/ProjectSelector.vue` | Modify | Replace dropdown with text input, add recent repos, restore Foundation tab |

This is a **frontend-only change** — no backend modifications needed.

---

## Edge Cases

| Case | Handling |
|---|---|
| User pastes URL with trailing slash | Already handled (store normalizes) |
| User pastes non-GitHub URL | Show inline validation error: "Only GitHub URLs are supported" |
| User pastes URL without `https://` | Auto-prepend `https://` if starts with `github.com/` |
| No previously processed repos | Hide "Recently processed" section |
| Processing takes > 30 seconds | Show progress message: "Scraping repository... this may take a few minutes for large projects" |
| Backend returns error | Show `VAlert` with error message, keep input populated for retry |

---

## Testing

### Unit Tests

**File:** `OSSPREY-FrontEnd-Server/tests/projectSelector.test.js`

```javascript
import { describe, it, expect } from 'vitest';

// --- URL Validation ---

const isValidGithubUrl = (url) => {
  const normalized = url.trim().toLowerCase();
  return /^https:\/\/github\.com\/[a-z0-9._-]+\/[a-z0-9._-]+/i.test(normalized);
};

describe('GitHub URL validation', () => {
  it('accepts standard GitHub URL', () => {
    expect(isValidGithubUrl('https://github.com/opencloud-eu/opencloud')).toBe(true);
  });

  it('accepts URL with .git suffix', () => {
    expect(isValidGithubUrl('https://github.com/opencloud-eu/opencloud.git')).toBe(true);
  });

  it('accepts URL with trailing slash', () => {
    expect(isValidGithubUrl('https://github.com/apache/airflow/')).toBe(true);
  });

  it('rejects non-GitHub URL', () => {
    expect(isValidGithubUrl('https://gitlab.com/user/repo')).toBe(false);
  });

  it('rejects bare domain', () => {
    expect(isValidGithubUrl('github.com/user/repo')).toBe(false);
  });

  it('rejects GitHub URL without repo name', () => {
    expect(isValidGithubUrl('https://github.com/opencloud-eu')).toBe(false);
  });

  it('rejects empty string', () => {
    expect(isValidGithubUrl('')).toBe(false);
  });

  it('rejects random text', () => {
    expect(isValidGithubUrl('not a url at all')).toBe(false);
  });
});

// --- formatRepoName ---

const formatRepoName = (url) => {
  const match = url.match(/github\.com\/([^/]+\/[^/.]+)/);
  return match ? match[1] : url;
};

describe('formatRepoName', () => {
  it('extracts owner/repo from full URL', () => {
    expect(formatRepoName('https://github.com/opencloud-eu/opencloud')).toBe('opencloud-eu/opencloud');
  });

  it('handles .git suffix', () => {
    expect(formatRepoName('https://github.com/apache/airflow.git')).toBe('apache/airflow');
  });

  it('handles trailing slash', () => {
    expect(formatRepoName('https://github.com/user/repo/')).toBe('user/repo');
  });

  it('returns original string if no match', () => {
    expect(formatRepoName('not-a-url')).toBe('not-a-url');
  });
});

// --- URL auto-normalization ---

const normalizeUrl = (input) => {
  let url = input.trim();
  if (url.startsWith('github.com/')) url = 'https://' + url;
  if (url.endsWith('/')) url = url.slice(0, -1);
  if (url.startsWith('https://github.com/') && !url.endsWith('.git')) url += '.git';
  return url;
};

describe('URL auto-normalization', () => {
  it('adds https:// when missing', () => {
    expect(normalizeUrl('github.com/user/repo')).toBe('https://github.com/user/repo.git');
  });

  it('removes trailing slash', () => {
    expect(normalizeUrl('https://github.com/user/repo/')).toBe('https://github.com/user/repo.git');
  });

  it('adds .git suffix when missing', () => {
    expect(normalizeUrl('https://github.com/user/repo')).toBe('https://github.com/user/repo.git');
  });

  it('leaves .git suffix alone', () => {
    expect(normalizeUrl('https://github.com/user/repo.git')).toBe('https://github.com/user/repo.git');
  });
});
```

### Smoke Tests

**Add to `smoke_test.sh`:**

```bash
# --- Project Selector API ---

# Test: user_repositories endpoint returns valid JSON
echo -n "  user_repositories endpoint... "
RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5001/api/user_repositories?email=test@example.com)
if [ "$RESP" = "200" ]; then
  echo "PASS"
else
  echo "FAIL (HTTP $RESP)"
fi

# Test: upload_git_link accepts valid URL
echo -n "  upload_git_link accepts valid URL... "
RESP=$(curl -s -X POST http://localhost:5001/api/upload_git_link \
  -H "Content-Type: application/json" \
  -d '{"git_link": "https://github.com/Nafiz43/EvidenceBot.git"}' \
  -o /dev/null -w "%{http_code}")
if [ "$RESP" = "200" ]; then
  echo "PASS"
else
  echo "FAIL (HTTP $RESP)"
fi

# Test: upload_git_link rejects invalid URL
echo -n "  upload_git_link rejects invalid URL... "
RESP=$(curl -s -X POST http://localhost:5001/api/upload_git_link \
  -H "Content-Type: application/json" \
  -d '{"git_link": "not-a-url"}' \
  -o /dev/null -w "%{http_code}")
if [ "$RESP" = "400" ] || [ "$RESP" = "422" ]; then
  echo "PASS"
else
  echo "WARN (HTTP $RESP — server may not validate URLs yet)"
fi
```

### E2E Browser Tests

These tests verify the full user-facing flow in the browser.

**Test 1: Direct URL submission**
```
1. Navigate to http://localhost:3000/dashboard
2. Locate the text input with placeholder "https://github.com/owner/repo"
3. Type "https://github.com/Nafiz43/EvidenceBot"
4. Click "Process Repository" button
5. Verify: button shows loading spinner
6. Wait for response (up to 5 minutes)
7. Verify: month slider appears
8. Verify: Graduation Forecast chart renders with data
9. Verify: no alert() dialog was shown
```

**Test 2: Enter key submission**
```
1. Navigate to http://localhost:3000/dashboard
2. Click the URL text input
3. Type "https://github.com/Nafiz43/EvidenceBot"
4. Press Enter key
5. Verify: pipeline processing starts (same as clicking button)
```

**Test 3: Invalid URL shows inline error**
```
1. Navigate to http://localhost:3000/dashboard
2. Type "https://gitlab.com/user/repo" in the URL input
3. Click "Process Repository"
4. Verify: inline error message appears (not an alert() dialog)
5. Verify: error says "Only GitHub URLs are supported" or similar
6. Verify: input field retains the typed URL
```

**Test 4: Empty input disables button**
```
1. Navigate to http://localhost:3000/dashboard
2. Verify: "Process Repository" button is disabled
3. Type any text in the URL input
4. Verify: button becomes enabled
5. Clear the input
6. Verify: button is disabled again
```

**Test 5: Recent repos appear and work**
```
1. Process a repo via the URL input (e.g., EvidenceBot)
2. Refresh the page
3. Verify: "Recently processed" section appears
4. Verify: chip shows "Nafiz43/EvidenceBot" (not the full URL)
5. Click the chip
6. Verify: dashboard loads instantly with cached data
7. Verify: month slider and forecast chart appear
```

**Test 6: Foundation tab loads Apache projects**
```
1. Navigate to http://localhost:3000/dashboard
2. Click the "Foundation" tab/toggle
3. Verify: Foundation dropdown appears with "Apache" selected
4. Verify: project autocomplete shows searchable list
5. Type "air" in the autocomplete
6. Verify: "Airflow" (or similar) appears in filtered results
7. Select a project
8. Verify: forecast chart renders
```

**Test 7: Loading state during long processing**
```
1. Navigate to http://localhost:3000/dashboard
2. Enter a large repo URL (e.g., https://github.com/apache/spark)
3. Click "Process Repository"
4. Verify: button shows loading spinner
5. Verify: button is not clickable during processing
6. Verify: progress message appears ("Scraping repository...")
7. Wait for completion or cancel
```

**Test 8: Backend error displays inline**
```
1. Navigate to http://localhost:3000/dashboard
2. Enter a URL for a private/nonexistent repo
3. Click "Process Repository"
4. Verify: error is shown as a VAlert below the input (not alert() dialog)
5. Verify: input field retains the URL for easy editing
6. Verify: button re-enables for retry
```
