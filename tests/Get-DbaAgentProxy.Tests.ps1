$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Proxy', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        $tUserName = "dbatoolsci_proxytest"
        New-LocalUser -Name $tUserName -Password $tPassword -Disabled:$false
        New-DbaCredential -SqlInstance $script:instance2 -Name "$tUserName" -Identity "$env:COMPUTERNAME\$tUserName" -Password $tPassword
        New-DbaAgentProxy -SqlInstance $script:instance2 -Name STIG -ProxyCredential "$tUserName"
    }
    Afterall {
        $tUserName = "dbatoolsci_proxytest"
        Remove-LocalUser -Name $tUserName
        $credential = Get-DbaCredential -SqlInstance $script:instance2 -Name $tUserName
        $credential.DROP()
        $proxy = Get-DbaAgentProxy -SqlInstance $script:instance2 -Proxy "STIG"
        $proxy.DROP()
    }

    Context "Gets the list of Proxy" {
        $results = Get-DbaAgentProxy -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should have the name STIG" {
            $results.name | Should Be "STIG"
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
    }
    Context "Gets a single Proxy" {
        $results = Get-DbaAgentProxy -SqlInstance $script:instance2 -Proxy "STIG"
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should have the name STIG" {
            $results.name | Should Be "STIG"
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
    }
}