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

| Test | Type | Description |
|---|---|---|
| Text input accepts any GitHub URL | Manual | Type URL → click Process → verify pipeline runs |
| Enter key submits | Manual | Type URL → press Enter → verify submit |
| Recent repos load | Manual | Process 2 repos → refresh → verify chips appear |
| Click recent repo chip | Manual | Click chip → verify instant load from cache |
| Invalid URL shows error | Manual | Type `example.com` → verify inline error |
| Foundation tab works | Manual | Switch to Foundation → select Apache → select project → verify data loads |
| Loading state during processing | Manual | Submit URL → verify button shows spinner → verify button re-enables after response |
