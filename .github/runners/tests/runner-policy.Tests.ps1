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
            [int]$Id = 1,
            [Parameter(Mandatory)]
            [string]$Actor,
            [Parameter(Mandatory)]
            [string]$Status,
            [Parameter(Mandatory)]
            [DateTimeOffset]$UpdatedAt,
            [string]$TriggerEvent = "pull_request",
            [string]$Message = "ordinary work",
            [string]$Sha = "run123",
            [string]$DisplayTitle = "",
            [string]$HeadBranch = "feature"
        )

        [pscustomobject]@{
            id            = $Id
            actor         = [pscustomobject]@{ login = $Actor }
            event         = $TriggerEvent
            status        = $Status
            updated_at    = $UpdatedAt.ToString("o")
            head_sha      = $Sha
            head_branch   = $HeadBranch
            head_commit   = [pscustomobject]@{ message = $Message }
            display_title = $DisplayTitle
        }
    }

    function Invoke-TestPolicy {
        param(
            [object[]]$Events = @(),
            [object[]]$WorkflowRuns = @(),
            [string]$DirectTriggerActor = "",
            [string]$DirectTriggerMessage = "",
            [int]$MaxRunners = 35,
            [hashtable]$PoolJobDemand = @{ },
            [int]$WarmFloor = 10
        )

        $splatPolicy = @{
            Events                  = $Events
            WorkflowRuns            = $WorkflowRuns
            Maintainers             = $script:Maintainers
            OptInPushUsers          = $script:OptInPushUsers
            MaintainerCount         = 10
            MaintainerWindowMinutes = 20
            CommunityCount          = 5
            CommunityGraceMinutes   = 20
            MaxRunners              = $MaxRunners
            Marker                  = "[do ci]"
            Now                     = $script:Now
            DirectTriggerActor      = $DirectTriggerActor
            DirectTriggerMessage    = $DirectTriggerMessage
            PoolJobDemand           = $PoolJobDemand
            WarmFloor               = $WarmFloor
        }
        Get-DesiredRunnerPools @splatPolicy
    }

    function Get-ControllerCapacityPlanner {
        $tokens = $null
        $parseErrors = $null
        $controllerPath = (Resolve-Path "$PSScriptRoot/../reconcile-runner-fleet.ps1").Path
        $controllerAst = [System.Management.Automation.Language.Parser]::ParseFile($controllerPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) {
            throw "Could not parse $controllerPath"
        }
        $capacityPlanner = $controllerAst.Find({
                param($ast)
                $ast -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $ast.Name -eq "Invoke-VmssCapacityPlan"
            }, $true)
        if (-not $capacityPlanner) {
            throw "Invoke-VmssCapacityPlan is not defined in $controllerPath"
        }
        [scriptblock]::Create($capacityPlanner.Extent.Text)
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
    It "rejects an unmarked potato push run outside development" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "push"
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeFalse
    }

    It "accepts an unmarked potato merge run on development" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "queued" -UpdatedAt $script:Now -TriggerEvent "push" -HeadBranch "development"
        Test-CiRunEligible -Run $run -OptInPushUsers $script:OptInPushUsers -Marker "[do ci]" | Should -BeTrue
    }

    It "rejects an unmarked push run whose branch differs only by case" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "queued" -UpdatedAt $script:Now -TriggerEvent "push" -HeadBranch "Development"
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

    It "does not heat potato from an unmarked development push event with no run" {
        $event = New-PushEvent -Actor "potatoqualitee" -CreatedAt $script:Now.AddMinutes(-5) -Branch "development"
        $result = Invoke-TestPolicy -Events @($event)
        $result.potatoqualitee | Should -Be 0
    }

    It "retains potato while an unmarked merge run is live" {
        $run = New-CiRun -Actor "potatoqualitee" -Status "in_progress" -UpdatedAt $script:Now -TriggerEvent "push" -HeadBranch "development"
        $result = Invoke-TestPolicy -WorkflowRuns @($run)
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

    It "retains Andreas before the twenty-minute boundary" {
        $event = New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-19)
        $result = Invoke-TestPolicy -Events @($event)
        $result.andreasjordan | Should -Be 10
    }

    It "expires Andreas at the twenty-minute boundary" {
        $event = New-PushEvent -Actor "andreasjordan" -CreatedAt $script:Now.AddMinutes(-20)
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

Describe "Get-DesiredRunnerPools demand-driven sizing" {
    It "keeps all ten runners for a live maintainer lane regardless of pending demand" {
        $run = New-CiRun -Actor "andreasjordan" -Status "in_progress" -UpdatedAt $script:Now
        $splatDemand = @{
            WorkflowRuns  = @($run)
            PoolJobDemand = @{ andreasjordan = 3 }
            WarmFloor     = 0
        }
        $result = Invoke-TestPolicy @splatDemand
        $result.andreasjordan | Should -Be 10
    }

    It "retains all ten maintainer runners nineteen minutes after CI completion" {
        $run = New-CiRun -Actor "andreasjordan" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-19)
        $result = Invoke-TestPolicy -WorkflowRuns @($run) -WarmFloor 0
        $result.andreasjordan | Should -Be 10
    }

    It "drops a maintainer lane to zero twenty minutes after CI completion" {
        $run = New-CiRun -Actor "andreasjordan" -Status "completed" -UpdatedAt $script:Now.AddMinutes(-20)
        $result = Invoke-TestPolicy -WorkflowRuns @($run) -WarmFloor 10
        $result.andreasjordan | Should -Be 0
    }

    It "sizes the community lane to pending jobs and caps at five" {
        $run = New-CiRun -Actor "outsider" -Status "in_progress" -UpdatedAt $script:Now
        $splatDemand = @{
            WorkflowRuns  = @($run)
            PoolJobDemand = @{ community = 9 }
            WarmFloor     = 0
        }
        $result = Invoke-TestPolicy @splatDemand
        $result.community | Should -Be 5
    }

    It "leaves a cold lane at zero even when demand is reported" {
        $splatDemand = @{
            PoolJobDemand = @{ niphlod = 4 }
            WarmFloor     = 3
        }
        $result = Invoke-TestPolicy @splatDemand
        $result.niphlod | Should -Be 0
    }
}

