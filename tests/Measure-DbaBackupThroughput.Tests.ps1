#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Measure-DbaBackupThroughput",
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
                "Since",
                "Last",
                "Type",
                "DeviceType",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
        $PSDefaultParameterValues["Backup-DbaDatabase:Path"] = $backupPath

        $randomSuffix = Get-Random
        $testDb = "dbatoolsci_measurethruput$randomSuffix"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDb | Backup-DbaDatabase

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testDb

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Returns output for single database" {
        It "Should return results" {
            $testResults = Measure-DbaBackupThroughput -SqlInstance $TestConfig.InstanceSingle -Database $testDb

            $testResults | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Measure-DbaBackupThroughput -SqlInstance $TestConfig.InstanceSingle -Database $testDb
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "AvgThroughput",
                "AvgSize",
                "AvgDuration",
                "MinThroughput",
                "MaxThroughput",
                "MinBackupDate",
                "MaxBackupDate",
                "BackupCount"
            )
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has DbaSize type for throughput properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].AvgThroughput | Should -BeOfType [DbaSize]
            $result[0].MinThroughput | Should -BeOfType [DbaSize]
            $result[0].MaxThroughput | Should -BeOfType [DbaSize]
        }

        It "Has DbaTimeSpan type for AvgDuration" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].AvgDuration | Should -BeOfType [DbaTimeSpan]
        }

        It "Has DbaDateTime type for date properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].MinBackupDate | Should -BeOfType [DbaDateTime]
            $result[0].MaxBackupDate | Should -BeOfType [DbaDateTime]
        }
    }
}