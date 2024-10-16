param($ModuleName = 'dbatools')

Describe "Add-DbaRegServer" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaRegServer
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have ServerName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ServerName -Type String -Not -Mandatory
        }
        It "Should have Name as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
        }
        It "Should have Description as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
        }
        It "Should have Group as a non-mandatory parameter of type Object" {
            $CommandUnderTest | Should -HaveParameter Group -Type Object -Not -Mandatory
        }
        It "Should have ActiveDirectoryTenant as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryTenant -Type String -Not -Mandatory
        }
        It "Should have ActiveDirectoryUserId as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryUserId -Type String -Not -Mandatory
        }
        It "Should have ConnectionString as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ConnectionString -Type String -Not -Mandatory
        }
        It "Should have OtherParams as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter OtherParams -Type String -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type ServerGroup[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ServerGroup[] -Not -Mandatory
        }
        It "Should have ServerObject as a non-mandatory parameter of type Server[]" {
            $CommandUnderTest | Should -HaveParameter ServerObject -Type Server[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
            $groupobject = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
            Get-DbaRegServerGroup -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "adds a registered server" {
            $results1 = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $srvName
            $results1.Name | Should -Be $srvName
            $results1.ServerName | Should -Be $srvName
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server with extended properties" {
            $results2 = Add-DbaRegServer -SqlInstance $script:instance1 -ServerName $RegsrvName -Name $srvName -Group $groupobject -Description $regSrvDesc
            $results2.ServerName | Should -Be $regSrvName
            $results2.Description | Should -Be $regSrvDesc
            $results2.Name | Should -Be $srvName
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