Describe "Get-PoolJobDemandFromJobs" {
    BeforeAll {
        # Defined in BeforeAll, not the Describe body: Pester runs the Describe body
        # during discovery, so a function declared there does not exist when the It
        # blocks execute. This matches the helper idiom in the top-level BeforeAll.
        function New-TestJob {
            param(
                [string]$Status = "queued",
                [string[]]$Labels = @("self-hosted", "dbatools-modern", "dbatools-pool-andreasjordan")
            )
            [pscustomobject]@{
                status = $Status
                labels = $Labels
            }
        }
    }

    It "counts pending jobs per pool label" {
        $jobs = @((New-TestJob), (New-TestJob), (New-TestJob -Status "in_progress"))
        $result = Get-PoolJobDemandFromJobs -Jobs $jobs
        $result.andreasjordan | Should -Be 3
    }

    It "ignores completed jobs" {
        $jobs = @((New-TestJob -Status "completed"), (New-TestJob))
        $result = Get-PoolJobDemandFromJobs -Jobs $jobs
        $result.andreasjordan | Should -Be 1
    }

    It "ignores jobs with no pool label" {
        $jobs = @((New-TestJob -Labels @("ubuntu-latest")), (New-TestJob))
        $result = Get-PoolJobDemandFromJobs -Jobs $jobs
        $result.andreasjordan | Should -Be 1
        $result.Keys.Count | Should -Be 1
    }

    It "counts job statuses it has never seen as pending" {
        $jobs = @((New-TestJob -Status "waiting"), (New-TestJob -Status "some_future_status"))
        $result = Get-PoolJobDemandFromJobs -Jobs $jobs
        $result.andreasjordan | Should -Be 2
    }

    It "separates pools within one job list" {
        $jobs = @(
            (New-TestJob),
            (New-TestJob -Labels @("self-hosted", "dbatools-pool-community"))
        )
        $result = Get-PoolJobDemandFromJobs -Jobs $jobs
        $result.andreasjordan | Should -Be 1
        $result.community | Should -Be 1
    }

    It "returns an empty hashtable for no jobs" {
        $result = Get-PoolJobDemandFromJobs -Jobs @()
        $result.Keys.Count | Should -Be 0
    }
}

