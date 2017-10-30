$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
	InModuleScope dbatools {
		Context "Should Pass an unadulterated history object" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            
            Mock Connect-SqlInstance { $true }
            Mock Get-DbaDatabase { $null }
            Mock Get-DbaDatabaseFile { $null }
            Mock New-DbaSqlDirectory  {$true}
            Mock Test-DbaSqlPath { $False }
            Mock New-DbaSqlDirectory {$True}
            It "Should return fail as backup files don't exist" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist
            } 
        }
    }
}