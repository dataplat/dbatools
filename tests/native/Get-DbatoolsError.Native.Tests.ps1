#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbatoolsError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Error query binding and selection" {
    BeforeEach {
        $script:errorQuerySaved = @($global:Error)
        $script:errorQueryFixtures = @()
        foreach ($errorQueryId in @("dbatools-first", "unrelated", "DBATOOLS-middle", "dbatools-last")) {
            $errorQueryException = New-Object System.InvalidOperationException "fixture-$errorQueryId"
            $errorQueryTarget = [pscustomobject]@{ Marker = $errorQueryId }
            $errorQueryRecord = New-Object System.Management.Automation.ErrorRecord -ArgumentList $errorQueryException, $errorQueryId, ([System.Management.Automation.ErrorCategory]::InvalidOperation), $errorQueryTarget
            $script:errorQueryFixtures += $errorQueryRecord
        }
        $global:Error.Clear()
        foreach ($errorQueryRecord in $script:errorQueryFixtures) { $null = $global:Error.Add($errorQueryRecord) }
    }
    AfterEach {
        $global:Error.Clear()
        foreach ($errorQuerySavedRecord in $script:errorQuerySaved) { $null = $global:Error.Add($errorQuerySavedRecord) }
    }

    It "converts explicit null integer arguments to zero" {
        @(Get-DbatoolsError -First $null).Count | Should -Be 0
        @(Get-DbatoolsError -Last $null).Count | Should -Be 0
        @(Get-DbatoolsError -Skip $null).Count | Should -Be 0
    }

    It "converts numeric strings and preserves projected object identity" {
        $errorQueryOutput = @(Get-DbatoolsError -First "2" -Skip "1")
        $errorQueryOutput.Count | Should -Be 2
        $errorQueryOutput[0].FullyQualifiedErrorId | Should -BeExactly "DBATOOLS-middle"
        $errorQueryOutput[1].FullyQualifiedErrorId | Should -BeExactly "dbatools-last"
        [object]::ReferenceEquals($errorQueryOutput[0].Exception, $script:errorQueryFixtures[2].Exception) | Should -BeTrue
        [object]::ReferenceEquals($errorQueryOutput[0].TargetObject, $script:errorQueryFixtures[2].TargetObject) | Should -BeTrue
        $errorQueryOutput[0].PSObject.TypeNames[0] | Should -BeExactly "Selected.System.Management.Automation.ErrorRecord"
    }

    It "lets All replace a negative First before selection validation" {
        $errorQueryOutput = @(Get-DbatoolsError -All -First -1)
        $errorQueryOutput.Count | Should -Be 3
        ($errorQueryOutput.FullyQualifiedErrorId -join ",") | Should -BeExactly "dbatools-first,DBATOOLS-middle,dbatools-last"
    }
}
