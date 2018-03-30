$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 4
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Enable-DbaAgHadr).Parameters.Keys
        $knownParameters = 'SqlInstance', 'Credential', 'Force', 'EnableException'
        it "Should contian our specifc parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $current = Get-DbaAgHadr -SqlInstance $script:instance3 # for appveyor $script:instance2
        if ($current.IsHadrEnabled) {
            Disable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -WarningAction SilentlyContinue -Force
        }
    }
    AfterAll {
        if (-not $current.IsHadrEnabled) {
            Disable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -WarningAction SilentlyContinue -Force
        }
    }
    
    $results = Enable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -Force
    
    It "enables hadr" {
        $results.IsHadrEnabled | Should -Be $true
    }
}