#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbOrphanUser",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Contained database handling" {
            BeforeAll {
                $script:sqlOrphanUser = [PSCustomObject]@{
                    Login     = ""
                    ID        = 5
                    Sid       = [byte[]](1..16)
                    LoginType = "SqlLogin"
                    Name      = "sql_orphan"
                }
                $script:windowsOrphanUser = [PSCustomObject]@{
                    Login     = "CONTOSO\win_orphan"
                    ID        = 6
                    Sid       = [byte[]](1..20)
                    LoginType = "WindowsUser"
                    Name      = "CONTOSO\win_orphan"
                }
                $script:baseServer = [PSCustomObject]@{
                    ComputerName       = "sql1"
                    ServiceName        = "MSSQLSERVER"
                    DomainInstanceName = "sql1"
                    Logins             = @()
                }
            }

            It "skips SQL login orphan detection for contained databases on SQL Server 2012 and newer" {
                $containedDatabase = [PSCustomObject]@{
                    Name            = "containeddb"
                    IsAccessible    = $true
                    ContainmentType = [Microsoft.SqlServer.Management.Smo.ContainmentType]::Partial
                    Users           = @($script:sqlOrphanUser, $script:windowsOrphanUser)
                }
                $server = $script:baseServer | Select-Object *
                $server | Add-Member -NotePropertyName versionMajor -NotePropertyValue 11 -Force
                $server | Add-Member -NotePropertyName Databases -NotePropertyValue @($containedDatabase) -Force

                Mock Connect-DbaInstance {
                    $server
                }
                Mock Stop-Function {
                    throw "Stop-Function called"
                }

                $results = @(Get-DbaDbOrphanUser -SqlInstance "sql2012")

                $results.Count | Should -Be 1
                $results[0].User | Should -Be "CONTOSO\win_orphan"
            }

            It "does not require ContainmentType on pre-SQL 2012 servers" {
                $legacyDatabase = [PSCustomObject]@{
                    Name         = "legacydb"
                    IsAccessible = $true
                    Users        = @($script:sqlOrphanUser)
                }
                $server = $script:baseServer | Select-Object *
                $server | Add-Member -NotePropertyName versionMajor -NotePropertyValue 10 -Force
                $server | Add-Member -NotePropertyName Databases -NotePropertyValue @($legacyDatabase) -Force

                Mock Connect-DbaInstance {
                    $server
                }
                Mock Stop-Function {
                    throw "Stop-Function called"
                }

                $results = @(Get-DbaDbOrphanUser -SqlInstance "sql2008")

                $results.Count | Should -Be 1
                $results[0].User | Should -Be "sql_orphan"
            }
        }
    }
}


Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $loginsq = @"
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
"@
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Invoke-DbaQuery -SqlInstance $server -Query $loginsq
        $usersq = @"
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $usersq -Database dbatoolsci_orphan
        $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
        Invoke-DbaQuery -SqlInstance $server -Query $dropOrphan

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 | Remove-DbaLogin -Force
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When checking for orphan users" {
        BeforeAll {
            $results = @(Get-DbaDbOrphanUser -SqlInstance $TestConfig.InstanceSingle -Database dbatoolsci_orphan)
        }

        It "Shows time taken for preparation" {
            1 | Should -BeExactly 1
        }

        It "Finds two orphans" {
            $results.Count | Should -BeExactly 2
            foreach ($user in $results) {
                $user.User | Should -BeIn @("dbatoolsci_orphan1", "dbatoolsci_orphan2")
                $user.DatabaseName | Should -Be "dbatoolsci_orphan"
            }
        }

        It "Has the correct properties" {
            $result = $results[0]
            $ExpectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "User",
                "SmoUser"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}