$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Path', 'FilePath', 'CredentialPersistenceType', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group1a"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $script:instance2 -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaRegServer -SqlInstance $script:instance2 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
    }
    AfterEach {
        Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        $results, $results2, $results3 | Remove-Item -ErrorAction Ignore
    }

    It -Skip "should create an xml file" {
        $results = $newServer | Export-DbaRegServer
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.Extension -eq '.xml' | Should -Be $true
    }

    It "should create a specific xml file when using Path" {
        $results2 = $newGroup2 | Export-DbaRegServer -Path C:\temp
        $results2 -is [System.IO.FileInfo] | Should -Be $true
        $results2.FullName | Should -match 'C\:\\temp'
        Get-Content -Path $results2 -Raw | Should -Match dbatoolsci-group1a
    }

    It "creates an importable xml file" {
        $results3 = $newServer3 | Export-DbaRegServer -Path C:\temp
        Get-DbaRegServer -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        $results4 = Import-DbaRegServer -SqlInstance $script:instance2 -Path $results3
        $newServer3.ServerName | Should -BeIn $results4.ServerName
        $newServer3.Description | Should -BeIn $results4.Description
    }
}