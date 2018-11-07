$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 2
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Invoke-DbatoolsFormatter).Parameters.Keys
        $knownParameters = 'Path','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should -Be $paramCount
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
        ## Set-Content adds a newline...WriteAllText() doesn't
        #Set-Content -Value $content -Path $temppath
        [System.IO.File]::WriteAllText($temppath, $content)
        Invoke-DbatoolsFormatter -Path $temppath
        $newcontent = [System.IO.File]::ReadAllText($temppath)
        <#
        write-host -fore cyan "w $($wantedContent | convertto-json)"
        write-host -fore cyan "n $($newcontent | convertto-json)"
        write-host -fore cyan "t $($newcontent -eq $wantedContent)"
        #>
        It "should format things according to dbatools standards" {
            $newcontent | Should -Be $wantedContent
        }
    }

}