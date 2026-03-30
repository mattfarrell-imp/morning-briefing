# Morning Briefing Agent

Automated daily briefing posted to a Microsoft Teams channel via Claude Code. Gathers data from Azure DevOps (PRs, work items) and Microsoft 365 (calendar, email, Teams chats) and delivers a formatted Adaptive Card summary every weekday morning.

## How It Works

```
Task Scheduler (09:10 weekdays)
  -> Run-MorningBriefing.ps1
    -> claude --print (with briefing prompt)
      -> MCP tools fetch DevOps + M365 data
      -> Builds Adaptive Card JSON
      -> POSTs to Power Automate webhook
        -> Posts card to Teams channel
```

## Prerequisites

- **Claude Code CLI** installed and authenticated (`claude` available on PATH)
- **Azure DevOps MCP server** configured in Claude Code (for PRs, work items)
- **Microsoft 365 MCP server** configured in Claude Code (for calendar, email, Teams chats)
- **Power Automate** (or a Teams Incoming Webhook) to receive the card
- **Windows Task Scheduler** (or cron on Linux/macOS) to run daily

## Setup

### 1. Install Claude Code

Follow the [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code) to install and authenticate.

### 2. Configure MCP Servers

Claude Code needs two MCP servers. Add them to your Claude Code settings (`~/.claude/settings.json` or via the CLI):

**Azure DevOps MCP** - provides PR lists, work items, reviewer votes.
We're all in the `impsoftwareuk` org, so just generate a PAT with read access to Code and Work Items:

```json
{
  "mcpServers": {
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@anthropic/azure-devops-mcp"],
      "env": {
        "AZURE_DEVOPS_ORG": "impsoftwareuk",
        "AZURE_DEVOPS_PAT": "your-personal-access-token"
      }
    }
  }
}
```

To create a PAT: Azure DevOps > User Settings (top-right) > Personal Access Tokens > New Token. Give it **Code (Read)** and **Work Items (Read)** scopes.

**Microsoft 365 MCP** - provides calendar, email, Teams chat search:
```json
{
  "mcpServers": {
    "microsoft-365": {
      "command": "npx",
      "args": ["-y", "@anthropic/microsoft-365-mcp"]
    }
  }
}
```

Check the MCP server documentation for the latest install instructions and authentication steps. The M365 server typically requires an OAuth app registration in Entra ID.

### 3. Create the Teams Webhook (Power Automate)

This briefing posts an Adaptive Card to Teams via a Power Automate workflow. Here's how to set one up:

