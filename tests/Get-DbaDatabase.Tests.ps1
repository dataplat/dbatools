Describe "Get-DbaDatabase Integration Tests" -Tags "Integrationtests" {

    Context "Count system databases on localhost" {
        $results = Get-DbaDatabase -SqlInstance localhost -NoUserDb 
        It "Should report the right number of databases" {
            $results.Count | Should Be 4
        }
    }

    Context "Check that master database is in Simple recovery mode" {
            $results = Get-DbaDatabase -SqlInstance localhost -Database master
            It "Should say the recovery mode of master is Simple" {
                $results.RecoveryModel | Should Be "Simple"
            }
        }
}
