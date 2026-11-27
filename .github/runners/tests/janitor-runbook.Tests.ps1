BeforeAll {
    $script:JanitorPath = (Resolve-Path "$PSScriptRoot/../janitor-runbook.ps1").Path
    $script:Now = (Get-Date).ToUniversalTime()
}

Describe "janitor runner protection" {
    BeforeEach {
        $script:RemovedVms = @()
        $script:RemovedNics = @()
        $script:RemovedPips = @()
        $script:Events = @()
        $script:Runs = @()
        $script:Vms = @()
        $script:Nics = @()
        $script:Pips = @()
        $script:ResourceCreatedAt = @{ }
        $script:CommitMessages = @{ }
        $script:CommitLookups = @()
        $script:RunsUnavailable = $false

        function Connect-AzAccount {
            param([switch]$Identity, [string]$WarningAction)
        }

        function Invoke-RestMethod {
            param(
                [string]$Uri,
                [hashtable]$Headers,
                [int]$TimeoutSec
            )
            if ($Uri -like "*/events?*") {
                # like the real cmdlet, emit the top-level JSON array as one Object[]
                return , @($script:Events)
            }
            if ($Uri -match "/commits/([^/?]+)$") {
                $sha = $Matches[1]
                $script:CommitLookups += $sha
                if (-not $script:CommitMessages.ContainsKey($sha)) {
                    throw "404 Not Found: commit $sha"
                }
                return [pscustomobject]@{ commit = [pscustomobject]@{ message = $script:CommitMessages[$sha] } }
            }
            if ($script:RunsUnavailable) {
                throw "503 Service Unavailable"
            }
            [pscustomobject]@{ workflow_runs = $script:Runs }
        }

        function Start-Sleep {
            param([int]$Seconds)
        }

        function Get-AzVM {
            param([string]$ResourceGroupName)
            $script:Vms
        }

        function Remove-AzVM {
            param(
                [string]$ResourceGroupName,
                [string]$Name,
                [switch]$Force
            )
            $script:RemovedVms += $Name
        }

        function Get-AzNetworkInterface {
            param([string]$ResourceGroupName)
            $script:Nics
        }

        function Remove-AzNetworkInterface {
            param(
                [string]$ResourceGroupName,
                [string]$Name,
                [switch]$Force
            )
            $script:RemovedNics += $Name
        }

        function Get-AzPublicIpAddress {
            param([string]$ResourceGroupName)
            $script:Pips
        }

        function Get-AzVmss {
            param(
                [string]$ResourceGroupName,
                [string]$VMScaleSetName,
                [string]$ErrorAction
            )
        }

        function Remove-AzPublicIpAddress {
            param(
                [string]$ResourceGroupName,
                [string]$Name,
                [switch]$Force
            )
            $script:RemovedPips += $Name
        }

        function Get-AzResource {
            param(
                [string]$ResourceId,
                [switch]$ExpandProperties,
                [string]$ErrorAction
            )
            [pscustomobject]@{ CreatedTime = $script:ResourceCreatedAt[$ResourceId] }
        }
    }

    It "protects the active lane instead of the newest runners from another lane" {
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
        )
        $andreasVms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })
        $niphVms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $script:Now.AddHours(-5)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })
        $script:Vms = @($andreasVms + $niphVms)

        . $script:JanitorPath | Out-Null

        @($script:RemovedVms | Where-Object { $PSItem -like "*andreas*" }).Count | Should -Be 0
        @($script:RemovedVms | Where-Object { $PSItem -like "*niph*" }).Count | Should -Be 10
    }

    It "preserves ten maintainer runners for a CI run completed within the grace period" {
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "completed"
                updated_at    = $script:Now.AddMinutes(-19).ToString("o")
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })

        . $script:JanitorPath | Out-Null

        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "keeps live lanes protected when a run carries an unreadable timestamp" {
        # The completed niphlod run cannot be dated; it only stops counting as recent,
        # while the live andreasjordan and community lanes keep their runners past the
        # 4h cap for excess capacity.
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "a-contributor" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "niphlod" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "completed"
                updated_at    = "not a timestamp"
            }
        )
        $andreasVms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })
        $communityVms = @(1..5 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_community-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "community" }
                }
            })
        $script:Vms = @($andreasVms + $communityVms)

        $warnings = . $script:JanitorPath 3>&1 | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }

        @($warnings | Where-Object { $PSItem.Message -like "unreadable GitHub timestamp*" }).Count | Should -BeGreaterThan 0
        $mode | Should -Be "active"
        $activeMaintainers | Should -Be @("andreasjordan")
        $communityLive | Should -BeTrue
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "applies the age caps to every lane when GitHub cannot be read" {
        # The runs request fails after the events arrived; the runners are past every
        # fallback age cap, community included.
        $script:RunsUnavailable = $true
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
        )
        $andreasVms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-14)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })
        $communityVms = @(1..5 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_community-$PSItem"
                    TimeCreated = $script:Now.AddHours(-14)
                    Tags        = @{ runnerPool = "community" }
                }
            })
        $script:Vms = @($andreasVms + $communityVms)

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "github-unreachable"
        @($script:RemovedVms | Where-Object { $PSItem -like "*andreas*" }).Count | Should -Be 10
        @($script:RemovedVms | Where-Object { $PSItem -like "*community*" }).Count | Should -Be 5
    }

    It "drops the lanes it marked when the check fails after classifying them" {
        # The live runs mark andreasjordan and community active. The created_at of a
        # stranger's event is first read when the activity times are collected, after
        # every lane is classified, and it cannot even be turned into a string.
        $unconvertible = [pscustomobject]@{ }
        $splatThrowingToString = @{
            MemberType = "ScriptMethod"
            Name       = "ToString"
            Value      = { throw "unexpected failure" }
            Force      = $true
        }
        $unconvertible | Add-Member @splatThrowingToString
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "a-stranger" }
                type       = "WatchEvent"
                created_at = $unconvertible
                payload    = [pscustomobject]@{ }
            }
        )
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "a-contributor" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
        )
        $andreasVms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-14)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })
        $communityVms = @(1..5 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_community-$PSItem"
                    TimeCreated = $script:Now.AddHours(-14)
                    Tags        = @{ runnerPool = "community" }
                }
            })
        $script:Vms = @($andreasVms + $communityVms)

        $warnings = . $script:JanitorPath 3>&1 | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }

        @($warnings | Where-Object { $PSItem.Message -like "GitHub activity check failed*" }).Count | Should -Be 1
        $mode | Should -Be "github-unreachable"
        @($script:RemovedVms | Where-Object { $PSItem -like "*andreas*" }).Count | Should -Be 10
        @($script:RemovedVms | Where-Object { $PSItem -like "*community*" }).Count | Should -Be 5
    }

    It "applies the conservative caps when an unreadable completed run is the only possible activity" {
        # The runners are 2h old: past the 1h stale cap, within the 3h and 13h caps.
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "niphlod" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "completed"
                updated_at    = "not a timestamp"
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $script:Now.AddHours(-2)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "activity-unknown"
        $runnerMaxHours | Should -BeIn @(3, 13)
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "does not read a date-only timestamp as midnight" {
        # Read as midnight, today's completed run would look expired and the lane stale.
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "niphlod" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "completed"
                updated_at    = $script:Now.ToString("yyyy-MM-dd")
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $script:Now.AddHours(-2)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "activity-unknown"
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "treats a [do ci] candidate push as unknown when <Case>" -ForEach @(
        @{ Case = "the commit comes back without a message"; Payload = @{ head = "nomessage" }; Messages = @{ "nomessage" = $null } }
        @{ Case = "the push has no head SHA"; Payload = @{ ref = "refs/heads/feature" }; Messages = @{ } }
    ) {
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]$Payload
            }
        )
        $script:CommitMessages = $Messages
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_potato-$PSItem"
                    TimeCreated = $script:Now.AddHours(-2)
                    Tags        = @{ runnerPool = "potatoqualitee" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "activity-unknown"
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "applies the conservative caps when an undatable push is the only possible activity" {
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "niphlod" }
                type       = "PushEvent"
                created_at = "not a timestamp"
                payload    = [pscustomobject]@{ head = "abc" }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $script:Now.AddHours(-2)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "activity-unknown"
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "reads DateTime timestamps under a day-first culture" {
        # PowerShell 7 delivers the GitHub timestamps as DateTime; the 13th fails a
        # culture-bound reparse in en-GB. The clock is frozen on the 13th so the recent
        # push is the only reason the lane is protected; misread, the lane goes stale
        # or falls back to the 3h night cap and its 6h-old runners die.
        $frozenNow = [datetime]::SpecifyKind([datetime]"2026-11-13T03:50:00", [DateTimeKind]::Utc)
        function Get-Date {
            $frozenNow
        }
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "niphlod" }
                type       = "PushEvent"
                created_at = $frozenNow.AddMinutes(-5)
                payload    = [pscustomobject]@{ head = "abc" }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $frozenNow.AddHours(-6)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })

        $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("en-GB")
            . $script:JanitorPath 3>$null | Out-Null
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }

        $mode | Should -Be "active"
        $activeMaintainers | Should -Be @("niphlod")
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "reads the [do ci] marker of a push from its head commit" {
        # The events API sends a push with its head SHA and no commit list.
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "c0ffee"; ref = "refs/heads/feature" }
            }
        )
        $script:CommitMessages = @{ "c0ffee" = "Get-DbaDatabase - Fix a thing [do ci]" }
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_potato-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "potatoqualitee" }
                }
            })

        . $script:JanitorPath | Out-Null

        $activeMaintainers | Should -Be @("potatoqualitee")
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "does not look up pushes of a lane a live run already proves active" {
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "potatoqualitee" }
                display_title = "ci-azure [do ci]"
                event         = "push"
                status        = "in_progress"
                head_commit   = [pscustomobject]@{ message = "Fix a thing [do ci]" }
                updated_at    = $script:Now.ToString("o")
            }
        )
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "unreadable"; ref = "refs/heads/feature" }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_potato-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "potatoqualitee" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $script:CommitLookups | Should -BeNullOrEmpty
        $mode | Should -Be "active"
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "keeps protecting other lanes when a push cannot be read" {
        $script:Runs = @(
            [pscustomobject]@{
                actor         = [pscustomobject]@{ login = "andreasjordan" }
                display_title = "ci-azure"
                event         = "pull_request"
                status        = "in_progress"
                updated_at    = $script:Now.ToString("o")
            }
        )
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "unreadable"; ref = "refs/heads/feature" }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_andreas-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "andreasjordan" }
                }
            })

        $warnings = . $script:JanitorPath 3>&1 | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }

        $script:CommitLookups | Should -Be @("unreadable", "unreadable", "unreadable")
        @($warnings | Where-Object { $PSItem.Message -like "commit lookup for push unreadable failed*" }).Count | Should -Be 1
        $mode | Should -Be "active"
        $activeMaintainers | Should -Be @("andreasjordan")
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "applies the conservative caps when an unreadable push is the only possible activity" {
        # No workflow run lists the push yet. The runners are 2h old: past the 1h stale
        # cap, within the 3h and 13h conservative caps.
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "unreadable"; ref = "refs/heads/feature" }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_potato-$PSItem"
                    TimeCreated = $script:Now.AddHours(-2)
                    Tags        = @{ runnerPool = "potatoqualitee" }
                }
            })

        . $script:JanitorPath 3>$null | Out-Null

        $mode | Should -Be "activity-unknown"
        $runnerMaxHours | Should -BeIn @(3, 13)
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "does not count a push whose head commit lacks the [do ci] marker" {
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "potatoqualitee" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "beef"; ref = "refs/heads/feature" }
            }
        )
        $script:CommitMessages = @{ "beef" = "Get-DbaDatabase - Fix a thing" }

        . $script:JanitorPath | Out-Null

        $mode | Should -Be "stale"
        $activeMaintainers | Should -BeNullOrEmpty
    }

    It "counts a maintainer push from the events feed as activity" {
        $script:Events = @(
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "niphlod" }
                type       = "PushEvent"
                created_at = $script:Now.AddMinutes(-5).ToString("o")
                payload    = [pscustomobject]@{ head = "abc"; commits = @() }
            }
            [pscustomobject]@{
                actor      = [pscustomobject]@{ login = "someone-else" }
                type       = "WatchEvent"
                created_at = $script:Now.AddMinutes(-90).ToString("o")
                payload    = [pscustomobject]@{ }
            }
        )
        $script:Vms = @(1..10 | ForEach-Object {
                [pscustomobject]@{
                    Name        = "dbatools-runners_niph-$PSItem"
                    TimeCreated = $script:Now.AddHours(-6)
                    Tags        = @{ runnerPool = "niphlod" }
                }
            })

        . $script:JanitorPath | Out-Null

        $mode | Should -Be "active"
        $activeMaintainers | Should -Be @("niphlod")
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "deletes only orphaned networking older than the provisioning grace period" {
        $oldNicId = "/subscriptions/test/resourceGroups/dbatools-ci/providers/Microsoft.Network/networkInterfaces/old-Nic-1"
        $youngNicId = "/subscriptions/test/resourceGroups/dbatools-ci/providers/Microsoft.Network/networkInterfaces/young-Nic-1"
        $oldPipId = "/subscriptions/test/resourceGroups/dbatools-ci/providers/Microsoft.Network/publicIPAddresses/instancepublicip-old"
        $youngPipId = "/subscriptions/test/resourceGroups/dbatools-ci/providers/Microsoft.Network/publicIPAddresses/instancepublicip-young"
        $script:Nics = @(
            [pscustomobject]@{
                Name           = "old-Nic-1"
                Id             = $oldNicId
                VirtualMachine = $null
            }
            [pscustomobject]@{
                Name           = "young-Nic-1"
                Id             = $youngNicId
                VirtualMachine = $null
            }
        )
        $script:Pips = @(
            [pscustomobject]@{
                Name            = "instancepublicip-old"
                Id              = $oldPipId
                IpConfiguration = $null
            }
            [pscustomobject]@{
                Name            = "instancepublicip-young"
                Id              = $youngPipId
                IpConfiguration = $null
            }
        )
        $script:ResourceCreatedAt = @{
            $oldNicId   = $script:Now.AddMinutes(-30)
            $youngNicId = $script:Now.AddMinutes(-2)
            $oldPipId   = $script:Now.AddMinutes(-30)
            $youngPipId = $script:Now.AddMinutes(-2)
        }

        . $script:JanitorPath | Out-Null

        $script:RemovedNics | Should -Be @("old-Nic-1")
        $script:RemovedPips | Should -Be @("instancepublicip-old")
    }
}

