# Morning Briefing - runs via Task Scheduler at your chosen time on weekdays
# Launches Claude Code with the briefing prompt, which gathers data
# from DevOps + M365 MCP tools and posts to Teams webhook.
#
# Configuration: edit appsettings.json (not this file)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$config = Get-Content "$scriptDir\appsettings.json" | ConvertFrom-Json

$userName       = $config.userName
$project        = $config.devopsProject
$repo           = $config.devopsRepo
$teamName       = $config.teamName
$teamReviewerId = $config.teamReviewerId
$workHours      = $config.workHoursPerDay
$workMinutes    = [int]($workHours * 60)
$webhookUrl     = $config.webhookUrl

$prompt = @"
You are ${userName}'s morning briefing agent. Gather data and post a summary to their Teams channel.

IMPORTANT — execution order: Complete ALL of Step 1 (Azure DevOps) before starting Step 2 (Microsoft 365). This ensures DevOps data is always captured even if M365 is slow or unavailable.

IMPORTANT — M365 retry policy: If ANY Microsoft 365 tool call fails (timeout, error, unavailable), wait 5 seconds and retry that specific call ONCE. If the retry also fails, record the failure and continue with remaining M365 calls — do not abandon the whole M365 step because one call failed.

## Step 1: Get Azure DevOps Data

### 1a. My PRs
- repo_list_pull_requests_by_repo_or_project with project=${project}, repositoryId=${repo}, created_by_me=true, status=Active

### 1b. PRs to review — gather candidates
Run BOTH of these queries and combine results (de-duplicate by PR ID):
- repo_list_pull_requests_by_repo_or_project with project=${project}, repositoryId=${repo}, i_am_reviewer=true, status=Active
- repo_list_pull_requests_by_repo_or_project with project=${project}, repositoryId=${repo}, status=Active, user_is_reviewer=${teamReviewerId}

The first query gets PRs where ${userName} is a direct individual reviewer.
The second query gets PRs where ${teamName} is a team reviewer (i_am_reviewer misses these).

From the combined list, immediately discard:
- Drafts (isDraft=true)
- PRs created by ${userName} (those are in "My PRs")

### 1c. Get squad members
Use core_list_project_teams with project=${project} to find the "${teamName}" team, then use core_get_identity_ids to get its current member names. These are needed for vote checking below.

### 1d. PR detail lookup
For each remaining PR, call repo_get_pull_request_by_id with includeWorkItemRefs=true.
This returns the reviewers array (with votes, hasDeclined, isContainer) and workItemRefs.
There will be ~20 PRs. You MUST fetch details for ALL of them — do not skip or stop early.

### 1e. Check for rejections/declines FIRST (before work item filter)
Scan ALL PRs from 1d. Any PR where a reviewer has vote=-10 (Rejected) OR hasDeclined=true goes into the **Needs Investigation** bucket immediately — these bypass the work item state filter entirely. Note the reason (e.g. "Rejected by Sam Eastburn", "Declined by Scarlett Ward").

### 1f. Work item state filter (for remaining PRs not in Investigation)
Collect ALL unique work item IDs from the remaining PRs' workItemRefs.
Call wit_get_work_items_batch_by_ids ONCE with all IDs to get their states in a single call.
Then for each PR:
1. KEEP only if at least one linked work item has state "Code Review" or "In Local Testing"
2. DISCARD if ALL linked work items are in any other state (In Development, New, Accepted, Removed, Merged to dev branch, etc.)
3. If NO work items are linked, keep with a note "(no linked work item)"

Vote values: 10=Approved, 5=Approved with suggestions, 0=No vote, -5=Waiting for author, -10=Rejected.

### 1g. Categorise into buckets
From the PRs that survived 1f (plus Investigation PRs from 1e):

**Needs My Review** — ${userName} is listed as a direct individual reviewer AND their vote is 0.

**Needs Team Review** — ${teamName} is listed as a reviewer AND no squad member (from 1c) has individually voted >= 5 on this PR. Important: check the vote on each individual reviewer entry whose name matches a squad member — do NOT rely on the team container's vote field (it is always 0).

**Needs Investigation** — Already identified in step 1e. Show with explanation.

**Already Actioned (hide completely)** — ${userName} has voted >= 5, OR any squad member has individually voted >= 5.

### 1h. Work items assigned to me
- wit_my_work_items with project=${project}, type=assignedtome
- For returned work item IDs, use wit_get_work_items_batch_by_ids to get titles, states, iteration paths

## Step 2: Get Microsoft 365 Data (after Step 1 is fully complete)
Use the Microsoft 365 MCP tools. Apply the retry policy above to each call individually.

### 2a. Core M365 data
- outlook_calendar_search with query=*, afterDateTime='today', beforeDateTime='tomorrow', limit=20
- outlook_email_search with folderName=Inbox, afterDateTime='yesterday', limit=20
- chat_message_search with query=*, afterDateTime='yesterday', limit=25

### 2b. Release Channels
Monitor these Teams channels for release activity:
- chat_message_search with query='release', afterDateTime='yesterday', limit=20
- chat_message_search with query='finance', afterDateTime='yesterday', limit=20
- chat_message_search with query='deploy OR release OR environment', afterDateTime='yesterday', limit=20
Extract any purchasing, finance, or platform release/deployment mentions.

## Step 3: Calculate Free Work Time
${userName} works ${workHours} hours (${workMinutes} minutes) per day:
- For each meeting: subtract duration PLUS 10 minutes (5 min buffer each side)
- Subtract 10 minutes flex per every 2 hours (about 37 min total)
- Report remaining free work time

## Step 4: Compile and Deliver
Build an Adaptive Card JSON and POST it via curl to this webhook:
WEBHOOK="${webhookUrl}"

Write the JSON to a temp file first, then POST:
curl -s -X POST "`$WEBHOOK" -H "Content-Type: application/json; charset=utf-8" --data-binary @/tmp/briefing.json

Card sections:
1. Header: Morning Briefing - {today's date DD MMMM YYYY}
2. Today's Calendar: each meeting with time, title, duration
3. Free Work Time: e.g. "4h 35m available (3 meetings, 30m buffers, 37m flex)"
4. Releases: purchasing/finance/platform release activity from last 24h
5. My PRs: PR ID, title, target branch
6. PRs Needing Review: split into three sub-sections:
   a. "Needs My Review" — PRs assigned directly to me with no vote yet. Show PR ID, author, title.
   b. "Needs Team Review" — PRs assigned to ${teamName} where no squad member has approved. Show PR ID, author, title.
   c. "Needs Investigation" — PRs with a rejection (vote -10) or a declined review (hasDeclined=true). Show PR ID, author, title, and WHY.
   Omit PRs already approved by me or any squad member entirely.
7. Work Items: ID, type, title, state (skip stale past-sprint items unless fewer than 5 current)
8. Email Highlights: actionable items only, skip marketing/newsletters/system notifications
9. Teams Highlights: messages needing attention (exclude release noise covered above)
10. TODO List: numbered, prioritised. Order: meeting prep, PR reviews, own work items, email follow-ups

IMPORTANT:
- ASCII only in JSON - no smart quotes or special unicode
- If a section is empty, show "Nothing here today"
- If a data source fails, note the error and continue
"@

# Suppress browser popup during M365 OAuth (token exchange still works via localhost redirect)
$env:BROWSER = "false"

# Run Claude Code with the prompt
claude --print "$prompt"
