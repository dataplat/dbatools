#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbTable",
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
                "IncludeSystemDBs",
                "Table",
                "EnableException",
                "InputObject",
                "Schema"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Configuration handling" {
        It "Only calls ClearAndInitialize when the config is enabled" {
            $commandAst = (Get-Command $CommandName).ScriptBlock.Ast
            $clearAndInitializeCalls = $commandAst.FindAll( {
                    param($Ast)

                    $Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Ast.Member.Extent.Text -eq "ClearAndInitialize"
                }, $true)

            $clearAndInitializeCalls.Count | Should -Be 1

            $parentAst = $clearAndInitializeCalls[0].Parent
            while ($parentAst -and $parentAst -isnot [System.Management.Automation.Language.IfStatementAst]) {
                $parentAst = $parentAst.Parent
            }

            $parentAst | Should -Not -BeNullOrEmpty
            $parentAst.Clauses[0].Item1.Extent.Text | Should -Match "Get-DbatoolsConfigValue"
            $parentAst.Clauses[0].Item1.Extent.Text | Should -Match "commands.get-dbadbtable.clearandinitialize"
        }
    }

    Context "Azure SQL handling" {
        It "Only adds space usage properties to the default view for non-Azure instances" {
            $commandAst = (Get-Command $CommandName).ScriptBlock.Ast
            $defaultPropsAssignments = $commandAst.FindAll( {
                    param($Ast)

                    $Ast -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Ast.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Ast.Left.VariablePath.UserPath -eq "defaultProps"
                }, $true)

            $defaultPropsAssignments.Count | Should -Be 1

            $expectedDefaultProps = @"
[System.Collections.ArrayList]@("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name")
"@.Trim()
            $defaultPropsAssignments[0].Right.Expression.Extent.Text | Should -Be $expectedDefaultProps

            $spacePropertyAdds = $commandAst.FindAll( {
                    param($Ast)

                    $Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Ast.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Ast.Expression.VariablePath.UserPath -eq "defaultProps" -and
                    $Ast.Member.Extent.Text -eq "Add" -and
                    $Ast.Arguments.Count -eq 1 -and
                    $Ast.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $Ast.Arguments[0].Value -in ("IndexSpaceUsed", "DataSpaceUsed")
                }, $true)

            $spacePropertyAdds.Count | Should -Be 2

            foreach ($spacePropertyAdd in $spacePropertyAdds) {
                $parentAst = $spacePropertyAdd.Parent
                while ($parentAst -and $parentAst -isnot [System.Management.Automation.Language.IfStatementAst]) {
                    $parentAst = $parentAst.Parent
                }

                $parentAst | Should -Not -BeNullOrEmpty
                $conditionAst = $parentAst.Clauses[0].Item1.PipelineElements[0].Expression

                $conditionAst.Left.Expression.VariablePath.UserPath | Should -Be "server"
                $conditionAst.Left.Member.Extent.Text | Should -Be "DatabaseEngineType"
                $conditionAst.Operator | Should -Be "Ine"
                $conditionAst.Right.Value | Should -Be "SqlAzureDatabase"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $tablename = "dbatoolssci_$(Get-Random)"

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname -Owner sa
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "Create table $tablename (col1 int)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should get the table" {
        It "Gets the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
        }

        It "Gets the table when you specify the database" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
        }
    }

    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
        }
    }
}