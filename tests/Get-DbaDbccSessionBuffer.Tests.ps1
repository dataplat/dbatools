$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Operation', 'SessionId', 'RequestId', 'All', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $queryResult = $db.Query('SELECT top 10 object_id, @@Spid as MySpid FROM sys.objects')
    }
    AfterAll {
    }

    Context "Validate standard output for all databases " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'SessionId', 'EventType', 'Parameters', 'EventInfo'
        $result = Get-DbaDbccSessionBuffer -SqlInstance $script:instance1 -Operation InputBuffer -All

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }

        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'SessionId', 'Buffer', 'HexBuffer'
        $result = Get-DbaDbccSessionBuffer -SqlInstance $script:instance1 -Operation OutputBuffer -All

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }

        }
    }

    Context "Validate returns results for SessionId " {
        $spid = $queryResult[0].MySpid
        $result = Get-DbaDbccSessionBuffer -SqlInstance $script:instance1 -Operation InputBuffer -SessionId $spid

        It "returns results for InputBuffer" {
            $result.SessionId -eq $spid | Should Be $true
        }

        $result = Get-DbaDbccSessionBuffer -SqlInstance $script:instance1 -Operation OutputBuffer -SessionId $spid

        It "returns results for OutputBuffer" {
            $result.SessionId -eq $spid | Should Be $true
        }
    }

}