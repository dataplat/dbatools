$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'ExcludeCredential', 'Identity', 'ExcludeIdentity', 'InputObject', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    BeforeEach {

        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $credentialName = "dbatoolsci_test_$(get-random)"
        $credentialName2 = "dbatoolsci_test_$(get-random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
        $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"

    }

    Context "commands work as expected" {

        It "removes a SQL credential" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName ) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Credential $credentialName -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName ) | Should -BeNullOrEmpty
        }

        It "supports piping SQL credential" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName ) | Should -Not -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $server -Credential $credentialName | Remove-DbaCredential -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName ) | Should -BeNullOrEmpty
        }

        It "removes all SQL credentials but excluded" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName2 ) | Should -Not -BeNullOrEmpty
            (Get-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2 ) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2 -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2 ) | Should -BeNullOrEmpty
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName2 ) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL credentials" {
            (Get-DbaCredential -SqlInstance $server ) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Confirm:$false
            (Get-DbaCredential -SqlInstance $server ) | Should -BeNullOrEmpty
        }
    }
}