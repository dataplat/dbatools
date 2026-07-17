BeforeAll {
    . "$PSScriptRoot/../runner-policy.ps1"

    $script:Now = [DateTimeOffset]::Parse("2026-07-17T12:00:00Z")
    $script:Maintainers = @("potatoqualitee", "andreasjordan", "niphlod")
    $script:OptInPushUsers = @("potatoqualitee")

    function New-PushEvent {
        param(
            [Parameter(Mandatory)]
            [string]$Actor,
            [Parameter(Mandatory)]
            [DateTimeOffset]$CreatedAt,
            [string]$Message = "ordinary work",
            [string]$Sha = "abc123",
            [string]$Branch = "feature"
        )

        [pscustomobject]@{
            type       = "PushEvent"
            created_at = $CreatedAt.ToString("o")
            actor      = [pscustomobject]@{ login = $Actor }
            payload    = [pscustomobject]@{
                head    = $Sha
                ref     = "refs/heads/$Branch"
                commits = @(
                    [pscustomobject]@{
                        sha     = $Sha
                        message = $Message
                    }
                )
            }
        }
    }

    function New-PullRequestEvent {
        param(
            [Parameter(Mandatory)]
            [string]$Actor,
            [Parameter(Mandatory)]
            [DateTimeOffset]$CreatedAt,
            [string]$Action = "synchronize"
        )

        [pscustomobject]@{
            type       = "PullRequestEvent"
            created_at = $CreatedAt.ToString("o")
            actor      = [pscustomobject]@{ login = $Actor }
            payload    = [pscustomobject]@{ action = $Action }
        }
    }

    function New-CiRun {
        param(
            [Parameter(Mandatory)]
            [string]$Actor,
            [Parameter(Mandatory)]
            [string]$Status,
            [Parameter(Mandatory)]
            [DateTimeOffset]$UpdatedAt,
            [string]$TriggerEvent = "pull_request",
            [string]$Message = "ordinary work",
            [string]$Sha = "run123",
            [string]$DisplayTitle = ""
        )

        [pscustomobject]@{
            actor       = [pscustomobject]@{ login = $Actor }
            event       = $TriggerEvent
            status      = $Status
            updated_at  = $UpdatedAt.ToString("o")
            head_sha    = $Sha
            head_commit = [pscustomobject]@{ message = $Message }
            display_title = $DisplayTitle
        }
    }

    function Invoke-TestPolicy {
        param(
            [object[]]$Events = @(),
            [object[]]$WorkflowRuns = @(),
            [string]$DirectTriggerActor = "",
            [string]$DirectTriggerMessage = "",
            [int]$MaxRunners = 35
        )

        $splatPolicy = @{
            Events                  = $Events
            WorkflowRuns            = $WorkflowRuns
            Maintainers             = $script:Maintainers
            OptInPushUsers          = $script:OptInPushUsers
            MaintainerCount         = 10
            MaintainerWindowMinutes = 60
            CommunityCount          = 5
            CommunityGraceMinutes   = 20
            MaxRunners              = $MaxRunners
            Marker                  = "[do ci]"
            Now                     = $script:Now
            DirectTriggerActor      = $DirectTriggerActor
            DirectTriggerMessage    = $DirectTriggerMessage
        }
        Get-DesiredRunnerPools @splatPolicy
    }
}

Describe "Test-CiMarker" {
    It "matches the runner marker case-insensitively" {
        Test-CiMarker -Message "work complete [DO CI]" -Marker "[do ci]" | Should -BeTrue
    }

    It "rejects a message without the exact marker" {
        Test-CiMarker -Message "do ci later" -Marker "[do ci]" | Should -BeFalse
    }
}

Describe "Test-CiRunEligible" {
    It "rejects an unmarked potato push run" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "push"
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeFalse
    }

    It "accepts a marked potato workflow dispatch" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "workflow_dispatch" -Message "[do ci]"
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeTrue
    }

    It "accepts potato PR CI without a marker" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeTrue
    }

    It "accepts other actors without a marker" {
        $run = New-CiRun -Actor "andreasjordan" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "push"
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeTrue
    }
}