Describe "janitor against the live GitHub API" {
    # The real Invoke-RestMethod talks to api.github.com, the boundary whose response
    # shape hid the unrolled events feed; only Azure stays stubbed, with an empty
    # resource group so nothing can be deleted.
    BeforeEach {
        $script:RemovedVms = @()

        function Connect-AzAccount {
            param([switch]$Identity, [string]$WarningAction)
        }

        function Get-AzVM {
            param([string]$ResourceGroupName)
        }

        function Remove-AzVM {
            param(
                [string]$ResourceGroupName,
                [string]$Name,
                [switch]$Force
            )
            $script:RemovedVms += $Name
        }

        function Get-AzNetworkInterface {
            param([string]$ResourceGroupName)
        }

        function Get-AzPublicIpAddress {
            param([string]$ResourceGroupName)
        }

        function Get-AzVmss {
            param(
                [string]$ResourceGroupName,
                [string]$VMScaleSetName,
                [string]$ErrorAction
            )
        }
    }

    It "reads the events feed and the workflow runs without falling back" {
        $warnings = . $script:JanitorPath 3>&1 | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }

        @($warnings | Where-Object { $PSItem.Message -like "GitHub activity check failed*" }) | Should -BeNullOrEmpty
        $mode | Should -BeIn @("active", "stale")
        $events.Count | Should -BeGreaterThan 1
        $parsed = @($events | ForEach-Object { ConvertTo-JanitorUtc -Value $PSItem.created_at } | Where-Object { $null -ne $PSItem -and $PSItem -gt $utcNow.AddDays(-120) -and $PSItem -le $utcNow.AddMinutes(5) })
        $parsed.Count | Should -Be $events.Count
        $workflowRuns = @($runResponse.workflow_runs)
        $workflowRuns.Count | Should -BeGreaterThan 1
        $parsedRuns = @($workflowRuns | ForEach-Object { ConvertTo-JanitorUtc -Value $PSItem.updated_at } | Where-Object { $null -ne $PSItem -and $PSItem -gt $utcNow.AddDays(-365) -and $PSItem -le $utcNow.AddMinutes(5) })
        $parsedRuns.Count | Should -Be $workflowRuns.Count
        $script:RemovedVms | Should -BeNullOrEmpty
    }

    It "reads the message of a pushed commit from its head SHA" {
        . $script:JanitorPath 3>$null | Out-Null
        $pushEvent = [pscustomobject]@{
            payload = [pscustomobject]@{ head = "f60caabe92c95a1baa0bd35c1ed546dfa4b345ff" }
        }

        Get-JanitorPushMessage -ActivityEvent $pushEvent | Should -BeLike "Get-DbaUptime - Let the instance measure its uptime*"
    }
}
