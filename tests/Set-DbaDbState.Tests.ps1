#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbState",
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
                "AllDatabases",
                "ReadOnly",
                "ReadWrite",
                "Online",
                "Offline",
                "Emergency",
                "Detached",
                "SingleUser",
                "RestrictedUser",
                "MultiUser",
                "Force",
                "EnableException",
                "InputObject"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Parameters validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $db1 = "dbatoolsci_dbsetstate_online"
            $server.Query("CREATE DATABASE $db1")
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db1
        }
        It "Stops if no Database or AllDatabases" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw -ExpectedMessage "*You must specify*"
        }
        # TODO: The output should write a normal warning, but does not.
        It -Skip "Is nice by default" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue
            $WarVar | Should -BeLike "*You must specify*"
        }
        It "Errors out when multiple 'access' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -SingleUser -RestrictedUser -EnableException } | Should -Throw -ExpectedMessage "*You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser*"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -MultiUser -RestrictedUser -EnableException } | Should -Throw -ExpectedMessage "*You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser*"
        }
        # TODO: The output should write a normal warning, but does not.
        It -Skip "Errors out when multiple 'access' params are passed without EnableException" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -SingleUser -RestrictedUser -WarningAction SilentlyContinue
            $WarVar | Should -BeLike "*You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser*"
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -MultiUser -RestrictedUser -WarningAction SilentlyContinue
            $WarVar | Should -BeLike "*You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser*"
        }
        It "Errors out when multiple 'status' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Offline -Online -EnableException } | Should -Throw -ExpectedMessage "*You can only specify one of: -Online,-Offline,-Emergency,-Detached*"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Emergency -Online -EnableException } | Should -Throw -ExpectedMessage "*You can only specify one of: -Online,-Offline,-Emergency,-Detached*"
        }
        # TODO: The output should write a normal warning, but does not.
        It -Skip "Errors out when multiple 'status' params are passed without Silent" {
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Offline -Online -WarningAction SilentlyContinue
            $WarVar | Should -BeLike "*You can only specify one of: -Online,-Offline,-Emergency,-Detached*"
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Emergency -Online -WarningAction SilentlyContinue
            $WarVar | Should -BeLike "*You can only specify one of: -Online,-Offline,-Emergency,-Detached*"
        }
        It "Errors out when multiple 'rw' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -ReadOnly -ReadWrite -EnableException } | Should -Throw -ExpectedMessage "*You can only specify one of: -ReadOnly,-ReadWrite*"
        }
        # TODO: The output should write a normal warning, but does not.
        It -Skip "Errors out when multiple 'rw' params are passed without EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -ReadOnly -ReadWrite *> $null } | Should -Throw -ExpectedMessage "*You can only specify one of: -ReadOnly,-ReadWrite*"
        }
    }
    Context "Operations on databases" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $db1 = "dbatoolsci_dbsetstate_online"
            $db2 = "dbatoolsci_dbsetstate_offline"
            $db3 = "dbatoolsci_dbsetstate_emergency"
            $db4 = "dbatoolsci_dbsetstate_single"
            $db5 = "dbatoolsci_dbsetstate_restricted"
            $db6 = "dbatoolsci_dbsetstate_multi"
            $db7 = "dbatoolsci_dbsetstate_rw"
            $db8 = "dbatoolsci_dbsetstate_ro"
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $server.Query("CREATE DATABASE $db3")
            $server.Query("CREATE DATABASE $db4")
            $server.Query("CREATE DATABASE $db5")
            $server.Query("CREATE DATABASE $db6")
            $server.Query("CREATE DATABASE $db7")
            $server.Query("CREATE DATABASE $db8")
            $setupright = $true
            $needed_ = $server.Query("select name from sys.databases")
            $needed = $needed_ | Where-Object name -in $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
            if ($needed.Count -ne 8) {
                $setupright = $false
            }
        }
        AfterAll {
            $null = Set-DbaDbState -Sqlinstance $TestConfig.instance2 -Database $db1, $db2, $db3, $db4, $db5, $db7 -Online -ReadWrite -MultiUser -Force
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
        }
        It "Honors the Database parameter" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db2 -Emergency -Force
            $result.DatabaseName | Should -Be $db2
            $result.Status | Should -Be "EMERGENCY"
            $results = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -Emergency -Force
            $results.Count | Should -Be 2
        }
        It "Honors the ExcludeDatabase parameter" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $alldbs_ = $server.Query("select name from sys.databases")
            $alldbs = ($alldbs_ | Where-Object Name -notin @($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8)).name
            $results = Set-DbaDbState -SqlInstance $TestConfig.instance2 -ExcludeDatabase $alldbs -Online -Force
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8))
            $comparison.Count | Should -Be 0
        }

        It "Sets a database as online" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Emergency -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Online -Force
            $result.DatabaseName | Should -Be $db1
            $result.Status | Should -Be "ONLINE"
        }

        It "Sets a database as offline" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db2 -Offline -Force
            $result.DatabaseName | Should -Be $db2
            $result.Status | Should -Be "OFFLINE"
        }

        It "Sets a database as emergency" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db3 -Emergency -Force
            $result.DatabaseName | Should -Be $db3
            $result.Status | Should -Be "EMERGENCY"
        }

        It "Sets a database as single_user" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db4 -SingleUser -Force
            $result.DatabaseName | Should -Be $db4
            $result.Access | Should -Be "SINGLE_USER"
        }
        It "Sets a database as multi_user" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db6 -RestrictedUser -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db6 -MultiUser -Force
            $result.DatabaseName | Should -Be $db6
            $result.Access | Should -Be "MULTI_USER"
        }

        It "Sets a database as restricted_user" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db5 -RestrictedUser -Force
            $result.DatabaseName | Should -Be $db5
            $result.Access | Should -Be "RESTRICTED_USER"
        }
        It "Sets a database as read_write" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db7 -ReadOnly -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db7 -ReadWrite -Force
            $result.DatabaseName | Should -Be $db7
            $result.RW | Should -Be "READ_WRITE"
        }
        It "Sets a database as read_only" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db8 -ReadOnly -Force
            $result.DatabaseName | Should -Be $db8
            $result.RW | Should -Be "READ_ONLY"
        }
        It "Works when piped from Get-DbaDbState" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db7, $db8 | Set-DbaDbState -Online -MultiUser -Force
            $results.Count | Should -Be 2
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db7, $db8))
            $comparison.Count | Should -Be 0
        }
        It "Works when piped from Get-DbaDatabase" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db7, $db8 | Set-DbaDbState -Online -MultiUser -Force
            $results.Count | Should -Be 2
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db7, $db8))
            $comparison.Count | Should -Be 0
        }
        It "Has the correct properties" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Emergency -Force
            $ExpectedProps = "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "RW", "Status", "Access", "Notes", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Has the correct default properties" {
            if (-not $setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1 -Emergency -Force
            $ExpectedPropsDefault = "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "RW", "Status", "Access", "Notes"
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}