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
        It "Should have a parameter SQLPass" {
            $Params['SQLPass'].Count | Should Be 1
        }
        It "Should have a parameter Path" {
            $Params['Path'].Count | Should Be 1
        }
        It "Should have a parameter EnableException" {
            $Params['EnableException'].Count | Should Be 1
        }
        It "Should have a silent alias for parameter EnableException" {
            $Params['EnableException'].Aliases | Should Be 'Silent'
        }
    }
}