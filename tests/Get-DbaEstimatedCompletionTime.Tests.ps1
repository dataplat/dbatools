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

Describe $CommandName -Tag IntegrationTests -Skip:$((-not $TestConfig.BigDatabaseBackup) -or $env:appveyor) {
    # Skip IntegrationTests on AppVeyor because the backup we use only works on SQL Server 2022 and skip if no BigDatabaseBackup is configured.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if (-not (Test-Path -Path $TestConfig.BigDatabaseBackup) -and $TestConfig.BigDatabaseBackupSourceUrl) {
            Invoke-TlsWebRequest -Uri $TestConfig.BigDatabaseBackupSourceUrl -OutFile $TestConfig.BigDatabaseBackup -ErrorAction Stop
        }
        $splatRestore = @{
            SqlInstance         = $TestConfig.InstanceSingle
            Path                = $TestConfig.BigDatabaseBackup
            DatabaseName        = "checkdbTestDatabase"
            WithReplace         = $true
            ReplaceDbNameInFile = $true
        }
        $null = Restore-DbaDatabase @splatRestore

        $splatJob = @{
            SqlInstance = $TestConfig.InstanceSingle
            Job         = "checkdbTestJob"
        }
        $null = New-DbaAgentJob @splatJob

        $splatJobStep = @{
            SqlInstance = $TestConfig.InstanceSingle
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
        $null = Get-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob | Remove-DbaAgentJob
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database checkdbTestDatabase | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets correct results" {
        BeforeAll {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }
        }

        It "Gets Query Estimated Completion" {
            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match "DBCC"
            $results.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets Query Estimated Completion when using -Database" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $resultsWithDb = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle -Database checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $resultsWithDb | Should -Not -BeNullOrEmpty
            $resultsWithDb.Command | Should -Match "DBCC"
            $resultsWithDb.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $resultsExcluded = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $resultsExcluded | Should -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Login",
                "Command",
                "PercentComplete",
                "StartTime",
                "RunningTime",
                "EstimatedTimeToGo",
                "EstimatedCompletionTime"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has Text property excluded from default display" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "Text" -Because "Text should be excluded from default display"
        }
    }
}