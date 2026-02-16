#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaExtendedProperty",
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
                "Name",
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
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
        $db.Query("EXEC sys.sp_addextendedproperty @name=N'dbatoolz', @value=N'woo'")
        #$tempdb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
        #$tempdb.Query("EXEC sys.sp_addextendedproperty @name=N'temptoolz', @value=N'woo2'")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $db | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {

        It "finds an extended property on an instance" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2 -OutVariable "global:dbatoolsciOutput"
            $ep.Count | Should -BeGreaterThan 0
        }

        It "finds an extended property in a single database" {
            $ep = Get-DbaExtendedProperty -SqlInstance $server2 -Database $db.Name
            $ep.Parent.Name | Select-Object -Unique | Should -Be $db.Name
            $ep.Count | Should -Be 1
        }

        It "supports piping databases" {
            $ep = $db | Get-DbaExtendedProperty -Name dbatoolz
            $ep.Name | Should -Be "dbatoolz"
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ExtendedProperty]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "ParentName",
                "Type",
                "Name",
                "Value"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.ExtendedProperty"
        }
    }
}