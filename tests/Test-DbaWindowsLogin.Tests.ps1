<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'ExcludeLogin', 'FilterBy', 'IgnoreDomains', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
<#
Did not include these tests yet as I was unsure if AppVeyor was capable of testing domain logins. Included these for future use.
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Test-DbaWindowsLogin -SqlInstance $script:instance2
        It "Should return correct properties" {
            $ExpectedProps = 'AccountNotDelegated,AllowReversiblePasswordEncryption,CannotChangePassword,DisabledInSQLServer,Domain,Enabled,Found,LockedOut,Login,PasswordExpired,PasswordNeverExpires,PasswordNotRequired,Server,SmartcardLogonRequired,TrustedForDelegation,Type,UserAccountControl'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        $Type = 'User'
        It "Should return true if Account type is: $Type" {
            ($results | Where-Object Type -match $Type) | Should Be $true
        }
        It "Should return true if Account is Found" {
            ($results | Where-Object Found).Found | Should Be $true
        }
    }
}#>