#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Get-DbaReplPublication",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

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
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Code Validation" {
            BeforeAll {
                Mock Connect-ReplicationDB -MockWith {
                    [object] @{
                                                Name              = "TestDB"
                        TransPublications = @{
                                                        Name         = "TestDB_pub"
                                                        Type         = "Transactional"
                            DatabaseName = "TestDB"
                        }
                        MergePublications = @{ }
                    }
                }

                Mock Connect-DbaInstance -MockWith {
                    [object] @{
                                                Name               = "MockServerName"
                                                ServiceName        = "MSSQLSERVER"
                        DomainInstanceName = "MockServerName"
                                                ComputerName       = "MockComputerName"
                                                Databases          = @{
                                                    Name               = "TestDB"
                        #state
                        #status
                                                    ID                 = 5
                        ReplicationOptions = "Published"
                                                    IsAccessible       = $true
                                                    IsSystemObject     = $false
                    }
                                            ConnectionContext  = @{
                    SqlConnectionObject = "FakeConnectionContext"
                }
            }
        }
    }

    It "Honors the SQLInstance parameter" {
        $Results = Get-DbaReplPublication -SqlInstance MockServerName
        $Results.SqlInstance.Name | Should -Be "MockServerName"
    }

    It "Honors the Database parameter" {
        $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB
        $Results.DatabaseName | Should -Be "TestDB"
    }

    It "Honors the Type parameter" {
        Mock Connect-ReplicationDB -MockWith {
            [object] @{
                                        Name              = "TestDB"
                TransPublications = @{
                    Name = "TestDB_pub"
                    Type = "Snapshot"
                }
                MergePublications = @{ }
            }
        }

        $Results = Get-DbaReplPublication -SqlInstance MockServerName -Database TestDB -Type Snapshot
        $Results.Type | Should -Be "Snapshot"
    }

    It "Stops if validate set for Type is not met" {
        { Get-DbaReplPublication -SqlInstance MockServerName -Type NotAPubType } | Should -Throw
    }
}
}
}