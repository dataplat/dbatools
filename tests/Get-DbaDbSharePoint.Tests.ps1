$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'ConfigDatabase', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $spdb = 'SharePoint_Admin_7c0c491d0e6f43858f75afa5399d49ab', 'WSS_Logging', 'SecureStoreService_20e1764876504335a6d8dd0b1937f4bf', 'DefaultWebApplicationDB', 'SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0', 'DefaultPowerPivotServiceApplicationDB-5b638361-c6fc-4ad9-b8ba-d05e63e48ac6', 'SharePoint_Config_4c524cb90be44c6f906290fe3e34f2e0'
        Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        foreach ($db in $spdb) {
            try {
                $null = $server.Query("Create Database [$db]")
            } catch { continue }
        }
        # This takes a long time but I cannot figure out why every backup of this db is malformed
        $bacpac = "$script:appveyorlabrepo\bacpac\sharepoint_config.bacpac"
        . "$PSScriptRoot\..\bin\smo\sqlpackage.exe" /Action:Import /tsn:$script:instance2 /tdn:Sharepoint_Config /sf:$bacpac /p:Storage=File
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $spdb -Confirm:$false
    }
    Context "Command gets SharePoint Databases" {
        $results = Get-DbaDbSharePoint -SqlInstance $script:instance2
        foreach ($db in $spdb) {
            It "returns $db from in the SharePoint database list" {
                $db | Should -BeIn $results.Name
            }
        }
    }
}