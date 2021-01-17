$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Category', 'InputObject', 'ExcludeSystemObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaPbmCategory -SqlInstance $script:instance2
        it "Gets Results" {
            $results | Should Not Be $null
        }
    }
    Context "Command actually works using -Category" {
        $results = Get-DbaPbmCategory -SqlInstance $script:instance2 -Category 'Availability database errors'
        it "Gets Results" {
            $results | Should Not Be $null
        }
    }
    Context "Command actually works using -ExcludeSystemObject" {
        $results = Get-DbaPbmCategory -SqlInstance $script:instance2 -ExcludeSystemObject
        it "Gets Results" {
            $results | Should Not Be $null
        }
    }
}