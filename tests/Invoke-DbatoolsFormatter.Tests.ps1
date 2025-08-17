#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbatoolsFormatter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $content = @"
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


"@
        #ensure empty lines also at the end
        $content = $content + "`r`n    `r`n"
        $wantedContent = @"
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
"@
    }

    Context "formatting actually works" {
        BeforeAll {
            $temppath = Join-Path $TestDrive "somefile.ps1"
            $temppathUnix = Join-Path $TestDrive "somefileUnixeol.ps1"
            ## Set-Content adds a newline...WriteAllText() doesn't
            #Set-Content -Value $content -Path $temppath
            [System.IO.File]::WriteAllText($temppath, $content)
            [System.IO.File]::WriteAllText($temppathUnix, $content.Replace("`r", ""))
            Invoke-DbatoolsFormatter -Path $temppath
            Invoke-DbatoolsFormatter -Path $temppathUnix
            $newcontent = [System.IO.File]::ReadAllText($temppath)
            $newcontentUnix = [System.IO.File]::ReadAllText($temppathUnix)
            <#
            write-host -fore cyan "w $($wantedContent | convertto-json)"
            write-host -fore cyan "n $($newcontent | convertto-json)"
            write-host -fore cyan "t $($newcontent -eq $wantedContent)"
            #>
        }

        It "Should format things according to dbatools standards" {
            $newcontent | Should -Be $wantedContent
        }
        It "Should keep the unix EOLs (see #5830)" {
            $newcontentUnix | Should -Be $wantedContent.Replace("`r", "")
        }
    }

    AfterAll {
        # TestDrive is automatically cleaned up by Pester, but adding explicit cleanup for consistency
        # No additional cleanup needed as TestDrive handles temporary file cleanup
    }
}