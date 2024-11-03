$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

<#
Describe "Disable-DbaFilestream" -Tag "IntegrationTests" {
    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $TestConfig.instance1
    }

    AfterAll {
        Set-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -Force
    }

    Context "When changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Set-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $NewLevel -Force -WarningAction SilentlyContinue -ErrorVariable errvar -ErrorAction SilentlyContinue
        }

        It "Should change the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
#>