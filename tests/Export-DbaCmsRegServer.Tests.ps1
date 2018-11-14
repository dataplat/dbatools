$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Path', 'CredentialPersistenceType', 'EnableException'
        $SupportShouldProcess = $false
        $paramCount = $knownParameters.Count
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group
        $newServer = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group1a"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group2
        $newServer2 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaCmsRegServer -SqlInstance $script:instance1 -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3
    }
    AfterAll {
        Get-DbaCmsRegServer -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServer -Confirm:$false
        Get-DbaCmsRegServerGroup -SqlInstance $script:instance1, $script:instance2 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServerGroup -Confirm:$false
        $results, $results2, $results3 | Remove-Item -ErrorAction Ignore
    }

    It -Skip "should create an xml file" {
        $results = $newServer | Export-DbaCmsRegServer
        $results -is [System.IO.FileInfo] | Should -Be $true
        $results.Extension -eq '.xml' | Should -Be $true
    }

    It "should create a specific xml file when using Path" {
        $results2 = $newGroup2 | Export-DbaCmsRegServer -Path C:\temp\dbatoolsci_regserverexport.xml
        $results2 -is [System.IO.FileInfo] | Should -Be $true
        $results2.FullName | Should -Be 'C:\temp\dbatoolsci_regserverexport.xml'
        Get-Content -Path $results2 -Raw | Should -Match dbatoolsci-group1a
    }

    It "creates an importable xml file" {
        $results3 = $newServer3 | Export-DbaCmsRegServer -Path C:\temp\dbatoolsci_regserverexport.xml
        $results4 = Import-DbaCmsRegServer -SqlInstance $script:instance2 -Path $results3
        $results4.ServerName | Should -Be $newServer3.ServerName
        $results4.Description | Should -Be $newServer3.Description
    }
}