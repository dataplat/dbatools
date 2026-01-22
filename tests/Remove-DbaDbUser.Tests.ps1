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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $db = Get-DbaDatabase $server -Database tempdb
            $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
            $loginTest = New-DbaLogin $server -Login dbatoolsci_remove_dba_db_user -Password $securePassword -Force
        }
        BeforeEach {
            $user = New-Object Microsoft.SqlServer.Management.SMO.User($db, $loginTest.Name)
            $user.Login = $loginTest.Name
            $user.Create()
        }
        AfterEach {
            $user = $db.Users[$loginTest.Name]
            if ($user) {
                $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                foreach ($schemaUrn in $schemaUrns) {
                    $schema = $server.GetSmoObject($schemaUrn)
                    $ownedUrns = $schema.EnumOwnedObjects()
                    foreach ($ownedUrn in $ownedUrns) {
                        $obj = $server.GetSmoObject($ownedUrn)
                        $obj.Drop()
                    }
                    $schema.Drop()
                }
                $user.Drop()
            }
        }
        AfterAll {
            if ($loginTest) {
                $loginTest.Drop()
            }
        }

        It "drops a user with no ownerships" {
            Remove-DbaDbUser $server -Database tempdb -User $user.Name
            $db.Users[$user.Name] | Should -BeNullOrEmpty
        }

        It "drops a user with a schema of the same name, but no objects owned by the schema" {
            $schema = New-Object Microsoft.SqlServer.Management.SMO.Schema($db, $user.Name)
            $schema.Owner = $user.Name
            $schema.Create()
            Remove-DbaDbUser $server -Database tempdb -User $user.Name
            $db.Users[$user.Name] | Should -BeNullOrEmpty
        }

        It "does NOT drop a user that owns objects other than a schema" {
            $schema = New-Object Microsoft.SqlServer.Management.SMO.Schema($db, $user.Name)
            $schema.Owner = $user.Name
            $schema.Create()
            $table = New-Object Microsoft.SqlServer.Management.SMO.Table($db, "dbtoolsci_remove_dba_db_user", $user.Name)
            $col1 = New-Object Microsoft.SqlServer.Management.SMO.Column($table, "col1", [Microsoft.SqlServer.Management.SMO.DataType]::Int)
            $table.Columns.Add($col1)
            $table.Create()
            Remove-DbaDbUser $server -Database tempdb -User $user.Name -WarningAction SilentlyContinue
            $db.Users[$user.Name] | Should -Be $user
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $db = Get-DbaDatabase $server -Database tempdb
            $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
            $loginTest = New-DbaLogin $server -Login dbatoolsci_remove_dba_db_user_output -Password $securePassword -Force
            $user = New-Object Microsoft.SqlServer.Management.SMO.User($db, $loginTest.Name)
            $user.Login = $loginTest.Name
            $user.Create()
            
            $result = Remove-DbaDbUser -SqlInstance $server -Database tempdb -User $user.Name -EnableException
        }
        AfterAll {
            if ($loginTest) {
                $loginTest.Drop()
            }
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'User',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has Status property set to 'Dropped' on successful removal" {
            $result.Status | Should -Be 'Dropped'
        }
    }
}