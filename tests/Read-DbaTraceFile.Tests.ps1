#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Read-DbaTraceFile",
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
                "Path",
                "Database",
                "Login",
                "Spid",
                "EventClass",
                "ObjectType",
                "ErrorId",
                "EventSequence",
                "TextData",
                "ApplicationName",
                "ObjectName",
                "Where",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command output" {
        It "returns results" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.instance2 -Id 1 | Read-DbaTraceFile
            $results.DatabaseName.Count | Should -BeGreaterThan 0
        }

        It "supports where for multiple servers" {
            $where = "DatabaseName is not NULL
                    and DatabaseName != 'tempdb'
                    and ApplicationName != 'SQLServerCEIP'
                    and ApplicationName != 'Report Server'
                    and ApplicationName not like 'dbatools%'
                    and ApplicationName not like 'SQLAgent%'
                    and ApplicationName not like 'Microsoft SQL Server Management Studio%'"

            # Collect the results into a variable so that the bulk import is super fast
            Get-DbaTrace -SqlInstance $TestConfig.instance2 -Id 1 | Read-DbaTraceFile -Where $where -WarningAction SilentlyContinue -WarningVariable warn > $null
            $warn | Should -BeNullOrEmpty
        }
    }
    Context "Verify Parameter Use" {
        It "Should execute using parameters Database, Login, Spid" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.instance2 -Id 1 | Read-DbaTraceFile -Database Master -Login sa -Spid 7 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
        It "Should execute using parameters EventClass, ObjectType, ErrorId" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.instance2 -Id 1 | Read-DbaTraceFile -EventClass 4 -ObjectType 4 -ErrorId 4 -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
        It "Should execute using parameters EventSequence, TextData, ApplicationName, ObjectName" {
            $results = Get-DbaTrace -SqlInstance $TestConfig.instance2 -Id 1 | Read-DbaTraceFile -EventSequence 4 -TextData "Text" -ApplicationName "Application" -ObjectName "Name" -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -BeNullOrEmpty
        }
    }
}