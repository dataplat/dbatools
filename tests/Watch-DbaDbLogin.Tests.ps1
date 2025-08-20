#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Watch-DbaDbLogin",
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
                "Table",
                "SqlCredential",
                "SqlCms",
                "ServersFromFile",
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

        $random = Get-Random

        $tableName1 = "dbatoolsciwatchdblogin1"
        $tableName2 = "dbatoolsciwatchdblogin2"
        $tableName3 = "dbatoolsciwatchdblogin3"
        $databaseName = "dbatoolsci_$random"
        $newDb = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $databaseName

        $testFile = "$($TestConfig.Temp)\Servers_$random.txt"
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force
        }

        $TestConfig.instance1, $TestConfig.instance2 | Out-File $testFile

        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        $regServer1 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $TestConfig.instance1 -Name "dbatoolsci_instance1_$random"
        $regServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $TestConfig.instance2 -Name "dbatoolsci_instance2_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $newDb | Remove-DbaDatabase -Confirm:$false
        Get-DbaRegServer -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Remove-Item -Path $testFile -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command actually works" {

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName1 -ServersFromFile $testFile -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName1 -IncludeSystemDBs
            $result.Name | Should -Be $tableName1
            $result.Status.Count | Should -BeGreaterThan 0
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName2 -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName2 -IncludeSystemDBs
            $result.Name | Should -Be $tableName2
            $result.Status.Count | Should -BeGreaterThan 0
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName3 -SqlCms $TestConfig.instance1 -EnableException
            $result = Get-DbaDbTable -SqlInstance $TestConfig.instance1 -Database $databaseName -Table $tableName3 -IncludeSystemDBs
            $result.Name | Should -Be $tableName3
            $result.Status.Count | Should -BeGreaterThan 0
        }
    }
}