Describe "Get-PoolJobDemandFromRuns" {
    BeforeAll {
        function New-RunJob {
            param(
                [string]$Status = "queued",
                [string[]]$Labels = @("self-hosted", "dbatools-modern", "dbatools-pool-potatoqualitee")
            )
            [pscustomobject]@{
                status = $Status
                labels = $Labels
            }
        }
    }

    It "ignores an ineligible live run before its matrix is created" {
        $splatRun = @{
            Id           = 41
            Actor        = "potatoqualitee"
            Status       = "in_progress"
            UpdatedAt    = $script:Now
            TriggerEvent = "push"
        }
        $run = New-CiRun @splatRun
        $jobsByRun = @{ "41" = @((New-RunJob -Labels @("ubuntu-latest"))) }
        $splatDemand = @{
            WorkflowRuns    = @($run)
            JobsByRun       = $jobsByRun
            Maintainers     = $script:Maintainers
            OptInPushUsers  = $script:OptInPushUsers
            Marker          = "[do ci]"
            MaintainerCount = 10
            CommunityCount  = 5
        }

        $result = Get-PoolJobDemandFromRuns @splatDemand

        $result.Keys.Count | Should -Be 0
    }

    It "returns no demand after an eligible run's fleet matrix has completed" {
        $splatRun = @{
            Id        = 42
            Actor     = "potatoqualitee"
            Status    = "in_progress"
            UpdatedAt = $script:Now
        }
        $run = New-CiRun @splatRun
        $jobsByRun = @{ "42" = @((New-RunJob -Status "completed")) }
        $splatDemand = @{
            WorkflowRuns    = @($run)
            JobsByRun       = $jobsByRun
            Maintainers     = $script:Maintainers
            OptInPushUsers  = $script:OptInPushUsers
            Marker          = "[do ci]"
            MaintainerCount = 10
            CommunityCount  = 5
        }

        $result = Get-PoolJobDemandFromRuns @splatDemand

        $result.Keys.Count | Should -Be 0
    }

    It "estimates a full pool only before an eligible run's fleet matrix exists" {
        $splatRun = @{
            Id        = 43
            Actor     = "potatoqualitee"
            Status    = "in_progress"
            UpdatedAt = $script:Now
        }
        $run = New-CiRun @splatRun
        $jobsByRun = @{ "43" = @((New-RunJob -Labels @("ubuntu-latest"))) }
        $splatDemand = @{
            WorkflowRuns    = @($run)
            JobsByRun       = $jobsByRun
            Maintainers     = $script:Maintainers
            OptInPushUsers  = $script:OptInPushUsers
            Marker          = "[do ci]"
            MaintainerCount = 10
            CommunityCount  = 5
        }

        $result = Get-PoolJobDemandFromRuns @splatDemand

        $result.potatoqualitee | Should -Be 10
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

Describe "Get-VmssCapacityPlan" {
    It "repairs phantom capacity before scaling to the requested target" {
        $splatCapacity = @{
            NominalCapacity = 4
            ActualCapacity  = 0
            TargetCapacity  = 1
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -Be @(0, 1)
    }

    It "repairs a partial allocation before filling the requested target" {
        $splatCapacity = @{
            NominalCapacity = 10
            ActualCapacity  = 6
            TargetCapacity  = 10
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -Be @(6, 10)
    }

    It "does nothing when actual capacity already satisfies the target" {
        $splatCapacity = @{
            NominalCapacity = 1
            ActualCapacity  = 1
            TargetCapacity  = 1
        }
        @(Get-VmssCapacityPlan @splatCapacity) | Should -BeNullOrEmpty
    }
}

Describe "Get-FleetCapacityStep" {
    It "scales out in one compensated step despite phantom capacity" {
        $splatPhantom = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 9
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatPhantom | Should -Be 13
    }

    It "does not mistake an in-flight scale-out for phantom capacity" {
        $splatInFlight = @{
            ProvisioningState = "Updating"
            NominalCapacity   = 10
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatInFlight | Should -BeNullOrEmpty
    }

    It "treats a missing provisioning state as an operation in flight" {
        $splatMissing = @{
            ProvisioningState = ""
            NominalCapacity   = 9
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatMissing | Should -BeNullOrEmpty
    }

    It "treats an unknown provisioning state as an operation in flight" {
        $splatUnknown = @{
            ProvisioningState = "SomeFutureArmState"
            NominalCapacity   = 9
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatUnknown | Should -BeNullOrEmpty
    }

    It "keeps scaling out while churn mints fresh phantom capacity" {
        $splatChurn = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 7
            ActualCapacity    = 5
            TargetCapacity    = 20
        }
        Get-FleetCapacityStep @splatChurn | Should -Be 22
    }

    It "reclaims headroom when the compensated step is pinned at the ceiling" {
        $splatPinned = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 35
            ActualCapacity    = 20
            TargetCapacity    = 25
        }
        Get-FleetCapacityStep @splatPinned | Should -Be 20
    }

    It "normalizes phantom capacity once demand is satisfied" {
        $splatQuiet = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 12
            ActualCapacity    = 10
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatQuiet | Should -Be 10
    }

    It "still recovers a failed scale set" {
        $splatFailed = @{
            ProvisioningState = "Failed"
            NominalCapacity   = 9
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatFailed | Should -Be 13
    }

    It "emits nothing when settled capacity already matches the target" {
        $splatSettled = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 10
            ActualCapacity    = 10
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatSettled | Should -BeNullOrEmpty
    }

    It "still recovers a canceled scale set" {
        $splatCanceled = @{
            ProvisioningState = "Canceled"
            NominalCapacity   = 9
            ActualCapacity    = 6
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatCanceled | Should -Be 13
    }

    It "compensates from nominal even when actual runs ahead of it" {
        # 7 looks wrong next to 8 real instances, but creation is nominal-delta: Azure
        # makes newValue-minus-nominal VMs, so 7 creates exactly the 2 the target needs.
        $splatInverted = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 5
            ActualCapacity    = 8
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatInverted | Should -Be 7
    }

    It "normalizes an emptied fleet down to zero" {
        $splatDrained = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 3
            ActualCapacity    = 0
            TargetCapacity    = 0
        }
        Get-FleetCapacityStep @splatDrained | Should -Be 0
    }

    It "emits nothing when actual exceeds nominal and demand is met" {
        $splatSurplus = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 5
            ActualCapacity    = 8
            TargetCapacity    = 8
        }
        Get-FleetCapacityStep @splatSurplus | Should -BeNullOrEmpty
    }

    It "reclaims a nominal above the ceiling instead of crashing the pass" {
        $splatRunaway = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 40
            ActualCapacity    = 16
            TargetCapacity    = 20
        }
        Get-FleetCapacityStep @splatRunaway | Should -Be 16
    }

    It "reclaims the single drifted slot when pinned one short of the target" {
        $splatPinnedSlot = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 35
            ActualCapacity    = 34
            TargetCapacity    = 35
        }
        Get-FleetCapacityStep @splatPinnedSlot | Should -Be 34
    }

    It "skips the pass when nominal telemetry arrives negative" {
        $splatNegativeNominal = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = -1
            ActualCapacity    = 2
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatNegativeNominal | Should -BeNullOrEmpty
    }

    It "skips the pass when actual telemetry arrives negative" {
        $splatNegativeActual = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 5
            ActualCapacity    = -3
            TargetCapacity    = 10
        }
        Get-FleetCapacityStep @splatNegativeActual | Should -BeNullOrEmpty
    }

    It "normalizes to an actual above the ceiling without clamping it" {
        # 40 members really exist, so 40 is the only safe normalization value:
        # clamping to the 35 ceiling would turn a bookkeeping correction into the
        # deletion of five live runners. The ceiling caps what the controller
        # creates, never what it acknowledges.
        $splatOverCeilingActual = @{
            ProvisioningState = "Succeeded"
            NominalCapacity   = 42
            ActualCapacity    = 40
            TargetCapacity    = 20
        }
        Get-FleetCapacityStep @splatOverCeilingActual | Should -Be 40
    }
}

Describe "Flexible VMSS capacity reconciliation" {
    BeforeEach {
        $script:ScaleCalls = @()
        $script:ProvisioningPolls = 0
        $script:SleepSeconds = @()

        function script:Invoke-NativeText {
            param(
                [string]$Tool,
                [string[]]$Arguments,
                [string]$Operation
            )

            $script:ScaleCalls += [pscustomobject]@{
                Tool      = $Tool
                Arguments = $Arguments
                Operation = $Operation
            }
        }

        function script:Start-Sleep {
            param([int]$Seconds)

            $script:SleepSeconds += $Seconds
        }

        function script:Get-FleetState {
            $script:ProvisioningPolls += 1
            [pscustomobject]@{
                Vms = @([pscustomobject]@{ provisioning = "Succeeded" })
            }
        }
    }

    It "normalizes phantom capacity before async scale-out and polls provisioning" {
        . (Get-ControllerCapacityPlanner)

        $splatCapacity = @{
            NominalCapacity = 4
            ActualCapacity  = 0
            TargetCapacity  = 1
            TransitionBusy  = 0
            ResourceGroup   = "test-rg"
            Vmss            = "test-vmss"
        }
        Invoke-VmssCapacityPlan @splatCapacity

        $script:ScaleCalls.Count | Should -Be 2
        $script:ScaleCalls[0].Tool | Should -Be "az"
        $script:ScaleCalls[0].Operation | Should -Be "normalize VMSS capacity to 0"
        $script:ScaleCalls[0].Arguments | Should -Be @(
            "vmss", "scale", "--resource-group", "test-rg", "--name", "test-vmss",
            "--new-capacity", "0", "--only-show-errors", "--output", "none"
        )
        $script:ScaleCalls[1].Operation | Should -Be "scale VMSS to 1"
        $script:ScaleCalls[1].Arguments | Should -Be @(
            "vmss", "scale", "--resource-group", "test-rg", "--name", "test-vmss",
            "--new-capacity", "1", "--only-show-errors", "--output", "none", "--no-wait"
        )
        $script:SleepSeconds | Should -Be @(20)
        $script:ProvisioningPolls | Should -Be 1
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

    It "scopes that gate to controller dispatches so every merge to development runs" {
        # push only fires on development here, so the earlier "not a pull_request" form
        # skipped the entire suite on every merge -- authorize green, test skipped, run
        # green in ten seconds. The marker is only meant to stop an ordinary feature-branch
        # push, and those arrive as a controller dispatch carrying pool_user.
        $script:CiWorkflow | Should -Match "\`$CI_EVENT`" = `"workflow_dispatch`""
        $script:CiWorkflow | Should -Match "-n `"\`$CI_POOL_USER`""
        $script:CiWorkflow | Should -Not -Match "\`$CI_EVENT`" != `"pull_request`""
        $script:CiWorkflow | Should -Match "CI_POOL_USER: \S+\{\{ inputs\.pool_user \}\}"
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
        $script:ReconcileWorkflow | Should -Match 'BOOST_MINUTES: 20'
    }

    It "skips ordinary potato push nudges at the source" {
        $script:BoostWorkflow | Should -Match 'potatoqualitee push has no \[do ci\] marker'
    }

    It "keeps the Azure backstop aligned with the four-pool ceiling" {
        $script:Janitor | Should -Match '@\("potatoqualitee", "andreasjordan", "niphlod"\)'
        $script:Janitor | Should -Match 'MAX_RUNNERS is 35'
    }

    It "keeps the janitor warm floor aligned with the reconcile workflow" {
        # Explicit -match, not Should -Match: Pester's assertion does not publish
        # $Matches into the test scope, so capturing the captured group needs the
        # operator itself. Each -match overwrites $Matches, hence the interleaving.
        ($script:ReconcileWorkflow -match "WARM_FLOOR: (\d+)") | Should -BeTrue
        $workflowFloor = [int]$Matches[1]
        ($script:Janitor -match "\`$warmFloor = (\d+)") | Should -BeTrue
        [int]$Matches[1] | Should -Be $workflowFloor
    }

    It "documents that targeting and activation markers are unrelated" {
        $script:Readme | Should -Match '\(do <cmd>\).*\[do ci\].*compatible and unrelated'
    }
}
