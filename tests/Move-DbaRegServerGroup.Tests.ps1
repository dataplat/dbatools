param($ModuleName = 'dbatools')

Describe "Move-DbaRegServerGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Move-DbaRegServerGroup
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Group",
                "NewGroup",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $srvName = "dbatoolsci-server1"
            $group = "dbatoolsci-group1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"

            $newGroup = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group
            $newServer = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group2

            $group3 = "dbatoolsci-group1b"
            $newGroup3 = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group3
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $global:instance1 -Name $regSrvName | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group $group, $group2, $group3 | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }

        It "moves a manually specified group" {
            $results = Move-DbaRegServerGroup -SqlInstance $global:instance1 -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be 'DatabaseEngineServerGroup'
        }
    }
}