Describe "Get-DesiredRunnerPools" {
    It "rejects an unmarked old-branch run even when a bot dispatched it" {
        $run = New-CiRun -Actor "github-actions[bot]" -Status "queued" -UpdatedAt $script:Now -TriggerEvent "push" -Message "ordinary migration work" -DisplayTitle "ci-azure [pool:potatoqualitee] ordinary migration work"
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.potatoqualitee | Should -Be 0
        $result.community | Should -Be 0
        @($result.Values | Measure-Object -Sum).Sum | Should -Be 0
    }

    It "attributes a dispatched run to its explicit pool user" {
        $run = New-CiRun -Actor "github-actions[bot]" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "workflow_dispatch" -Message "[do ci]" -DisplayTitle "ci-azure [pool:potatoqualitee]"
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.potatoqualitee | Should -Be 10
        $result.community | Should -Be 0
    }
    It "does not activate potato from an ordinary old-branch push dispatch" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now
        $result = Invoke-TestPolicy -Events @($event) -DirectTriggerActor "potatoqualitee"
        $result.potatoqualitee | Should -Be 0
    }

    It "activates potato from a marked direct push while event delivery catches up" {
        $result = Invoke-TestPolicy -DirectTriggerActor "potatoqualitee" -DirectTriggerMessage "work [DO CI]"
        $result.potatoqualitee | Should -Be 10
    }

    It "activates potato from a marked push event" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Message "work [do ci]"
        $result = Invoke-TestPolicy -Events @($event)
        $result.potatoqualitee | Should -Be 10
    }

    It "activates potato from PR synchronize activity without a marker" {
        $event = New-PullRequestEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5)
        $result = Invoke-TestPolicy -Events @($event)
        $result.potatoqualitee | Should -Be 10
    }

    It "retains potato while eligible PR CI is live" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.potatoqualitee | Should -Be 10
    }

    It "retains Andreas before the sixty-minute boundary" {
        $event = New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-59)
        $result = Invoke-TestPolicy -Events @($event)
        $result.andreasjordan | Should -Be 10
    }

    It "expires Andreas at the sixty-minute boundary" {
        $event = New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-60)
        $result = Invoke-TestPolicy -Events @($event)
        $result.andreasjordan | Should -Be 0
    }

    It "activates Niph independently" {
        $event = New-PushEvent -Actor "niphlod" -CreatedAt $script:Now.AddMinutes(-10)
        $result = Invoke-TestPolicy -Events @($event)
        $result.niphlod | Should -Be 10
        $result.andreasjordan | Should -Be 0
    }

    It "shares five community runners while CI is live" {
        $run = New-CiRun -Actor "contributor" -Status "in_progress" -UpdatedAt $script:Now
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.community | Should -Be 5
    }

    It "retains community nineteen minutes after CI completion" {
        $run = New-CiRun -Actor "contributor" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-19)
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.community | Should -Be 5
    }

    It "expires community at twenty minutes after CI completion" {
        $run = New-CiRun -Actor "contributor" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-20)
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
        $result.community | Should -Be 0
    }

    It "does not heat community from a push without CI" {
        $event = New-PushEvent -Actor "contributor" -CreatedAt $script:Now.AddMinutes(-5)
        $result = Invoke-TestPolicy -Events @($event)
        $result.community | Should -Be 0
    }

    It "returns zero for every pool without activity" {
        $result = Invoke-TestPolicy
        @($result.Values | Measure-Object -Sum).Sum | Should -Be 0
    }

    It "permits the complete thirty-five runner allocation" {
        $events = @(
            New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Message "[do ci]" -Sha "potato"
            New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-5) -Sha "andreas"
            New-PushEvent -Actor "niphlod" -CreatedAt $script:Now.AddMinutes(-5) -Sha "niph"
        )
        $run = New-CiRun -Actor "contributor" -Status "in_progress" -UpdatedAt $script:Now
        $result = Invoke-TestPolicy -Events $events -WorkflowRuns @($run)
        @($result.Values | Measure-Object -Sum).Sum | Should -Be 35
    }

    It "rejects policy totals above the hard maximum" {
        $events = @(
            New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Message "[do ci]" -Sha "potato"
            New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-5) -Sha "andreas"
            New-PushEvent -Actor "niphlod" -CreatedAt $script:Now.AddMinutes(-5) -Sha "niph"
        )
        $run = New-CiRun -Actor "contributor" -Status "in_progress" -UpdatedAt $script:Now
        { Invoke-TestPolicy -Events $events -WorkflowRuns @($run) -MaxRunners 34 } | Should -Throw "*MAX_RUNNERS*"
    }
}

