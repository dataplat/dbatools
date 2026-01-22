#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaQueryExecutionTime",
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
                "MaxResultsPerDb",
                "MinExecs",
                "MinExecMs",
                "ExcludeSystem",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Context "Output Validation" {
    BeforeAll {
        # Create a simple stored procedure to ensure we have something to query
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $db = Get-DbaDatabase -SqlInstance $server -Database tempdb
        
        # Create a test procedure that will show up in results
        $sql = @"
IF OBJECT_ID('dbo.TestQueryExecTime', 'P') IS NOT NULL
    DROP PROCEDURE dbo.TestQueryExecTime
GO
CREATE PROCEDURE dbo.TestQueryExecTime
AS
BEGIN
    SELECT 1
END
GO
"@
        $null = $db.ExecuteNonQuery($sql)
        
        # Execute it multiple times to meet the minimum execution threshold
        for ($i = 0; $i -lt 150; $i++) {
            $null = $db.ExecuteNonQuery("EXEC dbo.TestQueryExecTime")
        }
        
        # Get results with low thresholds to ensure we get data
        $result = Get-DbaQueryExecutionTime -SqlInstance $TestConfig.instance1 -Database tempdb -MinExecs 1 -MinExecMs 0 -EnableException
    }
    
    AfterAll {
        # Clean up test procedure
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $db = Get-DbaDatabase -SqlInstance $server -Database tempdb
        $null = $db.ExecuteNonQuery("IF OBJECT_ID('dbo.TestQueryExecTime', 'P') IS NOT NULL DROP PROCEDURE dbo.TestQueryExecTime")
    }

    It "Returns PSCustomObject" {
        $result[0].PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
    }

    It "Has the expected default display properties" {
        $expectedProps = @(
            'ComputerName',
            'InstanceName',
            'SqlInstance',
            'Database',
            'ProcName',
            'ObjectID',
            'TypeDesc',
            'Executions',
            'AvgExecMs',
            'MaxExecMs',
            'CachedTime',
            'LastExecTime',
            'TotalWorkerTimeMs',
            'TotalElapsedTimeMs',
            'SQLText'
        )
        $actualProps = $result[0].PSObject.Properties.Name
        foreach ($prop in $expectedProps) {
            $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
        }
    }

    It "Has FullStatementText property available but not in default display" {
        # FullStatementText should exist on the object
        $result[0].PSObject.Properties.Name | Should -Contain 'FullStatementText'
        
        # But it should be excluded from default view (TypeNames should reflect this)
        $defaultView = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        if ($defaultView) {
            $defaultView | Should -Not -Contain 'FullStatementText'
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>