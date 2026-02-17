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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"

        $dbname = "dbatoolsci_getdbUsage$random"
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname
        $null = $db.Query("CREATE TABLE $tableName (id int)", $dbname)
        $null = $db.Query("CREATE CLUSTERED INDEX [PK_Id] ON $tableName ([id] ASC)", $dbname)
        $null = $db.Query("INSERT $tableName(id) SELECT object_id FROM sys.objects", $dbname)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = "ComputerName", "InstanceName", "SqlInstance", "Database", "Cmd", "Output"
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput"
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
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
        }

        It "returns results for index by id" {
            $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $tableName -Index 1
            $result.Output -match "DBCC execution completed. If DBCC printed error messages, contact your system administrator." | Should -BeTrue
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
                "Cmd",
                "Output"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}