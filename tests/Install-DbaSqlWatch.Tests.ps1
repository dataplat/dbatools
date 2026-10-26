#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaSqlWatch",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "LocalFile",
                "Force",
                "PreRelease",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5 -or $env:appveyor) {
    # Skip IntegrationTests on AppVeyor because they take too long and skip on pwsh because the command is not supported.

    # The SqlWatch dacpac contains a case insensitive model and DacFx refuses to deploy that to a case sensitive
    # target (error SQL72030), so the installer cannot work there and the Context below skips. We ask the instance
    # for the behaviour instead of matching the collation name, because _BIN and _BIN2 collations are case sensitive
    # too and carry no _CS_. A failed probe leaves the skip off so a real connection problem still fails the tests loudly.
    $sqlWatchInstanceIsCaseSensitive = $false
    try {
        $sqlWatchCaseQuery = "SELECT CASE WHEN EXISTS (SELECT 1 FROM sys.databases WHERE name = UPPER(DB_NAME(1))) THEN 0 ELSE 1 END AS IsCaseSensitive"
        $sqlWatchInstanceIsCaseSensitive = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $sqlWatchCaseQuery -EnableException).IsCaseSensitive -eq 1
    } catch {
        $sqlWatchInstanceIsCaseSensitive = $false
    }

    Context "Testing SqlWatch installer" -Skip:$sqlWatchInstanceIsCaseSensitive {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_sqlwatch_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $database")

            $results = Install-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Uninstall-DbaSqlWatch -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $results[0].Database -eq $database | Should -Be $true
        }
        It "Returns an object with the expected properties" {
            $result = $results[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Database", "Status", "DashboardPath"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Installed tables" {
            $tableCount = (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "sqlwatch_*").Count
            $tableCount | Should -BeGreaterThan 0
        }
        It "Installed views" {
            $viewCount = (Get-DbaDbView -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "vw_sqlwatch_*").Count
            $viewCount | Should -BeGreaterThan 0
        }
        It "Installed stored procedures" {
            $sprocCount = (Get-DbaDbStoredProcedure -SqlInstance $TestConfig.InstanceSingle -Database $database | Where-Object Name -like "usp_sqlwatch_*").Count
            $sprocCount | Should -BeGreaterThan 0
        }
        It "Installed SQL Agent jobs" {
            $agentCount = (Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle | Where-Object { ($PSItem.Name -like "SqlWatch-*") -or ($PSItem.Name -like "DBA-PERF-*") }).Count
            $agentCount | Should -BeGreaterThan 0
        }

    }

    Context "When the pipeline is stopped" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $stopDatabase = "dbatoolsci_sqlwatchstop_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $stopDatabase
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The command runs in a runspace of its own, created by the PowerShell API without a host. There
            # Write-Progress puts every record into Streams.Progress, so a bar that was never completed shows
            # as an Id whose last record is not a completed one. The pipeline is stopped as soon as the first
            # record arrives, which is what Ctrl+C does, before the dacpac is published. The runspace imports
            # the manifest: an import of the psm1 without a command line skips the type data.
            $splatStopInstall = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $stopDatabase
                Confirm     = $false
            }
            if ($TestConfig.SqlCred) {
                $splatStopInstall.SqlCredential = $TestConfig.SqlCred
            }
            $stopRunspace = [runspacefactory]::CreateRunspace()
            $stopRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $stopRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $stopShell = [powershell]::Create()
            $stopShell.Runspace = $stopRunspace
            $null = $stopShell.AddCommand("Install-DbaSqlWatch").AddParameters($splatStopInstall)
            $stopAsync = $stopShell.BeginInvoke()
            $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not ($stopShell.Streams.Progress | Where-Object Activity -eq "Installing SQLWatch") -and -not $stopAsync.IsCompleted -and $stopWatch.Elapsed.TotalSeconds -lt 120) {
                Start-Sleep -Milliseconds 10
            }
            $stopShell.Stop()
            $stopState = $stopShell.InvocationStateInfo.State
            $stopRecords = @($stopShell.Streams.Progress)
            $stopShell.Dispose()
            $stopRunspace.Dispose()
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The stopped run did not get to publish SqlWatch, so there is nothing to uninstall: Uninstall-DbaSqlWatch
            # would throw here and keep the database from being removed.
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $stopDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Was stopped while it was running" {
            $stopState | Should -Be "Stopped"
        }

        It "Completes its progress bar" {
            # An Id stays on screen when its last record is not a completed one. Windows PowerShell completes its
            # own bar for loading modules with Id 0 as well, so a completed record somewhere is not enough.
            $openIds = $stopRecords | Group-Object -Property ActivityId | Where-Object { @($PSItem.Group)[-1].RecordType -ne "Completed" } | Select-Object -ExpandProperty Name
            $stopRecords | Where-Object Activity -eq "Installing SQLWatch" | Should -Not -BeNullOrEmpty
            $openIds | Should -BeNullOrEmpty
        }
    }
}