# ReACT Actionables — Enhancement Proposals

## Problem Statement

The current ReACT (Researched Actionables) system displays **generic academic recommendations** rather than **project-specific, data-driven insights**. The actionables panel shows the same advice regardless of whether a project has 3 contributors or 300. The underlying data to power meaningful analysis already exists in the scraped CSVs — it just isn't being used.

### Current Behavior

1. A static JSON file (`react_set.json`) contains ~100 recommendations sourced from research papers
2. The `ReACT_Extractor` checks which network features exist in the project data
3. Matching recommendations are displayed with a "critical/high/medium" label based solely on **how many papers cited them** (not project-specific risk)
4. No project-specific numbers, thresholds, or developer-level details are shown

### User Feedback

> *"This is not even moderately useful."*
>
> 1. It doesn't tell me how many core/active developers it is recognizing
> 2. It doesn't tell me the optimal amount
> 3. It doesn't tell me the consequences of having too many core contributors
> 4. It doesn't show me which core contributors haven't contributed in a while

---

## Proposed Enhancements

### 1. Project-Specific Metrics in Every Recommendation

**Current:** "Maintain a small number of core/active developers." (no numbers)

**Proposed:** "Your project has **15 committers**, but only **3 were active in the last 30 days**. Research suggests a core team of 5–8 active developers provides the best sustainability outcomes."

**Implementation:**
- Extract from commit CSV: unique committers, last-active date per committer, activity distribution
- Inject computed values into the recommendation template at render time
- Define thresholds per recommendation (e.g., "small" = 3–8 based on research)

---

### 2. Developer Activity Timeline

Show a per-developer activity heatmap or timeline:

| Developer | Last Commit | Commits (90d) | Status |
|---|---|---|---|
| Jörn Friedrich Dreyer | 2 days ago | 142 | 🟢 Active |
| Florian Schade | 5 days ago | 87 | 🟢 Active |
| David Christofas | 45 days ago | 12 | 🟡 Fading |
| Former Dev | 180 days ago | 3 | 🔴 Inactive |

**Data source:** Already available in `<project>-commit-file-dev.csv` — contains developer names and commit timestamps.

**Implementation:**
- Parse commit CSV for unique developers + last commit date
- Classify: Active (< 30d), Fading (30–90d), Inactive (> 90d)
- Display as a sortable table or heatmap in the Actionables panel

---

### 3. Bus Factor Analysis

Calculate and display the bus factor — the minimum number of developers who, if they left, would stall the project.

**Metrics to compute:**
- Files touched by only 1 developer (single points of failure)
- Percentage of commits from top N developers (concentration risk)
- Knowledge distribution across the codebase

**Example output:**
> **Bus Factor: 2** — 78% of commits come from the top 2 developers. If Jörn Friedrich Dreyer and Florian Schade left, 340 files would have no active maintainer.

**Data source:** `<project>-commit-file-dev.csv` has developer-file-commit triples.

---

### 4. Trend-Aware Recommendations

Instead of static advice, show trajectory:

> **Contributor Growth: ⚠️ Declining**
> Active contributors dropped from 12 → 8 → 5 over the last 3 months. At this rate, the project will have fewer than 3 active contributors within 60 days.

**Implementation:**
- Compute per-month active developer counts from commit data
- Apply simple trend detection (linear regression or moving average)
- Flag accelerating declines as critical

---

### 5. Consequence Explanations

Each recommendation should explain **what happens if you ignore it**, with quantified risk where possible.

**Current:** "Maintain a small number of core/active developers." [Critical]

**Proposed:**
> **Maintain a small number of core/active developers.** [Critical]
>
> **Why it matters:** Projects with diffuse ownership (no clear core team) are 2.3× more likely to become abandoned within 2 years (Coelho & Valente, 2019). Coordination overhead grows quadratically with team size.
>
> **Your risk:** With 15 committers and no clear core (top contributor has only 21% of commits), decision-making may be fragmented.
>
> **Suggested action:** Identify 3–5 maintainers with merge authority and document ownership areas.

---

### 6. Contextualized Priority Scoring

Replace the current priority system (based on paper citation count) with a computed score based on the project's actual data.

| Factor | Weight | Example |
|---|---|---|
| How far the metric deviates from healthy range | 40% | 15 committers vs ideal 5–8 = high deviation |
| Trend direction (improving/declining) | 30% | Contributor count declining = worse |
| Impact scope (how many files/features affected) | 20% | Bus factor affects 340 files = high |
| Research backing (current system) | 10% | 3 papers cited = minor boost |

---

### 7. Actionable Next Steps

Each recommendation should include concrete, copy-pasteable actions:

> **Suggested actions:**
> - Run `git shortlog -sn --since="90 days ago"` to see recent contributors
> - Create a `MAINTAINERS.md` file listing core team members and their areas
> - Set up CODEOWNERS to enforce review from domain experts
> - Schedule a quarterly "contributor health" review

---

### 8. Social Network from GitHub Data

The social network panel is empty for GitHub-hosted projects because the network builder expects mailing list threading data. GitHub issues use a flat comment model.

**Proposed:** Build an alternative social network from GitHub interactions:
- Issue comment reply chains (commenter → issue author)
- PR review relationships (reviewer → PR author)
- Co-commit patterns (developers who frequently change the same files)
- @mention graphs from issue/PR comments

**Data source:** The issues CSV already contains 60,000+ rows for OpenCloud. Parse `user_login`, `issue_url`, `comment_url`, and `body` (for @mentions) to build edges.

---

### 9. Comparative Benchmarking

Show how the project compares to similar projects in the database:

> **Compared to 260 Apache/Eclipse projects:**
> - Your bus factor (2) is in the **bottom 15%**
> - Your commit frequency (687 in 14 months) is in the **top 30%**
> - Your contributor count (15) is **average**

**Data source:** The Zenodo dataset has metrics for 260+ foundation projects, providing a ready-made benchmark population.

---

### 10. Export & Reporting

Add the ability to export the analysis as a standalone report:
- PDF/Markdown export of all panels
- Embeddable health badge (like CI badges) for README files
- Scheduled re-analysis with email/webhook alerts on metric changes

---

## Implementation Priority

| Enhancement | Effort | Impact | Priority |
|---|---|---|---|
| 1. Project-specific metrics | Medium | High | P0 |
| 2. Developer activity timeline | Low | High | P0 |
| 3. Bus factor analysis | Medium | High | P0 |
| 4. Trend-aware recommendations | Medium | High | P1 |
| 5. Consequence explanations | Low | Medium | P1 |
| 6. Contextualized priority scoring | High | High | P1 |
| 7. Actionable next steps | Low | Medium | P2 |
| 8. Social network from GitHub | High | High | P2 |
| 9. Comparative benchmarking | Medium | Medium | P2 |
| 10. Export & reporting | Medium | Low | P3 |

---

## References

The current `react_set.json` cites these papers most frequently:

- Coelho, J. & Valente, M.T. (2019). *Why Modern Open Source Projects Fail.* FSE '17.
- Avelino, G. et al. (2019). *On the Abandonment and Survival of Open Source Projects.* ESEM '19.
- Steinmacher, I. et al. (2015). *A Systematic Literature Review on the Barriers Faced by Newcomers to Open Source Projects.* IST.
- Yamashita, K. et al. (2018). *Turnover in Open-Source Projects: The Case of Core Developers.* OSS '20.
