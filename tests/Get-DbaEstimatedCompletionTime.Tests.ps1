#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaEstimatedCompletionTime",
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
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# uses a backup that only works on SQL Server 2022
Describe $CommandName -Tag IntegrationTests -Skip:$((-not $TestConfig.BigDatabaseBackup) -or $env:appveyor) {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not (Test-Path -Path $TestConfig.BigDatabaseBackup) -and $TestConfig.BigDatabaseBackupSourceUrl) {
            Invoke-WebRequest -Uri $TestConfig.BigDatabaseBackupSourceUrl -OutFile $TestConfig.BigDatabaseBackup -ErrorAction Stop
        }
        $splatRestore = @{
            SqlInstance         = $TestConfig.instance2
            Path                = $TestConfig.BigDatabaseBackup
            DatabaseName        = "checkdbTestDatabase"
            WithReplace         = $true
            ReplaceDbNameInFile = $true
        }
        $null = Restore-DbaDatabase @splatRestore

        $splatJob = @{
            SqlInstance = $TestConfig.instance2
            Job         = "checkdbTestJob"
        }
        $null = New-DbaAgentJob @splatJob

        $splatJobStep = @{
            SqlInstance = $TestConfig.instance2
            Job         = "checkdbTestJob"
            StepName    = "checkdb"
            Subsystem   = "TransactSql"
            Command     = "DBCC CHECKDB('checkdbTestDatabase')"
        }
        $null = New-DbaAgentJobStep @splatJobStep

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob | Remove-DbaAgentJob
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database checkdbTestDatabase | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets correct results" {
        It "Gets Query Estimated Completion" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match "DBCC"
            $results.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets Query Estimated Completion when using -Database" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2 -Database checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match "DBCC"
            $results.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.instance2 -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.instance2 -ExcludeDatabase checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -BeNullOrEmpty
        }
    }
}