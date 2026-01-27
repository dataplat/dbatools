#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools"
)

BeforeAll {
    $Path = Split-Path -Parent $PSCommandPath
    $ModulePath = (Get-Item $Path).Parent.FullName
    #$ManifestPath = "$ModulePath\$ModuleName.psd1"

    function Split-ArrayInParts($array, [int]$parts) {
        #splits an array in "equal" parts
        $size = $array.Length / $parts
        if ($size -lt 1) { $size = 1 }
        $counter = [PSCustomObject] @{ Value = 0 }
        $groups = $array | Group-Object -Property { [math]::Floor($counter.Value++ / $size) }
        $rtn = @()
        foreach ($g in $groups) {
            $rtn += , @($g.Group)
        }
        $rtn
    }
}

Describe "$ModuleName Aliases" -Tag Aliases, Build {
    ## Get the Aliases that should -Be set from the psm1 file
    BeforeAll {
        $psm1 = Get-Content "$ModulePath\$ModuleName.psm1"
        $Matches = [regex]::Matches($psm1, "AliasName`"\s=\s`"(\w*-\w*)`"")
        $global:Aliases = $Matches.ForEach{ $_.Groups[1].Value }
    }

    It "Should have aliases defined in module" -ForEach $global:Aliases {
        $Alias = $_
        Get-Alias $Alias | Should -Not -BeNullOrEmpty
    }

    It "Should have aliased commands that exist" -ForEach $global:Aliases {
        $Alias = $_
        $Definition = (Get-Alias $Alias).Definition
        Get-Command $Definition -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}


Describe "$ModuleName style" -Tag 'Compliance' {
    <#
    Ensures common formatting standards are applied:
    - OTBS style, courtesy of PSSA's Invoke-Formatter, is what dbatools uses
    - UTF8 without BOM is what is going to be used in PS Core, so we adopt this standard for dbatools
    #>
    BeforeAll {
        $global:AllFiles = Get-ChildItem -Path $ModulePath -File -Recurse -Filter '*.ps*1' | Where-Object Name -ne 'dbatools.ps1'
        $AllFunctionFiles = Get-ChildItem -Path "$ModulePath\public", "$ModulePath\private\functions" -Filter '*.ps*1'

        $maxConcurrentJobs = $env:NUMBER_OF_PROCESSORS
        if (-not $maxConcurrentJobs) { $maxConcurrentJobs = 1 }
        $whatever = Split-ArrayInParts -array $AllFunctionFiles -parts $maxConcurrentJobs
        $jobs = @()
        foreach ($piece in $whatever) {
            $jobs += Start-Job -ScriptBlock {
                foreach ($p in $Args) {
                    $content = Get-Content -Path $p.FullName -Raw -Encoding UTF8
                    $result = Invoke-Formatter -ScriptDefinition $content -Settings CodeFormattingOTBS
                    if ($result -ne $content) {
                        $p
                    }
                }
            } -ArgumentList $piece
        }
        $null = $jobs | Wait-Job #-Timeout 120
        $global:formattingResults = $jobs | Receive-Job
    }

    Context "formatting" {
        It "Should be compliant with OTBS formatting style" -ForEach $global:formattingResults {
            $f = $_
            "$f is not compliant with the OTBS formatting style. Please run Invoke-DbatoolsFormatter against the failing file and commit the changes." | Should -BeNullOrEmpty
        }
    }

    Context "BOM" {
        It "Should not have BOM" -ForEach $global:AllFiles {
            $f = $_
            [byte[]]$byteContent = Get-Content -Path $f.FullName -Encoding Byte -ReadCount 4 -TotalCount 4
            $hasBOM = $byteContent.Length -gt 2 -and $byteContent[0] -eq 0xef -and $byteContent[1] -eq 0xbb -and $byteContent[2] -eq 0xbf
            if ($hasBOM) {
                "$f has BOM in it" | Should -BeNullOrEmpty
            }
        }
    }


    Context "indentation" {
        It "Should not have leading tabs" -ForEach $global:AllFiles {
            $f = $_
            $LeadingTabs = Select-String -Path $f -Pattern '^[\t]+'
            if ($LeadingTabs.Count -gt 0) {
                "$f is indented with tabs (line(s) $($LeadingTabs.LineNumber -join ','))" | Should -BeNullOrEmpty
            }
        }

        It "Should not have trailing spaces" -ForEach $global:AllFiles {
            $f = $_
            $TrailingSpaces = Select-String -Path $f -Pattern '([^ \t\r\n])[ \t]+$'
            if ($TrailingSpaces.Count -gt 0) {
                "$f has trailing spaces (line(s) $($TrailingSpaces.LineNumber -join ','))" | Should -BeNullOrEmpty
            }
        }
    }
}


Describe "$ModuleName style" -Tag 'Compliance' {
    <#
    Ensures avoiding already discovered pitfalls
    #>
    BeforeAll {
        $global:AllPublicFunctions = Get-ChildItem -Path "$ModulePath\public" -Filter '*.ps*1'
    }

    Context "NoCompatibleTLS" {
        # .NET defaults clash with recent TLS hardening (e.g. no TLS 1.2 by default)
        It "Should use Invoke-TlsWebRequest instead of WebRequest/WebClient" -ForEach $global:AllPublicFunctions {
            $f = $_
            $NotAllowed = Select-String -Path $f -Pattern 'Invoke-WebRequest | New-Object System.Net.WebClient|\.DownloadFile'
            if ($NotAllowed.Count -gt 0 -and $f.Name -notmatch 'DbaKbUpdate') {
                "$f should instead use Invoke-TlsWebRequest, see #4250" | Should -BeNullOrEmpty
            }
        }
    }
    Context "Shell.Application" {
        # Not every PS instance has Shell.Application
        It "Should not use Shell.Application" -ForEach $global:AllPublicFunctions {
            $f = $_
            $NotAllowed = Select-String -Path $f -Pattern 'shell.application'
            if ($NotAllowed.Count -gt 0) {
                "$f should not use Shell.Application (usually fallbacks for Expand-Archive, which dbatools ships), see #4800" | Should -BeNullOrEmpty
            }
        }
    }

}


Describe "$ModuleName ScriptAnalyzerErrors" -Tag 'Compliance' {
    BeforeAll {
        $global:ScriptAnalyzerErrors = @()
        $global:ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\public" -Severity Error
        $global:ScriptAnalyzerErrors += Invoke-ScriptAnalyzer -Path "$ModulePath\private\functions" -Severity Error
    }
    Context "Errors" {
        It "Should not have ScriptAnalyzer errors" -ForEach $global:ScriptAnalyzerErrors {
            $err = $_
            "$($err.scriptName) has Error(s) : $($err.RuleName) - $($err.Message)" | Should -BeNullOrEmpty
        }
    }
}

Describe "$ModuleName Tests missing" -Tag 'Tests' {
    BeforeAll {
        $global:functions = Get-ChildItem "$ModulePath\public\" -Recurse -Include *.ps1
    }
    Context "Every function should have tests" {
        It "Should have a tests.ps1 file" -ForEach $global:functions {
            $f = $_
            Test-Path "$ModulePath\tests\$($f.basename).tests.ps1" | Should -Be $true
        }

        It "Should have validate parameters unit test" -ForEach $global:functions {
            $f = $_
            if (Test-Path "$ModulePath\tests\$($f.basename).tests.ps1") {
                $testFile = Get-Content "$ModulePath\tests\$($f.basename).Tests.ps1" -Raw
                $hasValidation = $testFile -match 'Context "Validate parameters"' -or $testFile -match 'Context "Parameter validation"'
                $hasValidation | Should -Be $true -Because "Test file must have parameter validation"
            }
        }
    }
}

Describe "$ModuleName Function Name" -Tag 'Compliance' {
    BeforeAll {
        $global:FunctionNameMatchesErrors = @()
        $global:FunctionNameDbaErrors = @()
        foreach ($item in (Get-ChildItem -Path "$ModulePath\public" -Filter '*.ps*1')) {
            $Tokens = $null
            $Errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$Tokens, [ref]$Errors)
            $FunctionName = $Ast.EndBlock.Statements.Name
            $BaseName = $item.BaseName
            if ($FunctionName -cne $BaseName) {
                $global:FunctionNameMatchesErrors += [PSCustomObject]@{
                    FunctionName = $FunctionName
                    BaseName     = $BaseName
                    Message      = "$FunctionName is not equal to $BaseName"
                }
            }
            If ($FunctionName -NotMatch "-Dba") {
                $global:FunctionNameDbaErrors += [PSCustomObject]@{
                    FunctionName = $FunctionName
                    Message      = "$FunctionName does not contain -Dba"
                }

            }
        }
        foreach ($item in (Get-ChildItem -Path "$ModulePath\private\functions" -Filter '*.ps*1' | Where-Object BaseName -ne 'Where-DbaObject')) {
            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$Tokens, [ref]$Errors)
            $FunctionName = $Ast.EndBlock.Statements.Name
            $BaseName = $item.BaseName
            if ($FunctionName -cne $BaseName) {
                Write-Host "aaa $functionname bbb $basename"
                $global:FunctionNameMatchesErrors += [PSCustomObject]@{
                    FunctionName = $FunctionName
                    BaseName     = $BaseName
                    Message      = "$FunctionName is not equal to $BaseName"
                }
            }
        }
    }
    Context "Function Name Matching Filename Errors" {
        It "Function name should match filename" -ForEach $global:FunctionNameMatchesErrors {
            $err = $_
            "$($err.FunctionName) is not equal to $($err.BaseName)" | Should -BeNullOrEmpty
        }
    }
    Context "Function Name has -Dba in it" {
        It "Function name should contain -Dba" -ForEach $global:FunctionNameDbaErrors {
            $err = $_
            "$($err.FunctionName) does not contain -Dba" | Should -BeNullOrEmpty
        }
    }
}

