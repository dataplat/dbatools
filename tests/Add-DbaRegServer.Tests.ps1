$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ServerName -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Group -Type Object -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryTenant -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ActiveDirectoryUserId -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ConnectionString -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OtherParams -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type ServerGroup[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ServerObject -Type Server[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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

    Context "Adds a registered server" {
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
