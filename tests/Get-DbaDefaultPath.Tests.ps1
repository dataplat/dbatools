$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        $results = Get-DbaDefaultPath -SqlInstance $script:instance1
        It "Data returns a value that contains :\" {
            $results.Data -match "\:\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log -match "\:\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup -match "\:\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog -match "\:\\"
        }
    }
}