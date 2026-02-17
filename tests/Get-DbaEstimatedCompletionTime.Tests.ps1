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
        It "Gets Query Estimated Completion" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match "DBCC"
            $results.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets Query Estimated Completion when using -Database" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle -Database checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -Not -BeNullOrEmpty
            $results.Command | Should -Match "DBCC"
            $results.Database | Should -Be "checkdbTestDatabase"
        }

        It "Gets no Query Estimated Completion when using -ExcludeDatabase" {
            $job = Start-DbaAgentJob -SqlInstance $TestConfig.InstanceSingle -Job checkdbTestJob
            Start-Sleep -Seconds 1
            $results = Get-DbaEstimatedCompletionTime -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase checkdbTestDatabase
            while ($job.CurrentRunStatus -eq "Executing") {
                Start-Sleep -Seconds 1
                $job.Refresh()
            }

            $results | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
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
                "EstimatedCompletionTime",
                "Text"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
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
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}