#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgDatabase",
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
                "AvailabilityGroup",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceHadr -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
        $agname = "dbatoolsci_removeagdb_agroup"
        $dbname = "dbatoolsci_removeagdb_agroupdb-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $dbName
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$dbname.bak"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$dbname.trn" -Type Log

        $splatAvailabilityGroup = @{
            Primary       = $TestConfig.InstanceHadr
            Name          = $agname
            ClusterType   = "None"
            FailoverMode  = "Manual"
            Database      = $dbname
            Certificate   = "dbatoolsci_AGCert"
            UseLastBackup = $true
        }
        $ag = New-DbaAvailabilityGroup @splatAvailabilityGroup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname
        Remove-Item -Path "$($TestConfig.Temp)\$dbname.bak", "$($TestConfig.Temp)\$dbname.trn" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "removes ag db" {
        It "returns removed results" {
            $results = Remove-DbaAgDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Database | Should -Be $dbname
            $results.Status | Should -Be "Removed"
        }

        It "really removed the db from the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.AvailabilityDatabases.Name | Should -Not -Contain $dbname
        }
    }
}