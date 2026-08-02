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
                return $script:Events
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
