$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'Session', 'Path', 'FilePath', 'Encoding', 'Passthru', 'BatchSeparator', 'NoPrefix', 'NoClobber', 'Append', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}


Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_XE_CustomFile.sql"
    }
    AfterAll {
        (Get-ChildItem $outputFile -ErrorAction SilentlyContinue) | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "Check if output file was created" {
        $null = Export-DbaXESession -SqlInstance $script:instance2 -FilePath $outputFile
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
        }
    }

    Context "Check if session parameter is honored" {
        $null = Export-DbaXESession -SqlInstance $script:instance2 -FilePath $outputFile -Session system_health
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
        }
    }

    Context "Check if supports Pipeline input" {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session system_health | Export-DbaXESession -FilePath $outputFile
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should BeGreaterThan 0
        }
    }
}