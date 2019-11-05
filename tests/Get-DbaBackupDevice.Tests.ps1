$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC sp_addumpdevice 'tape', 'dbatoolsci_tape', '\\.\tape0';"
        $server.Query($sql)
    }
    Afterall {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $sql = "EXEC sp_dropdevice 'dbatoolsci_tape';"
        $server.Query($sql)
    }

    Context "Gets the backup devices" {
        $results = Get-DbaBackupDevice -SqlInstance $script:instance2
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Should have the name dbatoolsci_tape" {
            $results.name | Should Be "dbatoolsci_tape"
        }
        It "Should have a BackupDeviceType of Tape" {
            $results.BackupDeviceType | Should Be "Tape"
        }
        It "Should have a PhysicalLocation of \\.\Tape0" {
            $results.PhysicalLocation | Should Be "\\.\Tape0"
        }
    }
}