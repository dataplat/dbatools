#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbDbccUpdateUsage",
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
                "Table",
                "Index",
                "NoInformationalMessages",
                "CountRows",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"

        $dbname = "dbatoolsci_getdbUsage$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbname
        $null = $db.Query("CREATE TABLE $tableName (id int)", $dbname)
        $null = $db.Query("CREATE CLUSTERED INDEX [PK_Id] ON $tableName ([id] ASC)", $dbname)
        $null = $db.Query("INSERT $tableName(id) SELECT object_id FROM sys.objects", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = "ComputerName", "InstanceName", "SqlInstance", "Database", "Cmd", "Output"
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.instance1 -Confirm:$false
        }

        It "returns results" {
            $result.Count -gt 0 | Should -BeTrue
        }

        It "Should return all required properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate returns results" {
        It "returns results for table" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.instance1 -Database $dbname -Table $tableName -Confirm:$false
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
        }

        It "returns results for index by id" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.instance1 -Database $dbname -Table $tableName -Index 1 -Confirm:$false
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
        }
    }

}