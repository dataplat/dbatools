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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDbName = "dbatoolsci_removeagdb_output-$(Get-Random)"
            $outputAgName = "dbatoolsci_removeagdb_outputag"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $outputDbName
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $outputDbName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$outputDbName.bak"
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $outputDbName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$outputDbName.trn" -Type Log

            $splatOutputAg = @{
                Primary       = $TestConfig.InstanceHadr
                Name          = $outputAgName
                ClusterType   = "None"
                FailoverMode  = "Manual"
                Database      = $outputDbName
                Certificate   = "dbatoolsci_AGCert"
                UseLastBackup = $true
            }
            $null = New-DbaAvailabilityGroup @splatOutputAg

            $result = Remove-DbaAgDatabase -SqlInstance $TestConfig.InstanceHadr -Database $outputDbName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $outputAgName -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path "$($TestConfig.Temp)\$outputDbName.bak", "$($TestConfig.Temp)\$outputDbName.trn" -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Database", "Status")
            foreach ($prop in $expectedProperties) {
                $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns the correct Status value" {
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Removed"
        }
    }
}