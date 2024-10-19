param($ModuleName = 'dbatools')

Describe "Remove-DbaRegServer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaRegServer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have ServerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerName
        }
        It "Should have Group as a parameter" {
            $CommandUnderTest | Should -HaveParameter Group
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'constants.ps1')

            $srvName = "dbatoolsci-server1"
            $regSrvName = "dbatoolsci-server12"
            $regSrvDesc = "dbatoolsci-server123"
            $newServer = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

            $srvName2 = "dbatoolsci-server2"
            $regSrvName2 = "dbatoolsci-server21"
            $regSrvDesc2 = "dbatoolsci-server321"
            $newServer2 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2
        }
        AfterAll {
            Get-DbaRegServer -SqlInstance $global:instance1 -Name $regSrvName, $regSrvName2, $regSrvName3 | Remove-DbaRegServer
        }

        It "supports dropping via the pipeline" {
            $results = $newServer | Remove-DbaRegServer
            $results.Name | Should -Be $regSrvName
            $results.Status | Should -Be 'Dropped'
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServer -SqlInstance $global:instance1 -Name $regSrvName2
            $results.Name | Should -Be $regSrvName2
            $results.Status | Should -Be 'Dropped'
        }
    }
}
