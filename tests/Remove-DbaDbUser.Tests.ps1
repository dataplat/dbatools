param($ModuleName = 'dbatools')

Describe "Remove-DbaDbUser Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Importing the function if needed
        # . "$PSScriptRoot\$ModuleName.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Remove-DbaDbUser'
            $command = Get-Command -Name $CommandName
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "User",
                "InputObject",
                "Force",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $command | Should -HaveParameter $param
            }
        }
    }
}

Describe "Remove-DbaDbUser Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $global:instance1 = "localhost"
    }

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $db = Get-DbaDatabase $server -Database tempdb
        $securePassword = ConvertTo-SecureString "password" -AsPlainText -Force
        $loginTest = New-DbaLogin $server -Login dbatoolsci_remove_dba_db_user -Password $securePassword -Force
    }

    AfterAll {
        if ($loginTest) {
            $loginTest.Drop()
        }
    }

    Context "Verifying User is removed" {
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

        It "drops a user with no ownerships" {
            Remove-DbaDbUser -SqlInstance $server -Database tempdb -User $user.Name
            $db.Users[$user.Name] | Should -BeNullOrEmpty
        }

        It "drops a user with a schema of the same name, but no objects owned by the schema" {
            $schema = New-Object Microsoft.SqlServer.Management.SMO.Schema($db, $user.Name)
            $schema.Owner = $user.Name
            $schema.Create()
            Remove-DbaDbUser -SqlInstance $server -Database tempdb -User $user.Name
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
            Remove-DbaDbUser -SqlInstance $server -Database tempdb -User $user.Name -WarningAction SilentlyContinue
            $db.Users[$user.Name] | Should -Be $user
        }
    }
}
