#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbState",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Parameters validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:db1 = "dbatoolsci_dbsetstate_online"
            $global:server.Query("CREATE DATABASE $global:db1")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $global:db1 -ErrorAction SilentlyContinue
        }

        It "Stops if no Database or AllDatabases" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -EnableException } | Should -Throw "You must specify"
        }

        It "Is nice by default" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 *> $null } | Should -Not -Throw "You must specify"
        }

        It "Errors out when multiple 'access' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -SingleUser -RestrictedUser -EnableException } | Should -Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -MultiUser -RestrictedUser -EnableException } | Should -Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
        }

        It "Errors out when multiple 'access' params are passed without EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -SingleUser -RestrictedUser *> $null } | Should -Not -Throw
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -MultiUser -RestrictedUser *> $null } | Should -Not -Throw
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -SingleUser -RestrictedUser *> $null
            $result | Should -Be $null
        }

        It "Errors out when multiple 'status' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -Offline -Online -EnableException } | Should -Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -Emergency -Online -EnableException } | Should -Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
        }

        It "Errors out when multiple 'status' params are passed without Silent" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -Offline -Online *> $null } | Should -Not -Throw
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -Emergency -Online *> $null } | Should -Not -Throw
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -Offline -Online *> $null
            $result | Should -Be $null
        }

        It "Errors out when multiple 'rw' params are passed with EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -ReadOnly -ReadWrite -EnableException } | Should -Throw "You can only specify one of: -ReadOnly,-ReadWrite"
        }

        It "Errors out when multiple 'rw' params are passed without EnableException" {
            { Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -ReadOnly -ReadWrite *> $null } | Should -Not -Throw
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1 -ReadOnly -ReadWrite *> $null
            $result | Should -Be $null
        }
    }

    Context "Operations on databases" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $global:opsServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:opsDb1 = "dbatoolsci_dbsetstate_online"
            $global:opsDb2 = "dbatoolsci_dbsetstate_offline"
            $global:opsDb3 = "dbatoolsci_dbsetstate_emergency"
            $global:opsDb4 = "dbatoolsci_dbsetstate_single"
            $global:opsDb5 = "dbatoolsci_dbsetstate_restricted"
            $global:opsDb6 = "dbatoolsci_dbsetstate_multi"
            $global:opsDb7 = "dbatoolsci_dbsetstate_rw"
            $global:opsDb8 = "dbatoolsci_dbsetstate_ro"

            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb6, $global:opsDb7, $global:opsDb8 | Remove-DbaDatabase -Confirm:$false

            $global:opsServer.Query("CREATE DATABASE $global:opsDb1")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb2")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb3")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb4")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb5")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb6")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb7")
            $global:opsServer.Query("CREATE DATABASE $global:opsDb8")

            $global:setupright = $true
            $needed = $global:opsServer.Query("select name from sys.databases")
            $neededDbs = $needed | Where-Object name -in $global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb6, $global:opsDb7, $global:opsDb8
            if ($neededDbs.Count -ne 8) {
                $global:setupright = $false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Set-DbaDbState -Sqlinstance $TestConfig.instance2 -Database $global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb7 -Online -ReadWrite -MultiUser -Force -ErrorAction SilentlyContinue
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb6, $global:opsDb7, $global:opsDb8 -ErrorAction SilentlyContinue
        }

        It "Waits for BeforeAll to finish" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $true | Should -Be $true
        }

        It "Honors the Database parameter" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb2 -Emergency -Force
            $result.DatabaseName | Should -Be $global:opsDb2
            $result.Status | Should -Be "EMERGENCY"
            $results = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb1, $global:opsDb2 -Emergency -Force
            $results.Count | Should -Be 2
        }

        It "Honors the ExcludeDatabase parameter" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $allDbsQuery = $global:opsServer.Query("select name from sys.databases")
            $allDbs = ($allDbsQuery | Where-Object Name -notin @($global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb6, $global:opsDb7, $global:opsDb8)).name
            $results = Set-DbaDbState -SqlInstance $TestConfig.instance2 -ExcludeDatabase $allDbs -Online -Force
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($global:opsDb1, $global:opsDb2, $global:opsDb3, $global:opsDb4, $global:opsDb5, $global:opsDb6, $global:opsDb7, $global:opsDb8))
            $comparison.Count | Should -Be 0
        }

        It "Sets a database as online" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb1 -Emergency -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb1 -Online -Force
            $result.DatabaseName | Should -Be $global:opsDb1
            $result.Status | Should -Be "ONLINE"
        }

        It "Sets a database as offline" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb2 -Offline -Force
            $result.DatabaseName | Should -Be $global:opsDb2
            $result.Status | Should -Be "OFFLINE"
        }

        It "Sets a database as emergency" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb3 -Emergency -Force
            $result.DatabaseName | Should -Be $global:opsDb3
            $result.Status | Should -Be "EMERGENCY"
        }

        It "Sets a database as single_user" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb4 -SingleUser -Force
            $result.DatabaseName | Should -Be $global:opsDb4
            $result.Access | Should -Be "SINGLE_USER"
        }

        It "Sets a database as multi_user" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb6 -RestrictedUser -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb6 -MultiUser -Force
            $result.DatabaseName | Should -Be $global:opsDb6
            $result.Access | Should -Be "MULTI_USER"
        }

        It "Sets a database as restricted_user" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb5 -RestrictedUser -Force
            $result.DatabaseName | Should -Be $global:opsDb5
            $result.Access | Should -Be "RESTRICTED_USER"
        }

        It "Sets a database as read_write" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $null = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb7 -ReadOnly -Force
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb7 -ReadWrite -Force
            $result.DatabaseName | Should -Be $global:opsDb7
            $result.RW | Should -Be "READ_WRITE"
        }

        It "Sets a database as read_only" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb8 -ReadOnly -Force
            $result.DatabaseName | Should -Be $global:opsDb8
            $result.RW | Should -Be "READ_ONLY"
        }

        It "Works when piped from Get-DbaDbState" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb7, $global:opsDb8 | Set-DbaDbState -Online -MultiUser -Force
            $results.Count | Should -Be 2
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($global:opsDb7, $global:opsDb8))
            $comparison.Count | Should -Be 0
        }

        It "Works when piped from Get-DbaDatabase" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:opsDb7, $global:opsDb8 | Set-DbaDbState -Online -MultiUser -Force
            $results.Count | Should -Be 2
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($global:opsDb7, $global:opsDb8))
            $comparison.Count | Should -Be 0
        }

        It "Has the correct properties" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb1 -Emergency -Force
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Notes",
                "Database"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Has the correct default properties" {
            if (-not $global:setupright) {
                Set-ItResult -Inconclusive -Because "Setup failed"
            }
            $result = Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:opsDb1 -Emergency -Force
            $expectedPropsDefault = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Notes"
            )
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedPropsDefault | Sort-Object)
        }
    }
}