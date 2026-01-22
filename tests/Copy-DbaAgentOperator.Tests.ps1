#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentOperator",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Operator",
                "ExcludeOperator",
                "Force",
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

        # Set variables. They are available in all the It blocks.
        $operatorName1 = "dbatoolsci_operator"
        $operatorName2 = "dbatoolsci_operator2"

        # Create the operators on the source server.
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $sqlAddOperator1 = "EXEC msdb.dbo.sp_add_operator @name=N'$operatorName1', @enabled=1, @pager_days=0"
        $null = $sourceServer.Query($sqlAddOperator1)
        $sqlAddOperator2 = "EXEC msdb.dbo.sp_add_operator @name=N'$operatorName2', @enabled=1, @pager_days=0"
        $null = $sourceServer.Query($sqlAddOperator2)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $sourceCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -ErrorAction SilentlyContinue
        $sqlDeleteOp1Source = "EXEC msdb.dbo.sp_delete_operator @name=N'$operatorName1'"
        $null = $sourceCleanupServer.Query($sqlDeleteOp1Source)
        $sqlDeleteOp2Source = "EXEC msdb.dbo.sp_delete_operator @name=N'$operatorName2'"
        $null = $sourceCleanupServer.Query($sqlDeleteOp2Source)

        $destCleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -ErrorAction SilentlyContinue
        $sqlDeleteOp1Dest = "EXEC msdb.dbo.sp_delete_operator @name=N'$operatorName1'"
        $null = $destCleanupServer.Query($sqlDeleteOp1Dest)
        $sqlDeleteOp2Dest = "EXEC msdb.dbo.sp_delete_operator @name=N'$operatorName2'"
        $null = $destCleanupServer.Query($sqlDeleteOp2Dest)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying operators" {
        It "Returns two copied operators" {
            $splatCopyOperators = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Operator    = @($operatorName1, $operatorName2)
            }
            $results = Copy-DbaAgentOperator @splatCopyOperators
            $results.Status.Count | Should -Be 2
            $results.Status | Should -Be @("Successful", "Successful")
        }

        It "Returns one result that's skipped when copying an existing operator" {
            $splatCopyExisting = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Operator    = $operatorName1
            }
            $copyResult = Copy-DbaAgentOperator @splatCopyExisting
            $copyResult.Status | Should -Be "Skipped"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $splatCopyOperator = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Operator    = $operatorName2
                Force       = $true
            }
            $result = Copy-DbaAgentOperator @splatCopyOperator
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject with MigrationObject type" {
            $result.PSObject.TypeNames | Should -Contain 'MigrationObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'DateTime',
                'SourceServer',
                'DestinationServer',
                'Name',
                'Type',
                'Status',
                'Notes'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Type property set to 'Agent Operator'" {
            $result.Type | Should -Be "Agent Operator"
        }

        It "Has Status property with valid values" {
            $result.Status | Should -BeIn @('Successful', 'Skipped', 'Failed')
        }
    }
}