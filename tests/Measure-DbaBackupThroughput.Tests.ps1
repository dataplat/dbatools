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
    Context "Returns output for single database" {
        It "Should return results" {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Get-DbaProcess -SqlInstance $TestConfig.instance2 | Where-Object Program -Match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $randomSuffix = Get-Random
            $testDb = "dbatoolsci_measurethruput$randomSuffix"
            $backupFilePath = "$($TestConfig.Temp)\$($testDb).bak"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDb | Backup-DbaDatabase -FilePath $backupFilePath

            # Get the test results for use in It blocks
            $testResults = Measure-DbaBackupThroughput -SqlInstance $TestConfig.instance2 -Database $testDb

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            try {
                $testResults.Database | Should -Be $testDb
                $testResults.BackupCount | Should -Be 1
            } finally {
                # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

                $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $testDb -Confirm:$false
                Remove-Item -Path $backupFilePath -ErrorAction SilentlyContinue
            }
        }
    }
}