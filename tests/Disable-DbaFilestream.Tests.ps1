$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

<#
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $script:instance1
    }
    AfterAll {
        Set-DbaFilestream -SqlInstance $script:instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -force
    }

    Context "Changing FileStream Level" {
        $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
        $results = Set-DbaFilestream -SqlInstance $script:instance1 -FileStreamLevel $NewLevel -Force -WarningVariable warnvar -WarningAction silentlyContinue -ErrorVariable errvar -Erroraction silentlyContinue
        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should be $NewLevel
        }
    }
}
#>