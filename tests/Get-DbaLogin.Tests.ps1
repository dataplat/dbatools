#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

Describe "Get-DbaLogin Integration Tests" -Tags "Integrationtests" {

    Context "Does sql instance have a SA account" {
        $results = Get-DbaLogin -SqlInstance localhost -Login sa 
        It "Should report that one account named SA exists" {
            $results.Count | Should Be 1
        }
    }

    Context "Check that SA account is enabled" {
            $results = Get-DbaLogin -SqlInstance localhost -Login sa
            It "Should say the SA account is disabled FALSE" {
                $results.IsDisabled | Should Be "False"
            }
        }
}