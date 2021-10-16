$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Path', 'EnableException'

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

    Context "formatting actually works" {
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
        <#
        write-host -fore cyan "w $($wantedContent | convertto-json)"
        write-host -fore cyan "n $($newcontent | convertto-json)"
        write-host -fore cyan "t $($newcontent -eq $wantedContent)"
        #>
        It "should format things according to dbatools standards" {
            $newcontent | Should -Be $wantedContent
        }
        It "should keep the unix EOLs (see #5830)" {
            $newcontentUnix | Should -Be $wantedContent.Replace("`r", "")
        }
    }

}