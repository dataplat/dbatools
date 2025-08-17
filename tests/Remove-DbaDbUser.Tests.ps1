#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbUser",
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
                "User",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying User is removed" {
        BeforeAll {
            $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $global:db = Get-DbaDatabase $global:server -Database tempdb
            $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
            $global:loginTest = New-DbaLogin $global:server -Login dbatoolsci_remove_dba_db_user -Password $securePassword -Force
        }
        BeforeEach {
            $global:user = New-Object Microsoft.SqlServer.Management.SMO.User($global:db, $global:loginTest.Name)
            $global:user.Login = $global:loginTest.Name
            $global:user.Create()
        }
        AfterEach {
            $user = $global:db.Users[$global:loginTest.Name]
            if ($user) {
                $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                foreach ($schemaUrn in $schemaUrns) {
                    $schema = $global:server.GetSmoObject($schemaUrn)
                    $ownedUrns = $schema.EnumOwnedObjects()
                    foreach ($ownedUrn in $ownedUrns) {
                        $obj = $global:server.GetSmoObject($ownedUrn)
                        $obj.Drop()
                    }
                    $schema.Drop()
                }
                $user.Drop()
            }
        }
        AfterAll {
            if ($global:loginTest) {
                $global:loginTest.Drop()
            }
        }

        It "drops a user with no ownerships" {
            Remove-DbaDbUser $global:server -Database tempdb -User $global:user.Name
            $global:db.Users[$global:user.Name] | Should -BeNullOrEmpty
        }

        It "drops a user with a schema of the same name, but no objects owned by the schema" {
            $schema = New-Object Microsoft.SqlServer.Management.SMO.Schema($global:db, $global:user.Name)
            $schema.Owner = $global:user.Name
            $schema.Create()
            Remove-DbaDbUser $global:server -Database tempdb -User $global:user.Name
            $global:db.Users[$global:user.Name] | Should -BeNullOrEmpty
        }

        It "does NOT drop a user that owns objects other than a schema" {
            $schema = New-Object Microsoft.SqlServer.Management.SMO.Schema($global:db, $global:user.Name)
            $schema.Owner = $global:user.Name
            $schema.Create()
            $table = New-Object Microsoft.SqlServer.Management.SMO.Table($global:db, "dbtoolsci_remove_dba_db_user", $global:user.Name)
            $col1 = New-Object Microsoft.SqlServer.Management.SMO.Column($table, "col1", [Microsoft.SqlServer.Management.SMO.DataType]::Int)
            $table.Columns.Add($col1)
            $table.Create()
            Remove-DbaDbUser $global:server -Database tempdb -User $global:user.Name -WarningAction SilentlyContinue
            $global:db.Users[$global:user.Name] | Should -Be $global:user
        }
    }
}