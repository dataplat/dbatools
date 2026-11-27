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
                return [pscustomobject]@{ commit = [pscustomobject]@{ message = $script:CommitMessages[$Matches[1]] } }
            }
            [pscustomobject]@{ workflow_runs = $script:Runs }
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

    It "protects no lane when the activity check fails after it marked one active" {
        # The live runs mark andreasjordan and community active before the unreadable
        # timestamp of the last run aborts the check; the runners are past every
        # fallback age cap.
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
                status        = "in_progress"
                updated_at    = "not a timestamp"
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
