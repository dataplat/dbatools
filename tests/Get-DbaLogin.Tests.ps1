$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'IncludeFilter', 'ExcludeLogin', 'ExcludeFilter', 'ExcludeSystemLogin', 'Type', 'HasAccess', 'Locked', 'Disabled', 'Detailed', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Does sql instance have a SA account" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should report that one account named SA exists" {
            $results.Count | Should Be 1
        }
    }

    Context "Check that SA account is enabled" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
        It "Should say the SA account is disabled FALSE" {
            $results.IsDisabled | Should Be "False"
        }
    }

    Context "Check that SA account is SQL Login" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa -Type SQL -Detailed
        It "Should report that one SQL Login named SA exists" {
            $results.Count | Should Be 1
        }
        It "Should get LoginProperties via Detailed switch" {
            $results.BadPasswordCount | Should Not Be $null
            $results.PasswordHash | Should Not Be $null
        }
    }
}