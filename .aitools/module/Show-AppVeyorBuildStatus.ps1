function Show-AppVeyorBuildStatus {
    <#
    .SYNOPSIS
        Shows detailed AppVeyor build status for a specific build ID.

    .DESCRIPTION
        Retrieves and displays comprehensive build information from AppVeyor API v2,
        including build status, jobs, and test results with adorable formatting.

    .PARAMETER BuildId
        The AppVeyor build ID to retrieve status for

    .PARAMETER AccountName
        The AppVeyor account name. Defaults to 'dataplat'

    .EXAMPLE
        PS C:\> Show-AppVeyorBuildStatus -BuildId 12345

        Shows detailed status for AppVeyor build 12345 with maximum cuteness
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Intentional: command renders a user-facing TUI with colors/emojis in CI.'
    )]
    param (
        [Parameter(Mandatory)]
        [string]$BuildId,

        [string]$AccountName = 'dataplat'
    )

    try {
        Write-Host "🔍 " -NoNewline -ForegroundColor Cyan
        Write-Host "Fetching AppVeyor build details..." -ForegroundColor Gray

        $apiParams = @{
            Endpoint    = "projects/dataplat/dbatools/builds/$BuildId"
            AccountName = $AccountName
        }
        $response = Invoke-AppVeyorApi @apiParams

        if ($response -and $response.build) {
            $build = $response.build

            # Header with fancy border
            Write-Host "`n╭─────────────────────────────────────────╮" -ForegroundColor Magenta
            Write-Host "│          🏗️  AppVeyor Build Status      │" -ForegroundColor Magenta
            Write-Host "╰─────────────────────────────────────────╯" -ForegroundColor Magenta

            # Build details with cute icons
            Write-Host "🆔 Build ID:   " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.buildId)" -ForegroundColor White

            # Status with colored indicators
            Write-Host "📊 Status:     " -NoNewline -ForegroundColor Yellow
            switch ($build.status.ToLower()) {
                'success' { Write-Host "✅ $($build.status)" -ForegroundColor Green }
                'failed' { Write-Host "❌ $($build.status)" -ForegroundColor Red }
                'running' { Write-Host "⚡ $($build.status)" -ForegroundColor Cyan }
                'queued' { Write-Host "⏳ $($build.status)" -ForegroundColor Yellow }
                default { Write-Host "❓ $($build.status)" -ForegroundColor Gray }
            }

            Write-Host "📦 Version:    " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.version)" -ForegroundColor White

            Write-Host "🌿 Branch:     " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.branch)" -ForegroundColor Green

            Write-Host "💾 Commit:     " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.commitId.Substring(0,8))" -ForegroundColor Cyan

            Write-Host "🚀 Started:    " -NoNewline -ForegroundColor Yellow
            Write-Host "$($build.started)" -ForegroundColor White

            if ($build.finished) {
                Write-Host "🏁 Finished:   " -NoNewline -ForegroundColor Yellow
                Write-Host "$($build.finished)" -ForegroundColor White
            }

            # Jobs section with adorable formatting
            if ($build.jobs) {
                Write-Host "`n╭─── 👷‍♀️ Jobs ───╮" -ForegroundColor Cyan
                foreach ($job in $build.jobs) {
                    Write-Host "│ " -NoNewline -ForegroundColor Cyan

                    # Job status icons
                    switch ($job.status.ToLower()) {
                        'success' { Write-Host "✨ " -NoNewline -ForegroundColor Green }
                        'failed' { Write-Host "💥 " -NoNewline -ForegroundColor Red }
                        'running' { Write-Host "🔄 " -NoNewline -ForegroundColor Cyan }
                        default { Write-Host "⭕ " -NoNewline -ForegroundColor Gray }
                    }

                    Write-Host "$($job.name): " -NoNewline -ForegroundColor White
                    Write-Host "$($job.status)" -ForegroundColor $(
                        switch ($job.status.ToLower()) {
                            'success' { 'Green' }
                            'failed' { 'Red' }
                            'running' { 'Cyan' }
                            default { 'Gray' }
                        }
                    )

                    if ($job.duration) {
                        Write-Host "│   ⏱️  Duration: " -NoNewline -ForegroundColor Cyan
                        Write-Host "$($job.duration)" -ForegroundColor Gray
                    }
                }
                Write-Host "╰────────────────╯" -ForegroundColor Cyan
            }

            Write-Host "`n🎉 " -NoNewline -ForegroundColor Green
            Write-Host "Build status retrieved successfully!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  " -NoNewline -ForegroundColor Yellow
            Write-Host "No build data returned from AppVeyor API" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "`n💥 " -NoNewline -ForegroundColor Red
        Write-Host "Oops! Something went wrong:" -ForegroundColor Red
        Write-Host "   $($_.Exception.Message)" -ForegroundColor Gray

        if (-not $env:APPVEYOR_API_TOKEN) {
            Write-Host "`n🔑 " -NoNewline -ForegroundColor Yellow
            Write-Host "AppVeyor API Token Setup:" -ForegroundColor Yellow
            Write-Host "   1️⃣  Go to " -NoNewline -ForegroundColor Cyan
            Write-Host "https://ci.appveyor.com/api-token" -ForegroundColor Blue
            Write-Host "   2️⃣  Generate a new API token (v2)" -ForegroundColor Cyan
            Write-Host "   3️⃣  Set: " -NoNewline -ForegroundColor Cyan
            Write-Host "`$env:APPVEYOR_API_TOKEN = 'your-token'" -ForegroundColor White
        }
    }
}