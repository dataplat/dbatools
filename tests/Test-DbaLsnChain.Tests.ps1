$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Test-DbaLsnChain.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'FilteredRestoreFiles', 'Continue', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag 'IntegrationTests' {
    InModuleScope dbatools {
        Context "General Diff restore" {
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1

            $filteredFiles = $header | Select-DbaBackupInformation
            It "Should Return 7" {
                $FilteredFiles.count | should be 7
            }
            It "Should return True" {
                $Output = Test-DbaLsnChain -FilteredRestoreFiles $FilteredFiles -WarningAction SilentlyContinue
                $Output | Should be True
            }
            $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
            $header = $Header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' }
            $header | Add-Member -Type NoteProperty -Name FullName -Value 1

            $FilteredFiles = $Header | Select-DbaBackupInformation
            It "Should return true if we remove diff backup" {
                $Output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles ($FilteredFiles | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' })
                $Output | Should be True
            }

            It "Should return False (faked lsn)" {
                $FilteredFiles[4].FirstLsn = 2
                $FilteredFiles[4].LastLsn = 1
                $Output = Test-DbaLsnChain -WarningAction SilentlyContinue -FilteredRestoreFiles $FilteredFiles
                $Output | Should be $False
            }
        }
    }
}