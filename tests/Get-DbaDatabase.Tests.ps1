$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Count system databases on localhost" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -NoUserDb 
        It "Should report the right number of databases" {
            $results.Count | Should Be 4
        }
    }
 
    Context "Check that master database is in Simple recovery mode" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master
        It "Should say the recovery mode of master is Simple" {
            $results.RecoveryModel | Should Be "Simple"
        }
    }
	
    Context "Check that master database is accessible" {
        $results = Get-DbaDatabase -SqlInstance $script:instance1 -Database master
        It "Should return true that master is accessible" {
            $results.IsAccessible | Should Be $true
        }
    }
}



Describe "$commandname Unit Tests" -Tags "UnitTests", Get-DBADatabase {
    BeforeAll {
        ## Ensure it is the module that is being coded that is in the session
        # Remove-Module dbatools -Force -ErrorAction SilentlyContinue
        # $Base = Split-Path -parent $PSCommandPath
        # Import-Module $Base\..\dbatools.psd1
    }
    Context "Input validation" {
        BeforeAll {
            Mock Stop-Function {} -ModuleName dbatools
            Mock Test-FunctionInterrupt {} -ModuleName dbatools
        }
        It "Should Call Stop-Function if NoUserDbs and NoSystemDbs are specified" {
            Get-DbaDatabase -SqlInstance Dummy -NoSystemDb -NoUserDb | Should Be 
        }
        It "Validates that Stop Function Mock has been called" {
            ## Nope I have no idea why it's two either - RMS
            $assertMockParams = @{
                'CommandName' = 'Stop-Function'
                'Times'       = 2 
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams 
        }
        It "Validates that Test-FunctionInterrupt Mock has been called" {
            $assertMockParams = @{
                'CommandName' = 'Test-FunctionInterrupt'
                'Times'       = 1 
                'Exactly'     = $true
                'Module'      = 'dbatools'
            }
            Assert-MockCalled @assertMockParams 
        }
    }
}
