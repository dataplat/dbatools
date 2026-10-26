# Ack-then-queue. GitHub gives a webhook 10 seconds to answer and never redelivers a
# failed one, so this validates the signature, drops a nudge on the queue and returns.
# A reconcile pass takes minutes; it must not happen on this thread.

param($Request, $TriggerMetadata)

$secret = $env:GITHUB_WEBHOOK_SECRET
if (-not $secret) {
    # Write-Warning, not Write-Error: an errored invocation is marked Failed and the
    # host answers with a bare 500, throwing away the response below. The status code
    # is the alert signal; the body is what tells whoever reads GitHub's delivery log
    # which setting is missing.
    Write-Warning "GITHUB_WEBHOOK_SECRET is not set; refusing to accept unverifiable deliveries"
    $splatUnconfigured = @{
        Name  = "Response"
        Value = [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::InternalServerError
            Body       = "webhook secret not configured"
        }
    }
    Push-OutputBinding @splatUnconfigured
    return
}

$rawBody = [string]$Request.RawBody
$splatSignature = @{
    Body      = $rawBody
    Signature = [string]$Request.Headers["x-hub-signature-256"]
    Secret    = $secret
}
if (-not (Test-GitHubWebhookSignature @splatSignature)) {
    # Deliberately before the payload is parsed or logged: an unverified body is
    # attacker-controlled and gets no further than this.
    $splatUnauthorized = @{
        Name  = "Response"
        Value = [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::Unauthorized
            Body       = "invalid signature"
        }
    }
    Push-OutputBinding @splatUnauthorized
    return
}

$eventName = [string]$Request.Headers["x-github-event"]
$deliveryId = [string]$Request.Headers["x-github-delivery"]
if ($eventName -eq "ping") {
    $splatPing = @{
        Name  = "Response"
        Value = [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = "pong"
        }
    }
    Push-OutputBinding @splatPing
    return
}

$config = Get-FleetConfig
$splatNudge = @{
    EventName   = $eventName
    Payload     = ($rawBody | ConvertFrom-Json -Depth 20)
    BoostUsers  = @([string]$config["BOOST_USERS"] -split "\s+" | Where-Object { $PSItem })
    RunnerLabel = [string]$config["RUNNER_LABEL"]
    CiWorkflow  = [string]$config["CI_WORKFLOW"]
}
$nudge = Get-FleetNudge @splatNudge
if (-not $nudge) {
    Write-Host "ignored $eventName delivery $deliveryId"
    $splatIgnored = @{
        Name  = "Response"
        Value = [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::Accepted
            Body       = "ignored"
        }
    }
    Push-OutputBinding @splatIgnored
    return
}

$nudge["delivery"] = $deliveryId
Push-OutputBinding -Name Nudge -Value ($nudge | ConvertTo-Json -Compress -Depth 6)
Write-Host "queued $($nudge["reason"]) from delivery $deliveryId"
$splatQueued = @{
    Name  = "Response"
    Value = [HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::Accepted
        Body       = "queued"
    }
}
Push-OutputBinding @splatQueued
