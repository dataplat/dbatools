$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Proxy', 'ExcludeProxy', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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
        New-DbaAgentProxy -SqlInstance $script:instance2 -Name STIGX -ProxyCredential "$tUserName"
    }
    Afterall {
        $tUserName = "dbatoolsci_proxytest"
        Remove-LocalUser -Name $tUserName
        $credential = Get-DbaCredential -SqlInstance $script:instance2 -Name $tUserName
        $credential.DROP()
        $proxy = Get-DbaAgentProxy -SqlInstance $script:instance2 -Proxy "STIG", "STIGX"
        $proxy.DROP()
    }

    Context "Gets the list of Proxy" {
        $results = Get-DbaAgentProxy -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should have the name STIG" {
            $results.name | Should Contain "STIG"
        }
        It "Should be enabled" {
            $results.isenabled | Should Contain $true
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
    Context "Gets the list of Proxy without excluded" {
        $results = Get-DbaAgentProxy -SqlInstance $script:instance2 -ExcludeProxy "STIG"
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should not have the name STIG" {
            $results.name | Should Not Be "STIG"
        }
        It "Should be enabled" {
            $results.isenabled | Should Be $true
        }
    }
}