$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaSpDatabase).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'ConfigDatabase', 'InputObject', 'EnableException'
        $paramCount = $knownParameters.Count
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $spdb = 'SharePoint_AdminContent_802c8b65-e146-474b-becf-86af7c25ab82', 'WSS_Content', 'Profile DB', 'Sync_4ea3ab1e-ac35-4b86-8ec2-bf04f927262b DB', 'Social DB', 'SharePoint_Config'
        Get-DbaProcess -SqlInstance $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        foreach ($db in $spdb) {
            if ($db -ne 'SharePoint_Config') {
                $null = $server.Query("Create Database [$db]")
            }
        }
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path "$script:appveyorlabrepo\singlerestore\SharePoint_Config.bak"
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $spdb -Confirm:$false
    }
    Context "Command gets SharePoint Databases" {
        $results = Get-DbaSpDatabase -SqlInstance $script:instance2
        foreach ($db in $spdb) {
            It "returns a db in the SharePoint database list" {
                $db | Should -BeIn $results.Name
            }
        }
    }
}