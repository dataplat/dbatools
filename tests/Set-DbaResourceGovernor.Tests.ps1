$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'Enabled', 'Disabled', 'ClassifierFunction', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $classifierFunction = "dbo.fnRGClassifier"
        $createUDFQuery = "CREATE FUNCTION $classifierFunction()
        RETURNS SYSNAME
        WITH SCHEMABINDING
        AS
        BEGIN
        RETURN DB_NAME();
        END;"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $createUDFQuery -Database "master"
        Set-DbaResourceGovernor -SqlInstance $script:instance2 -Disabled -Confirm:$false
    }
    Context "Validate command functionality" {
        It "enables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $script:instance2 -Enabled -Confirm:$false
            $results.Enabled | Should -Be $true
        }

        It "disables resource governor" {
            $results = Set-DbaResourceGovernor -SqlInstance $script:instance2 -Disabled -Confirm:$false
            $results.Enabled | Should -Be $false
        }

        It "modifies resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $script:instance2 -ClassifierFunction $classifierFunction -Confirm:$false
            $results.ClassifierFunction | Should -Be $classifierFunction
        }

        It "removes resource governor classifier function" {
            $results = Set-DbaResourceGovernor -SqlInstance $script:instance2 -ClassifierFunction 'NULL' -Confirm:$false
            $results.ClassifierFunction | Should -Be ''
        }
    }
    AfterAll {
        $dropUDFQuery = "DROP FUNCTION $classifierFunction;"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $dropUDFQuery -Database "master"
    }
}
