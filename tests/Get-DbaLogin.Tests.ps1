$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag UnitTests, Get-DbaLogin {
    Context "$Command Name Input" {
        $Params = (Get-Command Get-DbaLogin).Parameters
        It "Should have a mandatory parameter SQLInstance" {
            $Params['SQLInstance'].Attributes.Mandatory | Should be $true
        }
        It "Should have Alias of ServerInstance and SqlServer for Parameter SQLInstance" {
            $params['SQLInstance'].Aliases | Should Be @('ServerInstance', 'SqlServer')
        }
        It "Should have a parameter SqlCredential" {
            $Params['SqlCredential'].Count | Should Be 1
        }
        It "Should have a parameter Login" {
            $Params['Login'].Count | Should Be 1
        }
        It "Should have a parameter IncludeFilter" {
            $Params['IncludeFilter'].Count | Should Be 1
        }
        It "Should have a parameter ExcludeLogin" {
            $Params['ExcludeLogin'].Count | Should Be 1
        }
        It "Should have a parameter ExcludeFilter" {
            $Params['ExcludeFilter'].Count | Should Be 1
        }
        It "Should have a parameter NoSystem" {
            $Params['NoSystem'].Count | Should Be 1
        }
        It "Should have a parameter SQLLogins" {
            $Params['SQLLogins'].Count | Should Be 1
        }
        It "Should have a parameter WindowsLogins" {
            $Params['WindowsLogins'].Count | Should Be 1
        }
        It "Should have a parameter HasAccess" {
            $Params['HasAccess'].Count | Should Be 1
        }
        It "Should have a parameter Locked" {
            $Params['Locked'].Count | Should Be 1
        }
        It "Should have a parameter Disabled" {
            $Params['Disabled'].Count | Should Be 1
        }
        It "Should have a parameter EnableException" {
            $Params['EnableException'].Count | Should Be 1
        }
        It "Should have a silent alias for parameter EnableException" {
            $Params['EnableException'].Aliases | Should Be 'Silent'
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Does sql instance have a SA account" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should report that one account named SA exists" {
            $results.Count | Should Be 1
        }
    }

    Context "Check that SA account is enabled" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should say the SA account is disabled FALSE" {
            $results.IsDisabled | Should Be "False"
        }
    }
}