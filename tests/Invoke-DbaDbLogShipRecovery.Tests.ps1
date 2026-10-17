#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbLogShipRecovery",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Database",
                "SqlCredential",
                "NoRecovery",
                "EnableException",
                "Force",
                "InputObject",
                "Delay"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When the database is not a log shipping secondary" {
        BeforeAll {
            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id with records but without a completed one. master is never a log shipping secondary, so
            # the command draws its bar, warns and moves on to the next database without changing anything.
            # The runspace imports the manifest: an import of the psm1 without a command line skips the type data.
            $splatRecovery = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "master"
            }
            if ($TestConfig.SqlCred) {
                $splatRecovery.SqlCredential = $TestConfig.SqlCred
            }
            $recoveryRunspace = [runspacefactory]::CreateRunspace()
            $recoveryRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $recoveryRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $recoveryShell = [powershell]::Create()
            $recoveryShell.Runspace = $recoveryRunspace
            $null = $recoveryShell.AddCommand("Invoke-DbaDbLogShipRecovery").AddParameters($splatRecovery).Invoke()
            $recoveryWarnings = @($recoveryShell.Streams.Warning | ForEach-Object { $PSItem.Message })
            $recoveryRecords = @($recoveryShell.Streams.Progress)
            $recoveryShell.Dispose()
            $recoveryRunspace.Dispose()
        }

        It "Warns that the database is not a log shipping secondary" {
            ($recoveryWarnings -join " ") | Should -Match "is not configured as a secondary database for log shipping"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $recoveryRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $recoveryRecords | Where-Object Activity -like "Performing log shipping recovery*" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }

    Context "When neither -Database nor -Force is given" {
        It "Names the instance in the error" {
            # The target was $server.name, and $server is only set further down.
            $stopError = $null
            try {
                Invoke-DbaDbLogShipRecovery -SqlInstance $TestConfig.InstanceSingle -EnableException
            } catch {
                $stopError = $PSItem
            }
            $stopError | Should -Not -BeNullOrEmpty
            "$($stopError.TargetObject)" | Should -Be "$($TestConfig.InstanceSingle)"
        }
    }

    Context "When a log shipping secondary is recovered" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $primaryDatabase = "dbatoolsci_lsrecovery_$(Get-Random)"
            $secondaryDatabase = "$($primaryDatabase)_ls"
            $sharedPath = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_lsrecovery_$(Get-Random)"
            $null = New-Item -Path $sharedPath -ItemType Directory
            $copyDestinationFolder = Join-Path -Path $sharedPath -ChildPath "copy"
            $null = New-Item -Path $copyDestinationFolder -ItemType Directory
            # The setup follows the one in Invoke-DbaDbLogShipping.Tests.ps1: the command accepts the shared path only in
            # the form \\server\share. In the lab $TestConfig.Temp is a share already. On CI it is a local folder on the
            # runner, which also hosts the instance, so the administrative share of the drive names the same folder.
            $sharedPathUnc = $sharedPath -replace "^(.):", "\\$env:COMPUTERNAME\`$1`$"

            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $primaryDatabase -RecoveryModel Full
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $primaryDatabase -Path $sharedPath -Type Full
            $splatLogShipping = @{
                SourceSqlInstance       = $TestConfig.InstanceSingle
                DestinationSqlInstance  = $TestConfig.InstanceSingle
                Database                = $primaryDatabase
                SharedPath              = $sharedPathUnc
                IgnoreFileChecks        = $true
                CopyDestinationFolder   = $copyDestinationFolder
                UseExistingFullBackup   = $true
                SecondaryDatabaseSuffix = "_ls"
            }
            $null = Invoke-DbaDbLogShipping @splatLogShipping

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The RESTORE WITH RECOVERY at the end ran through Query(), which returns a $null for a statement without a
            # result set, so the output started with a $null.
            $recoveryResults = @(Invoke-DbaDbLogShipRecovery -SqlInstance $TestConfig.InstanceSingle -Database $secondaryDatabase)
            $recoveryWarning = $WarnVar
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatRemoveLogShipping = @{
                PrimarySqlInstance      = $TestConfig.InstanceSingle
                SecondarySqlInstance    = $TestConfig.InstanceSingle
                Database                = $primaryDatabase
                RemoveSecondaryDatabase = $true
            }
            $null = Remove-DbaDbLogShipping @splatRemoveLogShipping -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $primaryDatabase, $secondaryDatabase -ErrorAction SilentlyContinue
            Remove-Item -Path $sharedPath -Recurse -Force -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns one result for the database and nothing else" {
            $recoveryWarning | Should -BeNullOrEmpty
            $recoveryResults.Count | Should -Be 1
            $recoveryResults[0].Database | Should -Be $secondaryDatabase
            $recoveryResults[0].RecoverResult | Should -Be "Success"
        }

        It "Brings the database online" {
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $secondaryDatabase).Status | Should -Be "Normal"
        }
    }
}