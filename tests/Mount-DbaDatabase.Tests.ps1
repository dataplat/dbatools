$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'FileStructure', 'DatabaseOwner', 'AttachOption', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Setup removes, restores and backups on the local drive for Mount-DbaDatabase" {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Path "$($TestConfig.appveyorlabrepo)\detachattach\detachattach.bak" -WithReplace
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database detachattach | Backup-DbaDatabase -BackupFileName C:\Temp\detachattach.bak
        $null = Detach-DbaDatabase -SqlInstance $TestConfig.instance1 -Database detachattach -Force
    }

    Context "Attaches a single database and tests to ensure the alias still exists" {
        $results = Mount-DbaDatabase -SqlInstance $TestConfig.instance1 -Database detachattach

        It "Should return success" {
            $results.AttachResult | Should Be "Success"
        }

        It "Should return that the database is only Database" {
            $results.Database | Should Be "detachattach"
        }

        It "Should return that the AttachOption default is None" {
            $results.AttachOption | Should Be "None"
        }
    }

    $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database detachattach | Remove-DbaDatabase -Confirm:$false
    Remove-Item -Path C:\Temp\detachattach.bak
}
