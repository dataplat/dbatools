$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.
            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
        #>
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbRole).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase', 'ExcludeFixedRole'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
    Describe "Get-DbaDbRole Integration Tests" -Tag "IntegrationTests" {
        Context "parameters work" {
            It "returns no roles from excluded DB with -ExcludeDatabase" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -ExcludeDatabase master
                $results.where( {$_.Database -eq 'master'}).count | Should Be 0
            }
            It "returns only roles from selected DB with -Database" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -Database master
                $results.where( {$_.Database -ne 'master'}).count | Should Be 0
            }
            It "returns no fixed roles with -ExcludeFixedRole" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -ExcludeFixedRole
                $results.where( {$_.name -match 'db_datareader|db_datawriter|db_ddladmin'}).count | Should Be 0
            }
            It "returns fixed roles without -ExcludeFixedRole" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2
                $results.where( {$_.name -match 'db_datareader|db_datawriter|db_ddladmin'}).count | Should BeGreaterThan 0
            }
        }
    }
}