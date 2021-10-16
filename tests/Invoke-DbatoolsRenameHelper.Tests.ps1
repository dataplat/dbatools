$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'InputObject', 'Encoding', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}


Describe "$CommandName IntegrationTests" -Tag "IntegrationTests" {
    $content = @'
function Get-DbaStub {
    <#
        .SYNOPSIS
            is a stub

        .DESCRIPTION
            Using
    #>
    process {
        do this UseLastBackups
        then Find-SqlDuplicateIndex
        or Export-SqlUser -NoSystemLogins
        Write-Message -Level Verbose "stub"
    }
}
'@

    $wantedContent = @'
function Get-DbaStub {
    <#
        .SYNOPSIS
            is a stub

        .DESCRIPTION
            Using
    #>
    process {
        do this UseLastBackup
        then Find-DbaDbDuplicateIndex
        or Export-DbaUser -ExcludeSystemLogins
        Write-Message -Level Verbose "stub"
    }
}

'@

    Context "replacement actually works" {
        $temppath = Join-Path $TestDrive 'somefile2.ps1'
        [System.IO.File]::WriteAllText($temppath, $content)
        $results = $temppath | Invoke-DbatoolsRenameHelper
        $newcontent = [System.IO.File]::ReadAllText($temppath)

        It "returns 4 results" {
            $results.Count | Should -Be 4
        }

        foreach ($result in $results) {
            It "returns the expected results" {
                $result.Path | Should -Be $temppath
                $result.Pattern -in "Export-SqlUser", "Find-SqlDuplicateIndex", "UseLastBackups", "NoSystem" | Should -Be $true
                $result.ReplacedWith -in "Export-DbaUser", "Find-DbaDbDuplicateIndex", "UseLastBackup", "ExcludeSystemLogins" | Should -Be $true
            }
        }

        It "returns expected specific results" {
            $result = $results | Where-Object Pattern -eq "Export-SqlUser"
            $result.ReplacedWith | Should -Be "Export-DbaUser"
        }

        It -Skip "should return exactly the format we want" {
            $newcontent | Should -Be $wantedContent
        }
    }
}