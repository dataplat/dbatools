param($ModuleName = 'dbatools')

Describe "Invoke-DbatoolsFormatter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
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
        Write-Message -Level Verbose "stub"
}}


'@
        #ensure empty lines also at the end
        $content = $content + "`r`n    `r`n"
        $wantedContent = @'
function Get-DbaStub {
    <#
        .SYNOPSIS
            is a stub

        .DESCRIPTION
            Using
    #>
    process {
        Write-Message -Level Verbose "stub"
    }
}
'@
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbatoolsFormatter
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "Path",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "formatting actually works" {
        BeforeAll {
            $temppath = Join-Path $TestDrive 'somefile.ps1'
            $temppathUnix = Join-Path $TestDrive 'somefileUnixeol.ps1'
            ## Set-Content adds a newline...WriteAllText() doesn't
            #Set-Content -Value $content -Path $temppath
            [System.IO.File]::WriteAllText($temppath, $content)
            [System.IO.File]::WriteAllText($temppathUnix, $content.Replace("`r", ""))
            Invoke-DbatoolsFormatter -Path $temppath
            Invoke-DbatoolsFormatter -Path $temppathUnix
            $newcontent = [System.IO.File]::ReadAllText($temppath)
            $newcontentUnix = [System.IO.File]::ReadAllText($temppathUnix)
        }

        It "should format things according to dbatools standards" {
            $newcontent | Should -Be $wantedContent
        }
        It "should keep the unix EOLs (see #5830)" {
            $newcontentUnix | Should -Be $wantedContent.Replace("`r", "")
        }
    }
}
