$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
<#
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Parameters validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_dbsetstate_online"
            $server.Query("CREATE DATABASE $db1")
        }
        AfterAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1
        }
        It "Stops if no Database or AllDatabases" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -EnableException } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 *> $null } | Should Not Throw "You must specify"
        }
        It "Errors out when multiple 'access' params are passed with Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -SingleUser -RestrictedUser -EnableException } | Should Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -MultiUser -RestrictedUser -EnableException } | Should Throw "You can only specify one of: -SingleUser,-RestrictedUser,-MultiUser"
        }
        It "Errors out when multiple 'access' params are passed without Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -SingleUser -RestrictedUser *> $null } | Should Not Throw
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -MultiUser -RestrictedUser *> $null } | Should Not Throw
            $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -SingleUser -RestrictedUser *> $null
            $result | Should Be $null
        }
        It "Errors out when multiple 'status' params are passed with Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Offline -Online -EnableException } | Should Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Emergency -Online -EnableException } | Should Throw "You can only specify one of: -Online,-Offline,-Emergency,-Detached"
        }
        It "Errors out when multiple 'status' params are passed without Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Offline -Online *> $null } | Should Not Throw
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Emergency -Online *> $null } | Should Not Throw
            $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Offline -Online *> $null
            $result | Should Be $null
        }
        It "Errors out when multiple 'rw' params are passed with Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -ReadOnly -ReadWrite -EnableException } | Should Throw "You can only specify one of: -ReadOnly,-ReadWrite"
        }
        It "Errors out when multiple 'rw' params are passed without Silent" {
            { Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -ReadOnly -ReadWrite *> $null } | Should Not Throw
            $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -ReadOnly -ReadWrite *> $null
            $result | Should Be $null
        }
    }
    Context "Operations on databases" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_dbsetstate_online"
            $db2 = "dbatoolsci_dbsetstate_offline"
            $db3 = "dbatoolsci_dbsetstate_emergency"
            $db4 = "dbatoolsci_dbsetstate_single"
            $db5 = "dbatoolsci_dbsetstate_restricted"
            $db6 = "dbatoolsci_dbsetstate_multi"
            $db7 = "dbatoolsci_dbsetstate_rw"
            $db8 = "dbatoolsci_dbsetstate_ro"
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8 | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $server.Query("CREATE DATABASE $db3")
            $server.Query("CREATE DATABASE $db4")
            $server.Query("CREATE DATABASE $db5")
            $server.Query("CREATE DATABASE $db6")
            $server.Query("CREATE DATABASE $db7")
            $server.Query("CREATE DATABASE $db8")
            $setupright = $true
            $needed = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
            if ($needed.Count -ne 8) {
                $setupright = $false
                it "has failed setup" {
                    Set-TestInconclusive -message "Setup failed"
                }
            }
        }
        AfterAll {
            $null = Set-DbaDatabaseState -Sqlinstance $script:instance2 -Database $db2, $db3, $db4, $db5, $db7 -Online -ReadWrite -MultiUser -Force
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
        }
        if ($setupright) {
            # just to have a correct report on how much time BeforeAll takes
            It "Waits for BeforeAll to finish" {
                $true | Should Be $true
            }
            It "Honors the Database parameter" {
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db2 -Emergency -Force
                $result.DatabaseName | Should be $db2
                $result.Status | Should Be 'EMERGENCY'
                $results = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1, $db2 -Emergency -Force
                $results.Count | Should be 2
            }
            It "Honors the ExcludeDatabase parameter" {
                $alldbs = (Get-DbaDatabase -SqlInstance $script:instance2 | Where-Object Name -notin @($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8)).Name
                $results = Set-DbaDatabaseState -SqlInstance $script:instance2 -ExcludeDatabase $alldbs -Online -Force
                $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8))
                $comparison.Count | Should Be 0
            }

            It "Sets a database as online" {
                $null = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Emergency -Force
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Online -Force
                $result.DatabaseName | Should Be $db1
                $result.Status | Should Be "ONLINE"
            }

            if (-not $env:appveyor) {
                It "Sets a database as offline" {
                    $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db2 -Offline -Force
                    $result.DatabaseName | Should Be $db2
                    $result.Status | Should Be "OFFLINE"
                }
            }

            It "Sets a database as emergency" {
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db3 -Emergency -Force
                $result.DatabaseName | Should Be $db3
                $result.Status | Should Be "EMERGENCY"
            }
            if (-not $env:appveyor) {
                It "Sets a database as single_user" {
                    $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db4 -SingleUser -Force
                    $result.DatabaseName | Should Be $db4
                    $result.Access | Should Be "SINGLE_USER"
                }
                It "Sets a database as multi_user" {
                    $null = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db6 -RestrictedUser -Force
                    $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db6 -MultiUser -Force
                    $result.DatabaseName | Should Be $db6
                    $result.Access | Should Be "MULTI_USER"
                }
            }
            It "Sets a database as restricted_user" {
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db5 -RestrictedUser -Force
                $result.DatabaseName | Should Be $db5
                $result.Access | Should Be "RESTRICTED_USER"
            }
            It "Sets a database as read_write" {
                $null = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db7 -ReadOnly -Force
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db7 -ReadWrite -Force
                $result.DatabaseName | Should Be $db7
                $result.RW | Should Be "READ_WRITE"
            }
            It "Sets a database as read_only" {
                $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db8 -ReadOnly -Force
                $result.DatabaseName | Should Be $db8
                $result.RW | Should Be "READ_ONLY"
            }
            It "Works when piped from Get-DbaDatabaseState" {
                $results = Get-DbaDatabaseState -SqlInstance $script:instance2 -Database $db7, $db8 | Set-DbaDatabaseState -Online -MultiUser -Force
                $results.Count | Should Be 2
                $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db7, $db8))
                $comparison.Count | Should Be 0
            }
            It "Works when piped from Get-DbaDatabase" {
                $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db7, $db8 | Set-DbaDatabaseState -Online -MultiUser -Force
                $results.Count | Should Be 2
                $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db7, $db8))
                $comparison.Count | Should Be 0
            }
            $result = Set-DbaDatabaseState -SqlInstance $script:instance2 -Database $db1 -Emergency -Force
            It "Has the correct properties" {
                $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,DatabaseName,RW,Status,Access,Notes,Database'.Split(',')
                ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
            }

            It "Has the correct default properties" {
                $ExpectedPropsDefault = 'ComputerName,InstanceName,SqlInstance,DatabaseName,RW,Status,Access,Notes'.Split(',')
                ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedPropsDefault | Sort-Object)
            }
        }
    }
}
#>