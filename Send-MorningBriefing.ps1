<#
.SYNOPSIS
    Morning briefing script — gathers DevOps PRs, work items, emails, Teams chats
    and posts a summary to a Teams channel via webhook.
    Designed to be run by a Claude Code remote trigger each weekday morning.
#>

param(
    [string]$WebhookUrl = "https://default60e9bcaaf4c1441b8d931bda37d909.0b.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/33f98280b86d4714b4993034faaa0921/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=qQPadNXrqrCY4_pibg3XoRNMTB65pr5A4kg6gC2AlZo"
)

function Send-AdaptiveCard {
    param([hashtable]$Card)

    $payload = @{
        type        = "message"
        attachments = @(
            @{
                contentType = "application/vnd.microsoft.card.adaptive"
                contentUrl  = $null
                content     = $Card
            }
        )
    } | ConvertTo-Json -Depth 20 -Compress

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body $payload
}

# This script is a template — the actual data gathering is done by the Claude remote trigger
# which has access to MCP tools (DevOps, M365, etc.) and calls this webhook directly.
# See the remote trigger prompt for the full logic.
Write-Host "This script is invoked by the Claude remote trigger. Run it via /schedule."
