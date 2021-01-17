$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {

        [array]$knownParameters = 'Type', 'Action', 'PublishXml', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $publishprofile = New-DbaDacProfile -SqlInstance $script:instance1 -Database whatever -Path C:\temp
    }
    AfterAll {
        Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
    }
    It "Returns dacpac export options" {
        New-DbaDacOption -Action Export | Should -Not -BeNullOrEmpty
    }
    It "Returns bacpac export options" {
        New-DbaDacOption -Action Export -Type Bacpac | Should -Not -BeNullOrEmpty
    }
    It "Returns dacpac publish options" {
        New-DbaDacOption -Action Publish  | Should -Not -BeNullOrEmpty
    }
    It "Returns dacpac publish options from an xml" {
        New-DbaDacOption -Action Publish -PublishXml $publishprofile.FileName -EnableException | Should -Not -BeNullOrEmpty
    }
    It "Returns bacpac publish options" {
        New-DbaDacOption -Action Publish -Type Bacpac | Should -Not -BeNullOrEmpty
    }
}