Describe "Get-MarkedPushDispatch" {
    It "returns a new marked branch and SHA" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Message "work [do ci]" -Sha "marked123" -Branch "feature"
        $splatDispatch = @{
            Events         = @($event)
            WorkflowRuns   = @()
            OptInPushUsers = $script:OptInPushUsers
            Marker         = "[do ci]"
            Cutoff         = $script:Now.AddMinutes(-60)
        }
        $result = Get-MarkedPushDispatch @splatDispatch
        $result.Ref | Should -Be "feature"
        $result.Sha | Should -Be "marked123"
    }

    It "does not dispatch when CI already has the head SHA" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Message "[do ci]" -Sha "marked123"
        $run = New-CiRun -Actor "potatoqualitee" -Status "completed" -UpdatedAt $script:Now -TriggerEvent "workflow_dispatch" -Message "[do ci]" -Sha "marked123"
        $splatDispatch = @{
            Events         = @($event)
            WorkflowRuns   = @($run)
            OptInPushUsers = $script:OptInPushUsers
            Marker         = "[do ci]"
            Cutoff         = $script:Now.AddMinutes(-60)
        }
        Get-MarkedPushDispatch @splatDispatch | Should -BeNullOrEmpty
    }

    It "does not dispatch an unmarked potato push" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5)
        $splatDispatch = @{
            Events         = @($event)
            WorkflowRuns   = @()
            OptInPushUsers = $script:OptInPushUsers
            Marker         = "[do ci]"
            Cutoff         = $script:Now.AddMinutes(-60)
        }
        Get-MarkedPushDispatch @splatDispatch | Should -BeNullOrEmpty
    }
}

Describe "Runner workflow policy wiring" {
    BeforeAll {
        $script:RunnerRoot = (Resolve-Path "$PSScriptRoot/..").Path
        $script:WorkflowRoot = (Resolve-Path "$PSScriptRoot/../../workflows").Path
        $script:CiWorkflow = Get-Content -Raw "$script:WorkflowRoot/ci-azure.yml"
        $script:ReconcileWorkflow = Get-Content -Raw "$script:WorkflowRoot/runner-reconcile.yml"
        $script:BoostWorkflow = Get-Content -Raw "$script:WorkflowRoot/runner-boost.yml"
        $script:Janitor = Get-Content -Raw "$script:RunnerRoot/janitor-runbook.ps1"
        $script:Readme = Get-Content -Raw "$script:RunnerRoot/README.md"
    }

    It "gates the self-hosted CI job behind potato authorization" {
        $script:CiWorkflow | Should -Match "(?s)authorize:.*Unmarked potato push.*test:.*needs: authorize"
        $script:CiWorkflow | Should -Match "\[do ci\]"
    }

    It "defines all four pool labels" {
        foreach ($pool in @("potatoqualitee", "andreasjordan", "niphlod", "community")) {
            $script:CiWorkflow | Should -Match ([regex]::Escape("'$pool'"))
        }
    }

    It "reconciles completions frequently with explicit limits" {
        $script:ReconcileWorkflow | Should -Match 'cron: "\*/5 \* \* \* \*"'
        $script:ReconcileWorkflow | Should -Match 'types: \[requested, completed\]'
        $script:ReconcileWorkflow | Should -Match 'MAX_RUNNERS: 35'
        $script:ReconcileWorkflow | Should -Match 'COMMUNITY_GRACE_MINUTES: 20'
        $script:ReconcileWorkflow | Should -Match 'BOOST_HOURS: 1'
    }

    It "skips ordinary potato push nudges at the source" {
        $script:BoostWorkflow | Should -Match 'potatoqualitee push has no \[do ci\] marker'
    }

    It "keeps the Azure backstop aligned with the four-pool ceiling" {
        $script:Janitor | Should -Match '@\("potatoqualitee", "andreasjordan", "niphlod"\)'
        $script:Janitor | Should -Match 'MAX_RUNNERS is 35'
    }

    It "documents that targeting and activation markers are unrelated" {
        $script:Readme | Should -Match '\(do <cmd>\).*\[do ci\].*compatible and unrelated'
    }
}
