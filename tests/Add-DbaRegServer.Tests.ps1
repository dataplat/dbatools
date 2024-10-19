param($ModuleName = 'dbatools')

Describe "Add-DbaRegServer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaRegServer
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have ServerName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ServerName
        }
        It "Should have Name as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Description as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Description
        }
        It "Should have Group as a non-mandatory parameter of type System.Object" {
            $CommandUnderTest | Should -HaveParameter Group
        }
        It "Should have ActiveDirectoryTenant as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryTenant
        }
        It "Should have ActiveDirectoryUserId as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryUserId
        }
        It "Should have ConnectionString as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ConnectionString
        }
        It "Should have OtherParams as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter OtherParams
        }
        It "Should have InputObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have ServerObject as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.Server[]" {
            $CommandUnderTest | Should -HaveParameter ServerObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
            $groupobject = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $global:instance1, $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $global:instance1, $global:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "adds a registered server" {
            $results1 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $srvName
            $results1.Name | Should -Be $srvName
            $results1.ServerName | Should -Be $srvName
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server with extended properties" {
            $results2 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $RegsrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