# test the module manifest - exports the right functions, processes the right formats, and is generally correct
<#
Describe "Manifest" {

    $global:Manifest = $null

    It "has a valid manifest" {

        {

            $global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop -WarningAction SilentlyContinue

        } | Should -Not -Throw

    }
## Should -Be fixed now - Until the issue with requiring full paths for required assemblies is resolved need to keep this commented out RMS 01112016

$global:Manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction SilentlyContinue
    It "has a valid name" {

        $global:Manifest.Name | Should -Be $ModuleName

    }



    It "has a valid root module" {

        $global:Manifest.RootModule | Should -Be "$ModuleName.psm1"

    }



    It "has a valid Description" {

        $global:Manifest.Description | Should -Be 'Provides extra functionality for SQL Server Database admins and enables SQL Server instance migrations.'

    }

    It "has a valid Author" {
        $global:Manifest.Author | Should -Be 'Chrissy LeMaire'
    }

    It "has a valid Company Name" {
        $global:Manifest.CompanyName | Should -Be 'dbatools.io'
    }
    It "has a valid guid" {

        $global:Manifest.Guid | Should -Be '9d139310-ce45-41ce-8e8b-d76335aa1789'

    }
    It "has valid PowerShell version" {
        $global:Manifest.PowerShellVersion | Should -Be '3.0'
    }

    It "has valid  required assemblies" {
        $global:Manifest.RequiredAssemblies | Should -BeEmpty
    }

    It "has a valid copyright" {

        $global:Manifest.CopyRight | Should -BeLike '* Chrissy LeMaire'

    }



 # Don't want this just yet

    It 'exports all public functions' {

        $FunctionFiles = Get-ChildItem "$ModulePath\public" -Filter *.ps1 | Select-Object -ExpandProperty BaseName

        $FunctionNames = $FunctionFiles

        $ExFunctions = $global:Manifest.ExportedFunctions.Values.Name
        $ExFunctions
        foreach ($FunctionName in $FunctionNames)

        {

            $ExFunctions -contains $FunctionName | Should -Be $true

        }

    }
}
#>