1. Go to [Power Automate](https://make.powerautomate.com/)
2. Create a new **Instant cloud flow** with trigger **When an HTTP request is received**
3. In the trigger, set the method to **POST** and leave the JSON schema blank (accept any)
4. Add an action: **Microsoft Teams > Post adaptive card in a chat or channel**
   - Post as: Flow bot
   - Post in: Channel
   - Team: select your team (e.g. "Purchasing Squad")
   - Channel: select or create a channel (e.g. "Morning Briefings")
5. In the Adaptive Card field, use this expression to extract the card from the payload:
   ```
   triggerBody()?['attachments']?[0]?['content']
   ```
   Or map the full body if your card format differs.
6. **Save** the flow. Copy the **HTTP POST URL** from the trigger — this is your webhook URL.

**Alternative: Teams Incoming Webhook (simpler but limited)**

If you don't need Power Automate, you can use a basic Incoming Webhook connector:
1. In Teams, go to the target channel > Manage channel > Connectors
2. Add **Incoming Webhook**, give it a name, copy the URL
3. Note: Incoming Webhooks use a slightly different payload format and have a character limit

### 4. Configure

Copy `appsettings.template.json` to `appsettings.json` and fill in your details:

```json
{
  "userName": "Your Name",
  "devopsProject": "ImpPlanner",
  "devopsRepo": "ImpPlanner",
  "teamName": "Purchasing Squad",
  "teamReviewerId": "vstfs:///Classification/TeamProject/f8031cff-1c25-4ba5-9fde-766c967e1457\\Purchasing Squad",
  "workHoursPerDay": 7.5,
  "webhookUrl": "YOUR_POWER_AUTOMATE_WEBHOOK_URL"
}
```

| Field | What to change |
|-------|---------------|
| `userName` | Your full name as it appears in Azure DevOps |
| `devopsProject` | Leave as `ImpPlanner` (we're all in the same org) |
| `devopsRepo` | Leave as `ImpPlanner` |
| `teamName` | Your team name in DevOps (e.g. `Purchasing Squad`, `Finance Squad`) |
| `teamReviewerId` | Your team's reviewer identity (see "Finding your team reviewer ID" below) |
| `workHoursPerDay` | Your contracted hours (default 7.5) |
| `webhookUrl` | Your Power Automate webhook URL from step 3 |

**Finding your team reviewer ID:** Open any PR in Azure DevOps where your team is a required reviewer. In the URL bar, navigate to the PR API: `https://dev.azure.com/impsoftwareuk/ImpPlanner/_apis/git/repositories/ImpPlanner/pullRequests/{PR_ID}?api-version=7.0`. Look for the reviewer entry with `isContainer: true` — the `uniqueName` field is your `teamReviewerId`.

You do NOT need to edit `Run-MorningBriefing.ps1` — it reads everything from `appsettings.json`.

### 5. Schedule It

Pick a time that works for you -- the default is 09:10 but you can set whatever you like.

**Windows Task Scheduler:**

1. Open Task Scheduler > Create Task
2. Name: `Morning Briefing`
3. Trigger: Daily, **your preferred time** (e.g. 08:30, 09:10), weekdays only (Mon-Fri)
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\Users\YourName\scripts\morning-briefing\Run-MorningBriefing.ps1"`
5. Conditions: uncheck "Start only if on AC power" if using a laptop
6. Settings: check "Run task as soon as possible after a scheduled start is missed"

To change the time later, just edit the trigger in Task Scheduler -- no code changes needed.

**Linux/macOS cron (alternative):**

```bash
# crontab -e
# Change "10 9" to your preferred hour/minute (24h format)
10 9 * * 1-5 /path/to/Run-MorningBriefing.sh
```

### 6. Test It

Run manually to verify:

```powershell
powershell -ExecutionPolicy Bypass -File .\Run-MorningBriefing.ps1
```

Check your Teams channel for the card. If M365 tools aren't connected, those sections will show fallback text — the DevOps sections should still work.

## Customisation

### PR Review Filtering

The briefing categorises PRs into:

- **Needs My Review** -- assigned directly to you, you haven't voted yet
- **Needs Team Review** -- assigned to your team, no team member has approved yet
- **Already Actioned** -- you or a team member approved; hidden from the briefing

Edit the squad member list in the prompt to match your team.

### Card Sections

The Adaptive Card includes these sections (all customisable in the prompt):

| Section | Source |
|---------|--------|
| Calendar | M365 `outlook_calendar_search` |
| Free Work Time | Calculated from calendar |
| Releases | M365 `chat_message_search` |
| My PRs | DevOps `repo_list_pull_requests_by_repo_or_project` |
| PR Reviews | DevOps PR list + `repo_get_pull_request_by_id` for votes |
| Work Items | DevOps `wit_my_work_items` |
| Email | M365 `outlook_email_search` |
| Teams | M365 `chat_message_search` |
| TODO List | Auto-generated from above |

### TeamsRelay Azure Function (Optional)

The `TeamsRelay/` directory contains an Azure Function that acts as a proxy -- it receives the Adaptive Card JSON and forwards it to the Teams webhook. This is useful if you want to:

- Deploy the relay to Azure and use it as a stable endpoint
- Add auth, logging, or rate limiting
- Use it from Claude Code remote triggers instead of direct webhook calls

To deploy: `func azure functionapp publish <your-function-app-name>`

Set the `TEAMS_WEBHOOK_URL` app setting in the Function App to your Power Automate webhook URL.

## Quick Start (for teammates)

1. Copy this folder to `C:\Users\YourName\scripts\morning-briefing\`
2. Copy `appsettings.template.json` to `appsettings.json`
3. Fill in your name and webhook URL (see step 4 above)
4. Ensure Claude Code CLI is installed and authenticated
5. Test: `powershell -ExecutionPolicy Bypass -File .\Run-MorningBriefing.ps1`
6. Set up Task Scheduler (see step 5 above)

## File Structure

```
morning-briefing/
  Run-MorningBriefing.ps1      # Main script - reads config and runs Claude
  appsettings.json              # YOUR config (git-ignored, not shared)
  appsettings.template.json     # Template to copy — fill in your details
  Send-MorningBriefing.ps1      # Helper for sending Adaptive Cards
  briefing.json                 # Sample output (last generated card)
  README.md                     # This file
  TeamsRelay/                   # Optional Azure Function relay
    RelayToTeams.cs
    Program.cs
    TeamsRelay.csproj
    host.json
    local.settings.json
```

## Troubleshooting

- **No card posted**: Check the webhook URL is correct and the Power Automate flow is turned on
- **M365 sections empty**: The M365 MCP server needs OAuth consent -- check auth status
- **DevOps sections empty**: Verify your PAT has read access to the repo and work items
- **Card formatting broken**: Check for non-ASCII characters (smart quotes, emoji) in the JSON -- the prompt enforces ASCII only
- **Task Scheduler not running**: Ensure "Run whether user is logged on or not" is set, and the user account has "Log on as a batch job" rights
