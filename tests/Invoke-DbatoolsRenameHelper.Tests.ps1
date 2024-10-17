param($ModuleName = 'dbatools')

Describe "Invoke-DbatoolsRenameHelper" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"

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
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbatoolsRenameHelper
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type FileInfo[] -Mandatory:$false
        }
        It "Should have Encoding as a parameter" {
            $CommandUnderTest | Should -HaveParameter Encoding -Type String -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "replacement actually works" {
        BeforeAll {
            $temppath = Join-Path $TestDrive 'somefile2.ps1'
            [System.IO.File]::WriteAllText($temppath, $content)
            $results = $temppath | Invoke-DbatoolsRenameHelper
            $newcontent = [System.IO.File]::ReadAllText($temppath)
        }

        It "returns 4 results" {
            $results.Count | Should -Be 4
        }

        It "returns the expected results" {
            foreach ($result in $results) {
                $result.Path | Should -Be $temppath
                $result.Pattern | Should -BeIn @("Export-SqlUser", "Find-SqlDuplicateIndex", "UseLastBackups", "NoSystem")
                $result.ReplacedWith | Should -BeIn @("Export-DbaUser", "Find-DbaDbDuplicateIndex", "UseLastBackup", "ExcludeSystemLogins")
            }
        }

        It "returns expected specific results" {
            $result = $results | Where-Object Pattern -eq "Export-SqlUser"
            $result.ReplacedWith | Should -Be "Export-DbaUser"
        }

        It "should return exactly the format we want" -Skip {
            $newcontent | Should -Be $wantedContent
        }
    }
}
