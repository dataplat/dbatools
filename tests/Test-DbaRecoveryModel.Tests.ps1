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
        $paramCount = 7
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaRecoveryModel).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential','RecoveryModel', 'Database', 'ExcludeDatabase', 'EnableException', 'Detailed'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
Describe "$CommandName Intigration Tests" -Tag  "IntegrationTests" {
    BeforeAll {
        $fullRecovery = "dbatoolsci_RecoveryModelFull"
        $bulkLoggedRecovery = "dbatoolsci_RecoveryModelBulk"
        $simpleRecovery = "dbatoolsci_RecoveryModelSimple"
        $psudoSimpleRecovery = "dbatoolsci_RecoveryModelPsudoSimple"
        $server = Connect-DbaInstance -SqlInstance $script:instance2

        Stop-DbaProcess -SqlInstance $script:instance2 -Database model
        $server.Query("CREATE DATABASE $fullRecovery")
        Stop-DbaProcess -SqlInstance $script:instance2 -Database model
        $server.Query("CREATE DATABASE $bulkLoggedRecovery")
        Stop-DbaProcess -SqlInstance $script:instance2 -Database model
        $server.Query("CREATE DATABASE $simpleRecovery")
        Stop-DbaProcess -SqlInstance $script:instance2 -Database model
        $server.Query("CREATE DATABASE $psudoSimpleRecovery")

        Set-DbaDbRecoveryModel -sqlInstance $script:instance2 -RecoveryModel BulkLogged -Database $bulkLoggedRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Simple -Database $simpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Simple -Database $psudoSimpleRecovery -Confirm:$false
        Set-DbaDbRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Full -Database $psudoSimpleRecovery -Confirm:$false

    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance2 -Database $fullRecovery, $bulkLoggedRecovery, $simpleRecovery, $psudoSimpleRecovery
    }

    Context "Default Execution" {
        $results = Test-DbaRecoveryModel -SqlInstance $script:instance2 -Database $fullRecovery,$psudoSimpleRecovery,'Model'

       It "Should return $fullRecovery, $psudoSimpleRecovery, and Model" {
            $results.Database | should -BeIn ($fullRecovery,$psudoSimpleRecovery,'Model')
       }

    }

    Context "Full Recovery" {
        $results = Test-DbaRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Full -Database $fullRecovery,$psudoSimpleRecovery -ExcludeDatabase 'Model'

        It "Should return $fullRecovery and $psudoSimpleRecovery" {
            $results.Database | should -BeIn ($fullRecovery,$psudoSimpleRecovery)
       }
    }

    Context "Bulk Logged Recovery" {
        $results =  Test-DbaRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Bulk_Logged -Database $bulkLoggedRecovery

        It "Should return $bulkLoggedRecovery" {
            $results.Database | should -Be "$bulkLoggedRecovery"
        }

    }

    Context "Simple Recovery" {
        $results =  Test-DbaRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Simple -Database $simpleRecovery

        It "Should return $simpleRecovery" {
            $results.Database | should -Be "$simpleRecovery"
        }

    }

    Context "Psudo Simple Recovery" {
        $results =  Test-DbaRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Full | Where {$_.database -eq "$psudoSimpleRecovery"}

        It "Should return $psudoSimpleRecovery" {
            $results.Database | should -Be "$psudoSimpleRecovery"
        }

    }

    Context "Error Check" {

        It "Should Throw Error for Incorrect Recovery Model" {
            {Test-DbaRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Awesome -EnableException -Database 'dontexist' } | should -Throw
        }

        Mock Connect-SqlInstance { Throw } -ModuleName dbatools
        It "Should Thow Error for a DB Connection Error" {
            {Test-DbaRecoveryModel -SqlInstance $script:instance2 -EnableException | Should -Throw }
        }

        Mock Select-DefaultView { Throw } -ModuleName dbatools
        It "Should Thow Error for Output Error " {
            {Test-DbaRecoveryModel -SqlInstance $script:instance2 -EnableException | Should -Throw }
        }

    }


}