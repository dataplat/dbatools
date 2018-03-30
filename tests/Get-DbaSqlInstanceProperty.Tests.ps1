$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 3
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaSqlInstanceProperty).Parameters.Keys
        $knownParameters = 'Computer', 'SqlInstance', 'SqlCredential', 'Credential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $results = Get-DbaSqlInstanceProperty -SqlInstance $script:instance2
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,PropertyType,SqlInstance'.Split(',')
            (($results | Get-Member -MemberType NoteProperty).name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Should return that returns a valid build" {
            $(Get-DbaSqlBuildReference -Build ($results | Where-Object {$_.name -eq 'ResourceVersionString'}).Value).MatchType | Should Be "Exact"
        }
        It "Should have DisableDefaultConstraintCheck set false" {
            ($results | Where-Object {$_.name -eq 'DisableDefaultConstraintCheck'}).Value | Should Be $False
        }
        It "Should get the correct DefaultFile location" {
            $defaultFiles = Get-DbaDefaultPath -SqlInstance $script:instance2
            ($results | Where-Object {$_.name -eq 'DefaultFile'}).Value | Should BeLike "$($defaultFiles.Data)*"
        }
    }
    Context "Command can handle multiple instances" {
        It "Should have results for 2 instances" {
            $(Get-DbaSqlInstanceProperty -SqlInstance $script:instance1, $script:instance2 | Select-Object -unique SqlInstance).count | Should Be 2
        }
    }
}